// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {Setup} from "./Setup.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {IMarketOracle} from "@project/interfaces/IMarketOracle.sol";
import {IPriceOracle} from "@project/interfaces/IPriceOracle.sol";
import {State} from "./State.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {DVPUtils} from "../../utils/DVPUtils.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {TestOptionsFinanceHelper} from "../lib/TestOptionsFinanceHelper.sol";
import {FinanceIG, FinanceParameters, VolatilityParameters, TimeLockedFinanceValues} from "@project/lib/FinanceIG.sol";
import {Amount} from "@project/lib/Amount.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {EchidnaVaultUtils} from "../lib/EchidnaVaultUtils.sol";
import {WadTime} from "@project/lib/WadTime.sol";
import {FinanceIGPrice} from "@project/lib/FinanceIGPrice.sol";

/**
 * medusa fuzz --no-color
 * echidna . --contract CryticTester --config config.yaml
 */
abstract contract TargetFunctions is BaseTargetFunctions, State {
    mapping(address => bool) internal _pendingWithdraw;
    mapping(bytes32 => uint256) public calls;

    function setup() internal virtual override {
        deploy();
        _initializeProperties();
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    //----------------------------------------------
    // USER OPs.
    //----------------------------------------------

    function buyBull(uint256 input) public countCall("buyBull") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_BULL, input);
        DVPUtils.logState(ig);
        console.log("** BUY BULL", amount_.up);
        _buy(amount_, _BULL);
    }

    function buyBear(uint256 input) public countCall("buyBear") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_BEAR, input);
        DVPUtils.logState(ig);
        console.log("** BUY BEAR", amount_.down);
        _buy(amount_, _BEAR);
    }

    function buySmilee(uint256 input) public countCall("buySmilee") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_SMILEE, input);
        DVPUtils.logState(ig);
        console.log("** BUY SMILEE");
        _buy(amount_, _SMILEE);
    }

    function sellBull(uint256 index) public countCall("sellBull") {
        precondition(!vault.paused() && !ig.paused());
        precondition(bullTrades.length > 0);
        index = _between(index, 0, bullTrades.length - 1);
        BuyInfo storage buyInfo_ = bullTrades[index];

        console.log("** SELL BULL", buyInfo_.amountUp);
        _sell(buyInfo_);
        _popTrades(index, buyInfo_);
    }

    function sellBear(uint256 index) public countCall("sellBear") {
        precondition(!vault.paused() && !ig.paused());
        precondition(bearTrades.length > 0);
        index = _between(index, 0, bearTrades.length - 1);
        BuyInfo storage buyInfo_ = bearTrades[index];

        console.log("** SELL BEAR", buyInfo_.amountDown);
        _sell(buyInfo_);
        _popTrades(index, buyInfo_);
    }

    function sellSmilee(uint256 index) public countCall("sellSmilee") {
        precondition(!vault.paused() && !ig.paused());
        precondition(smileeTrades.length > 0);
        index = _between(index, 0, smileeTrades.length - 1);
        BuyInfo storage buyInfo_ = smileeTrades[index];

        console.log("** SELL SMILEE", buyInfo_.amountUp + buyInfo_.amountDown);
        _sell(buyInfo_);

        _popTrades(index, buyInfo_);
    }

    //----------------------------------------------
    // ADMIN OPs.
    //----------------------------------------------

    function callAdminFunction(uint256 input) public {
        emit Debug("_setTokenPrice()");
        _setTokenPrice(input);
    }

    function _getTokenPrice(address tokenAddress) internal view returns (uint256 tokenPrice) {
        IPriceOracle apPriceOracle = IPriceOracle(ap.priceOracle());
        tokenPrice = apPriceOracle.getPrice(tokenAddress, vault.baseToken());
    }

    function _setTokenPrice(uint256 price) internal countCall("setTokenPrice") {
        TestnetPriceOracle apPriceOracle = TestnetPriceOracle(ap.priceOracle());
        address sideToken = vault.sideToken();
        uint256 prevPrice = _getTokenPrice(sideToken);

        price = _between(price, MIN_TOKEN_PRICE, MAX_TOKEN_PRICE);
        console.log("** PREVIOUS TOKEN PRICE", prevPrice);
        console.log("** SET TOKEN PRICE", price);
        hevm.prank(admin);
        apPriceOracle.setTokenPrice(sideToken, price);
    }


    function _getRiskFreeRate(address tokenAddress) internal view returns (uint256 riskFreeRate) {
        IMarketOracle marketOracle = IMarketOracle(ap.marketOracle());
        riskFreeRate = marketOracle.getRiskFreeRate(tokenAddress);
    }

    function _boundBuyInput(uint8 buyType, uint256 input) internal view returns (Amount memory amount) {
        (, , uint256 bearAvailNotional, uint256 bullAvailNotional) = ig.notional();
        uint256 availNotional;
        uint256 amountUp = 0;
        uint256 amountDown = 0;

        if (buyType == _BULL) {
            amountUp = _between(input, MIN_OPTION_BUY, bullAvailNotional);
        } else if (buyType == _BEAR) {
            amountDown = _between(input, MIN_OPTION_BUY, bearAvailNotional);
        } else {
            availNotional = bearAvailNotional;
            if (bullAvailNotional < availNotional) {
                availNotional = bullAvailNotional;
            }
            amountUp = _between(input, MIN_OPTION_BUY, availNotional);
            amountDown = amountUp;
        }

        amount = Amount(amountUp, amountDown);
    }

    //----------------------------------------------
    // COMMON
    //----------------------------------------------

    function _buy(Amount memory amount, uint8 buyType) internal returns (uint256) {
        console.log("*** AMOUNT UP", amount.up);
        console.log("*** AMOUNT DOWN", amount.down);
        console.log(
            "*** TRADE TIME ELAPSED FROM EPOCH",
            block.timestamp - (ig.getEpoch().current - ig.getEpoch().frequency)
        );

        uint256 buyTokenPrice = _getTokenPrice(vault.sideToken());

        (uint256 expectedPremium, ) = ig.premium(ig.currentStrike(), amount.up, amount.down);
        precondition(expectedPremium > 100); // Slippage has no influence for value <= 100
        (uint256 sigma, ) = ig.getPostTradeVolatility(ig.currentStrike(), amount, true);
        uint256 maxPremium = expectedPremium + (ACCEPTED_SLIPPAGE * expectedPremium) / 1e18;

        if (msg.sender != USER1) {
            TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(ig), maxPremium, _convertVm());
        }

        uint256 premium;
        // uint256 positiontokenId;

        // try pm.mint(IPositionManager.MintParams({
        //         dvpAddr: address(ig),
        //         notionalUp: amount.up,
        //         notionalDown: amount.down,
        //         strike: ig.currentStrike(),
        //         recipient: msg.sender,
        //         tokenId: 0,
        //         expectedPremium: expectedPremium,
        //         maxSlippage: ACCEPTED_SLIPPAGE,
        //         nftAccessTokenId: 0
        //     })) returns (uint256 _positiontokenId, uint256 _premium) {
        //         premium = _premium;
        //         positionTokenId = _positionTokenId;
        //     } catch (bytes memory err) {
        //         if (!FLAG_SLIPPAGE) {
        //             _shouldNotRevertUnless(err, _GENERAL_6);
        //         } else {
        //             revert(string(err));
        //         }
        //     }
        uint256 currentStrike = ig.currentStrike();

        hevm.prank(msg.sender);
        premium = ig.mint(msg.sender, currentStrike, amount.up, amount.down, expectedPremium, ACCEPTED_SLIPPAGE, 0);
        VaultUtils.logState(vault);

        BuyInfo memory buyInfo = BuyInfo(
            0,
            msg.sender,
            ig.getEpoch().current,
            epochs.length,
            amount.up,
            amount.down,
            ig.currentStrike(),
            premium,
            ig.getUtilizationRate(),
            buyTokenPrice,
            expectedPremium,
            buyType,
            sigma,
            block.timestamp,
            _getRiskFreeRate(address(baseToken)),
            WadTime.yearsToTimestamp(ig.getEpoch().current)
        );

        _pushTrades(buyInfo);
        lastBuy = buyInfo;

        return premium;
    }

    function _sell(BuyInfo memory buyInfo_) internal returns (uint256) {
        console.log(
            "*** TRADE TIME ELAPSED FROM EPOCH",
            block.timestamp - (ig.getEpoch().current - ig.getEpoch().frequency)
        );
        uint256 sellTokenPrice = _getTokenPrice(vault.sideToken());

        // if one epoch have passed, get end price from current epoch
        if (epochs.length == buyInfo_.epochCounter + 1) {
            sellTokenPrice = ig.currentStrike();
        }

        // if more epochs have passed, get end price from trade subsequent epoch
        if (epochs.length > buyInfo_.epochCounter + 1) {
            EpochInfo storage epochInfo_ = epochs[buyInfo_.epochCounter + 1];
            sellTokenPrice = epochInfo_.epochStrike;
        }

        hevm.prank(buyInfo_.recipient);
        (uint256 expectedPayoff, ) = ig.payoff(
            buyInfo_.epoch,
            buyInfo_.strike,
            buyInfo_.amountUp,
            buyInfo_.amountDown
        );

        hevm.prank(buyInfo_.recipient);
        uint256 payoff = ig.burn(
                buyInfo_.epoch,
                buyInfo_.recipient,
                buyInfo_.strike,
                buyInfo_.amountUp,
                buyInfo_.amountDown,
                expectedPayoff,
                ACCEPTED_SLIPPAGE
            );

        uint256 currentTimestamp = block.timestamp;
        if (msg.sender == USER1 && currentTimestamp == buyInfo_.timestamp && _getTokenPrice(vault.sideToken()) == buyInfo_.buyTokenPrice) {
            _checkPnL();
        }

        return payoff;
    }

    //----------------------------------------------
    // PRECONDITIONS
    //----------------------------------------------

    function _buyPreconditions() internal {
        precondition(!vault.paused() && !ig.paused());
        precondition(block.timestamp < ig.getEpoch().current);
        uint256 totalDeposit = VaultUtils.getState(vault).liquidity.totalDeposit;
        precondition(totalDeposit > 0);
    }

    //----------------------------------------------
    // INVARIANTS ASSERTIONS
    //----------------------------------------------


    function _checkPnL() internal {
        uint256 balance = baseToken.balanceOf(USER1);
        t(int256(USER1_INITIAL_BALANCE - balance) <= 0 , "PANPROG");
    }
}
