// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {Setup} from "./Setup.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {IMarketOracle} from "@project/interfaces/IMarketOracle.sol";
import {IPositionManager} from "@project/interfaces/IPositionManager.sol";
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

    string INVARIANT_PNL = "PNL CAN NEVER BE GREATER THAN ZERO IF PRICE DOESN'T CHANGE AND TIME DOESN'T PASS";

    //----------------------------------------------
    // USER OPs.
    //----------------------------------------------

    function buyBull(uint256 input) public countCall("buyBull") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_BULL, input);
        DVPUtils.logState(ig);
        console.log("** BUY BULL", amount_.up);
        _buy(amount_);
    }

    function buyBear(uint256 input) public countCall("buyBear") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_BEAR, input);
        DVPUtils.logState(ig);
        console.log("** BUY BEAR", amount_.down);
        _buy(amount_);
    }

    function buySmilee(uint256 input) public countCall("buySmilee") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_SMILEE, input);
        DVPUtils.logState(ig);
        console.log("** BUY SMILEE");
        _buy(amount_);
    }

    function sellBull(uint256 index, uint256 amount) public countCall("sellBull") {
        precondition(!vault.paused() && !ig.paused());
        precondition(bullTrades.length > 0);
        index = _between(index, 0, bullTrades.length - 1);
        BuyInfo storage buyInfo_ = bullTrades[index];

        console.log("** SELL BULL", buyInfo_.amountUp);

        Amount memory amountToSell = Amount(_between(amount, 0, buyInfo_.amountUp), 0);
        _sell(buyInfo_, amountToSell);
        _popTrades(index, buyInfo_, amountToSell.up);
    }

    function sellBear(uint256 index, uint256 amount) public countCall("sellBear") {
        precondition(!vault.paused() && !ig.paused());
        precondition(bearTrades.length > 0);
        index = _between(index, 0, bearTrades.length - 1);
        BuyInfo storage buyInfo_ = bearTrades[index];

        console.log("** SELL BEAR", buyInfo_.amountDown);

        Amount memory amountToSell = Amount(0, _between(amount, 0, buyInfo_.amountDown));
        _sell(buyInfo_, amountToSell);
        _popTrades(index, buyInfo_, amountToSell.down);
    }

    function sellSmilee(uint256 index, uint256 amount) public countCall("sellSmilee") {
        precondition(!vault.paused() && !ig.paused());
        precondition(smileeTrades.length > 0);
        index = _between(index, 0, smileeTrades.length - 1);
        BuyInfo storage buyInfo_ = smileeTrades[index];

        console.log("** SELL SMILEE", buyInfo_.amountUp + buyInfo_.amountDown);

        amount = _between(amount, 0, buyInfo_.amountUp);
        Amount memory amountToSell = Amount(amount, amount);
        _sell(buyInfo_, amountToSell);
        _popTrades(index, buyInfo_, amountToSell.up);
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

    function _buy(Amount memory amount) internal returns (uint256) {
        console.log("*** AMOUNT UP", amount.up);
        console.log("*** AMOUNT DOWN", amount.down);
        console.log("*** TRADE TIME ELAPSED FROM EPOCH", block.timestamp - (ig.getEpoch().current - ig.getEpoch().frequency));

        uint256 buyTokenPrice = _getTokenPrice(vault.sideToken());
        (uint256 expectedPremium, ) = ig.premium(ig.currentStrike(), amount.up, amount.down);
        precondition(expectedPremium > 100); // Slippage has no influence for value <= 100
        uint256 maxPremium = expectedPremium + (ACCEPTED_SLIPPAGE * expectedPremium) / 1e18;

        if (msg.sender != USER1) {
            TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(pm), maxPremium, _convertVm());
        }

        uint256 strike = ig.currentStrike();
        hevm.prank(msg.sender);
        (uint256 tokenId, uint256 premium) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: amount.up,
                notionalDown: amount.down,
                strike: strike,
                recipient: msg.sender,
                tokenId: 0,
                expectedPremium: expectedPremium,
                maxSlippage: ACCEPTED_SLIPPAGE,
                nftAccessTokenId: 0
            })
        );
        BuyInfo memory buyInfo = BuyInfo(tokenId, msg.sender, premium, amount.up, amount.down, block.timestamp, buyTokenPrice);
        VaultUtils.logState(vault);

        _pushTrades(buyInfo);
        lastBuy = buyInfo;

        return premium;
    }

    function _sell(BuyInfo memory buyInfo_, Amount memory amountToSell) internal returns (uint256) {
        console.log("*** TRADE TIME ELAPSED FROM EPOCH", block.timestamp - (ig.getEpoch().current - ig.getEpoch().frequency));

        hevm.prank(buyInfo_.recipient);
        (uint256 expectedPayoff, ) = pm.payoff(buyInfo_.tokenId, amountToSell.up, amountToSell.down);

        hevm.prank(buyInfo_.recipient);
        uint256 payoff = pm.sell(
            IPositionManager.SellParams({
                tokenId: buyInfo_.tokenId,
                notionalUp: amountToSell.up,
                notionalDown: amountToSell.down,
                expectedMarketValue: expectedPayoff,
                maxSlippage: ACCEPTED_SLIPPAGE
            })
        );

        uint256 currentTimestamp = block.timestamp;
        // User PnL can never be greater than 0 if price doesn't change and time doesn't pass
        if (buyInfo_.recipient == USER1 && currentTimestamp == buyInfo_.timestamp && _getTokenPrice(vault.sideToken()) == buyInfo_.buyTokenPrice) {
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
        t(int256(balance) - int256(USER1_INITIAL_BALANCE) <= 0, INVARIANT_PNL);
    }
}
