// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    Amount totalAmountBought; // intra epoch

    function setup() internal virtual override {
        deploy();
        _initializeProperties();
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    //----------------------------------------------
    // VAULT
    //----------------------------------------------
    function deposit(uint256 amount) public countCall("deposit") {
        precondition(!vault.paused());
        // precondition revert ExceedsMaxDeposit
        uint256 totalDeposit = VaultUtils.getState(vault).liquidity.totalDeposit;
        uint256 maxDeposit = vault.maxDeposit();
        uint256 depositCapacity = maxDeposit - totalDeposit;
        uint256 minVaultDeposit = totalDeposit == 0 ? BT_UNIT : MIN_VAULT_DEPOSIT;
        amount = _between(amount, minVaultDeposit, depositCapacity);

        console.log("--- VAULT STATE PRE DEPOSIT ---");
        VaultUtils.logState(vault);
        console.log("------");

        precondition(block.timestamp < ig.getEpoch().current);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(vault), amount, _convertVm());

        console.log("** DEPOSIT", amount);
        hevm.prank(msg.sender);
        try vault.deposit(amount, msg.sender, 0) {} catch (bytes memory err) {
            if (!FLAG_SLIPPAGE) {
                _shouldNotRevertUnless(err, _GENERAL_1);
            } else {
                revert(string(err));
            }
        }

        _depositInfo.push(DepositInfo(msg.sender, amount, ig.getEpoch().current));
        if (firstDepositEpoch < 0) {
            firstDepositEpoch = int256(epochs.length);
        }
        console.log("--- VAULT STATE AFTER DEPOSIT ---");
        VaultUtils.logState(vault);
        console.log("------");
    }

    function redeem(uint256 index) public countCall("redeem") {
        precondition(!vault.paused());
        precondition(_depositInfo.length > 0);
        index = _between(index, 0, _depositInfo.length - 1);
        precondition(block.timestamp < ig.getEpoch().current); // EpochFinished()

        DepositInfo storage depInfo = _depositInfo[index];
        (uint256 heldByUser, uint256 heldByVault) = vault.shareBalances(depInfo.user);
        precondition(heldByVault > 0); // can't redeem shares before mint (before epoch roll)

        console.log("** REDEEM", heldByVault);
        hevm.prank(depInfo.user);
        try vault.redeem(heldByVault) {} catch (bytes memory err) {
            if (!FLAG_SLIPPAGE) {
                _shouldNotRevertUnless(err, _GENERAL_1);
            } else {
                revert(string(err));
            }
        }

        eq(vault.balanceOf(depInfo.user), heldByUser + heldByVault, "");
    }

    function initiateWithdraw(uint256 index) public countCall("initiateWithdraw") {
        precondition(!vault.paused());
        precondition(_depositInfo.length > 0);
        index = _between(index, 0, _depositInfo.length - 1);
        precondition(block.timestamp < ig.getEpoch().current); // EpochFinished()

        DepositInfo storage depInfo = _depositInfo[index];

        precondition(!_pendingWithdraw[depInfo.user]); // ExistingIncompleteWithdraw()
        (uint256 heldByUser, uint256 heldByVault) = vault.shareBalances(depInfo.user);
        uint256 sharesToWithdraw = heldByUser + heldByVault;
        precondition(sharesToWithdraw > 0); // AmountZero()

        sharesToWithdraw = sharesToWithdraw - (sharesToWithdraw / 10000); // see test_27

        console.log("--- VAULT STATE PRE INITIATE WITHDRAW ---");
        VaultUtils.logState(vault);
        console.log("------");

        console.log("** INITIATE WITHDRAW", sharesToWithdraw);

        hevm.prank(depInfo.user);
        try vault.initiateWithdraw(sharesToWithdraw) {} catch (bytes memory err) {
            if (!FLAG_SLIPPAGE) {
                _shouldNotRevertUnless(err, _GENERAL_1);
            } else {
                revert(string(err));
            }
        }

        _pendingWithdraw[depInfo.user] = true;
        withdrawals.push(WithdrawInfo(depInfo.user, sharesToWithdraw, epochs.length));
        _popDepositInfo(index);
        console.log("--- VAULT STATE AFTER INITIATE WITHDRAW ---");
        VaultUtils.logState(vault);
        console.log("------");
    }

    function completeWithdraw(uint256 index) public countCall("completeWithdraw") {
        precondition(!vault.paused());
        precondition(withdrawals.length > 0);
        index = _between(index, 0, withdrawals.length - 1);

        WithdrawInfo storage withdrawInfo = withdrawals[index];
        precondition(withdrawInfo.epochCounter < epochs.length); // WithdrawTooEarly()

        uint256 initialUserBalance = baseToken.balanceOf(withdrawInfo.user);
        (uint256 withdrawEpoch, ) = vault.withdrawals(withdrawInfo.user);
        uint256 epochSharePrice = vault.epochPricePerShare(withdrawEpoch);
        uint256 expectedAmountToWithdraw = (withdrawInfo.amount * epochSharePrice) / BT_UNIT;

        console.log("** WITHDRAW", expectedAmountToWithdraw);
        hevm.prank(withdrawInfo.user);
        try vault.completeWithdraw() {} catch (bytes memory err) {
            if (!FLAG_SLIPPAGE) {
                _shouldNotRevertUnless(err, _GENERAL_1);
            } else {
                revert(string(err));
            }
        }

        eq(baseToken.balanceOf(withdrawInfo.user), initialUserBalance + expectedAmountToWithdraw, "");
        _pendingWithdraw[withdrawInfo.user] = false;
        _popWithdrawals(index);
    }

    //----------------------------------------------
    // USER OPs.
    //----------------------------------------------

    function buyBull(uint256 input) public countCall("buyBull") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_BULL, input);
        uint256 tokenPrice = _getTokenPrice(vault.sideToken());
        DVPUtils.logState(ig);

        uint256 strike = ig.currentStrike();
        (uint256 sigma, ) = ig.getPostTradeVolatility(strike, amount_, true);
        uint256 riskFreeRate = _getRiskFreeRate(vault.baseToken());

        console.log("** BUY BULL", amount_.up);
        uint256 premium = _buy(amount_, _BULL);

        (uint256 premiumCallK, uint256 premiumCallKb) = TestOptionsFinanceHelper.equivalentOptionPremiums(
            _BULL,
            amount_.up,
            tokenPrice,
            riskFreeRate,
            sigma,
            _initialFinanceParameters
        );

        if (!FLAG_SLIPPAGE) {
            lte(premium, premiumCallK, _IG_05_1.desc);
            gte(premium, premiumCallKb, _IG_05_2.desc);
        }
    }

    function buyBear(uint256 input) public countCall("buyBear") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_BEAR, input);
        uint256 tokenPrice = _getTokenPrice(vault.sideToken());
        DVPUtils.logState(ig);

        uint256 strike = ig.currentStrike();
        (uint256 sigma, ) = ig.getPostTradeVolatility(strike, amount_, true);
        uint256 riskFreeRate = _getRiskFreeRate(vault.baseToken());

        console.log("** BUY BEAR", amount_.down);
        uint256 premium = _buy(amount_, _BEAR);

        (uint256 premiumPutK, uint256 premiumPutKa) = TestOptionsFinanceHelper.equivalentOptionPremiums(
            _BEAR,
            amount_.down,
            tokenPrice,
            riskFreeRate,
            sigma,
            _initialFinanceParameters
        );

        lte(premium, amount_.down, _IG_06.desc);
        if (!FLAG_SLIPPAGE) {
            lte(premium, premiumPutK, _IG_07_1.desc);
            gte(premium, premiumPutKa, _IG_07_2.desc);
        }
    }

    function buySmilee(uint256 input) public countCall("buySmilee") {
        _buyPreconditions();
        Amount memory amount_ = _boundBuyInput(_SMILEE, input);
        uint256 tokenPrice = _getTokenPrice(vault.sideToken());
        DVPUtils.logState(ig);

        uint256 strike = ig.currentStrike();
        (uint256 sigma, ) = ig.getPostTradeVolatility(strike, amount_, true);
        uint256 riskFreeRate = _getRiskFreeRate(vault.baseToken());

        console.log("** BUY SMILEE");
        uint256 premium = _buy(amount_, _SMILEE);

        (uint256 premiumStraddleK, uint256 premiumStrangleKaKb) = TestOptionsFinanceHelper.equivalentOptionPremiums(
            _SMILEE,
            amount_.up, // == amount_.down
            tokenPrice,
            riskFreeRate,
            sigma,
            _initialFinanceParameters
        );

        if (!FLAG_SLIPPAGE) {
            lte(premium, premiumStraddleK, _IG_08_1.desc);
            gte(premium, premiumStrangleKaKb, _IG_08_2.desc);
        }
    }

    function sellBull(uint256 index) public countCall("sellBull") {
        precondition(!vault.paused() && !ig.paused());
        precondition(bullTrades.length > 0);
        index = _between(index, 0, bullTrades.length - 1);
        BuyInfo storage buyInfo_ = bullTrades[index];

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);
        console.log("** SELL BULL", buyInfo_.amountUp);
        uint256 payoff = _sell(buyInfo_, _BULL);

        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, _IG_09.desc);
        _popTrades(index, buyInfo_);
    }

    function sellBear(uint256 index) public countCall("sellBear") {
        precondition(!vault.paused() && !ig.paused());
        precondition(bearTrades.length > 0);
        index = _between(index, 0, bearTrades.length - 1);
        BuyInfo storage buyInfo_ = bearTrades[index];

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);
        console.log("** SELL BEAR", buyInfo_.amountDown);
        uint256 payoff = _sell(buyInfo_, _BEAR);

        lte(payoff, buyInfo_.amountDown, _IG_06.desc);
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, _IG_09.desc);
        _popTrades(index, buyInfo_);
    }

    function sellSmilee(uint256 index) public countCall("sellSmilee") {
        precondition(!vault.paused() && !ig.paused());
        precondition(smileeTrades.length > 0);
        index = _between(index, 0, smileeTrades.length - 1);
        BuyInfo storage buyInfo_ = smileeTrades[index];

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);
        console.log("** SELL SMILEE", buyInfo_.amountUp + buyInfo_.amountDown);
        uint256 payoff = _sell(buyInfo_, _SMILEE);

        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, _IG_09.desc);
        _popTrades(index, buyInfo_);
    }

    //----------------------------------------------
    // ADMIN OPs.
    //----------------------------------------------

    function callAdminFunction(uint256 perc, uint256 input) public {
        perc = _between(perc, 0, 100);

        if (perc < 20) {
            // 20% - Test invariant IG_24_3
            emit Debug("_check_IG_24_3()");
            _check_IG_24_3(input);
        } else if (perc < 40) {
            // 20% - RollEpoch
            emit Debug("_rollEpoch()");
            _rollEpoch();
        } else {
            // 35% - SetTokenPrice
            emit Debug("_setTokenPrice()");
            _setTokenPrice(input);
        }
    }

    function _rollEpoch() internal countCall("rollEpoch") {
        precondition(!vault.paused() && !ig.paused());
        console.log("** STATES PRE ROLLEPOCH");
        VaultUtils.logState(vault);
        DVPUtils.logState(ig);

        uint256 currentEpoch = ig.getEpoch().current;

        _before();

        _rollepochAssertionBefore();

        console.log("** ROLLEPOCH");
        hevm.prank(admin);
        try ig.rollEpoch() {} catch (bytes memory err) {
            if (block.timestamp > currentEpoch) {
                _shouldNotRevertUnless(err, _GENERAL_4);
            }
            _shouldNotRevertUnless(err, _GENERAL_5);
        }

        console.log("************************ SHARE PRICE", vault.epochPricePerShare(ig.getEpoch().previous));
        console.log("** STATES AFTER ROLLEPOCH");
        VaultUtils.logState(vault);
        DVPUtils.logState(ig);

        epochs.push(EpochInfo(currentEpoch, _endingStrike));

        _after();

        _rollepochAssertionAfter();

        totalAmountBought.up = 0;
        totalAmountBought.down = 0;

        {
            uint256 epochsCount = epochs.length;
            if (firstDepositEpoch >= 0 && int256(epochsCount) >= firstDepositEpoch + 2) {
                EpochInfo memory epochInfok0 = epochs[epochsCount - 2]; // previous - 1
                uint256 epochPriceT0 = vault.epochPricePerShare(epochInfok0.epochTimestamp);
                EpochInfo memory epochInfok1 = epochs[epochsCount - 1]; // previous
                uint256 epochPriceT1 = vault.epochPricePerShare(epochInfok1.epochTimestamp);
                int256 vaultPayoffPerc = int256((epochPriceT1 * 1e18) / epochPriceT0) - int256(1e18);

                uint256 lpPayoff = TestOptionsFinanceHelper.lpPayoff(
                    ig.currentStrike(),
                    epochInfok1.epochStrike,
                    _endingFinanceParameters.kA,
                    _endingFinanceParameters.kB,
                    _endingFinanceParameters.theta
                );
                int256 lpPnl = int256(lpPayoff) - 1e18;

                if (!FLAG_SLIPPAGE) {
                    uint256 minExp = 1e18 / 10 ** baseToken.decimals();
                    if (
                        (vaultPayoffPerc <= 0 && lpPnl <= 0) &&
                        (uint256(vaultPayoffPerc * -1) <= minExp) &&
                        (uint256(lpPnl * -1) <= minExp)
                    ) {
                        t(true, _VAULT_01.desc);
                    } else {
                        t(vaultPayoffPerc >= lpPnl, _VAULT_01.desc);
                    }
                }
            }
        }

        // +1 error margin see test_22
        if (!FLAG_SLIPPAGE) {
            gte(
                EchidnaVaultUtils.getAssetsValue(vault, ap) + 1,
                _initialVaultState.liquidity.pendingPayoffs +
                    _initialVaultState.liquidity.pendingWithdrawals +
                    _initialVaultState.liquidity.pendingDeposits +
                    ((_initialVaultTotalSupply - _initialVaultState.withdrawals.heldShares) *
                        vault.epochPricePerShare(ig.getEpoch().previous)) /
                    BT_UNIT,
                _VAULT_03.desc
            );
        }
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

    function _check_IG_24_3(uint256 input) internal {
        precondition(ig.getEpoch().current - block.timestamp > MIN_TIME_WARP);
        console.log("** FORCE SKIP TIME");

        uint256 currentStrike = ig.currentStrike();
        Amount memory amountBull = _boundBuyInput(_BULL, input);

        (uint256 bullEP, ) = ig.premium(currentStrike, amountBull.up, amountBull.down);

        // force a time warp between the current timestamp and the end of the epoch
        uint256 timeToSkip = _between(input, MIN_TIME_WARP, ig.getEpoch().current - block.timestamp);
        uint256 currentTimestamp = block.timestamp;
        hevm.warp(currentTimestamp + timeToSkip);

        (uint256 bullEPAfter, ) = ig.premium(currentStrike, amountBull.up, amountBull.down);

        lte(bullEPAfter, bullEP, _IG_24_3.desc);

        // reset time
        hevm.warp(currentTimestamp);
    }

    function _setFeePrice() internal {
        // FEE_PARAMS.timeToExpiryThreshold = 9999;
        FeeManager feeManager = FeeManager(ap.feeManager());
        feeManager.setDVPFee(address(ig), FEE_PARAMS);
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

        _buyAssertion(buyTokenPrice);

        (uint256 expectedPremium, uint256 fee) = ig.premium(ig.currentStrike(), amount.up, amount.down);
        precondition(expectedPremium > 100); // Slippage has no influence for value <= 100
        (uint256 sigma, ) = ig.getPostTradeVolatility(ig.currentStrike(), amount, true);
        uint256 maxPremium = expectedPremium + (ACCEPTED_SLIPPAGE * expectedPremium) / 1e18;
        {
            (uint256 ivMax, uint256 ivMin) = _getIVMaxMin(EPOCH_FREQUENCY);
            uint256 premiumMaxIV = _getMarketValueWithCustomIV(ivMax, amount, address(baseToken), buyTokenPrice);
            uint256 premiumMinIV = _getMarketValueWithCustomIV(ivMin, amount, address(baseToken), buyTokenPrice);
            lte(expectedPremium, (premiumMaxIV * _getMaxPremiumApprox()) / BASE_TOKEN_DECIMALS, _IG_03_1.desc); // See test_16 in CryticToFoundry.sol
            gte((expectedPremium * _getMaxPremiumApprox()) / BASE_TOKEN_DECIMALS, premiumMinIV, _IG_03_2.desc);
        }

        _checkFee(fee, _BUY);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(ig), maxPremium, _convertVm());
        uint256 initialUserBalance = baseToken.balanceOf(msg.sender);

        if (!FLAG_SLIPPAGE) {
            (uint256 preTradeRY, uint256 preTradePremium, uint256 uPreTrade) = _getPreTradeRY(ig.currentStrike());
            ryInfo_VAULT_2_1 = RYInfo(preTradeRY, preTradePremium, uPreTrade);
        }

        _vault25();

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

        console.log("expectedPremium", expectedPremium);
        console.log("maxPremium", maxPremium);
        console.log("ALLOWANCE", baseToken.allowance(msg.sender, address(ig)));
        hevm.prank(msg.sender);
        try ig.mint(msg.sender, currentStrike, amount.up, amount.down, expectedPremium, ACCEPTED_SLIPPAGE) returns (
            uint256 _premium
        ) {
            premium = _premium;
        } catch (bytes memory err) {
            if (!FLAG_SLIPPAGE) {
                _shouldNotRevertUnless(err, _GENERAL_6);
            } else {
                revert(string(err));
            }
        }

        VaultUtils.logState(vault);

        if (!FLAG_SLIPPAGE) {
            uint256 postTradeRY = _getPostTradeRY(ig.currentStrike(), ryInfo_VAULT_2_1, amount.up, amount.down);
            t(postTradeRY - ryInfo_VAULT_2_1.tradeRY >= 0, _VAULT_02_1.desc);
        }

        _updateT1RY(); // VAULT_25

        totalAmountBought.up += amount.up;
        totalAmountBought.down += amount.down;

        gte(baseToken.balanceOf(msg.sender), initialUserBalance - premium, _IG_10.desc);
        lte(premium, maxPremium, _IG_11.desc);
        gte(premium / BT_UNIT, expectedPremium / BT_UNIT, _IG_03_3.desc); // see test_17

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

    function _sell(BuyInfo memory buyInfo_, uint8 sellType) internal returns (uint256) {
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
        (uint256 expectedPayoff, uint256 fee) = ig.payoff(
            buyInfo_.epoch,
            buyInfo_.strike,
            buyInfo_.amountUp,
            buyInfo_.amountDown,
            0
        );

        {
            // valid only if buy epoch is not finished yet
            if (epochs.length == buyInfo_.epochCounter) {
                FinanceParameters memory financeParameters = TestOptionsFinanceHelper.getFinanceParameters(ig);
                if (_getTokenPrice(address(vault.sideToken())) > financeParameters.kA) {
                    uint256 expiryPayoff = _getTradeExpiryPayoff(buyInfo_.amountUp, buyInfo_.amountDown);
                    (uint256 expectedPremium, ) = ig.premium(buyInfo_.strike, buyInfo_.amountUp, buyInfo_.amountDown);
                    uint256 epTolerance = expectedPremium > BT_UNIT ? expectedPremium / BT_UNIT : 1;
                    gte(expectedPremium + epTolerance, expiryPayoff, _IG_14.desc);
                }
                (uint256 ivMax, uint256 ivMin) = _getIVMaxMin(EPOCH_FREQUENCY);
                Amount memory amount = Amount(buyInfo_.amountUp, buyInfo_.amountDown);
                uint256 payoffMaxIV = _getMarketValueWithCustomIV(ivMax, amount, address(baseToken), sellTokenPrice);
                uint256 payoffMinIV = _getMarketValueWithCustomIV(ivMin, amount, address(baseToken), sellTokenPrice);
                lte(expectedPayoff, payoffMaxIV, _IG_03_1.desc);
                gte(expectedPayoff, payoffMinIV, _IG_03_2.desc);
            }
        }
        _checkFee(fee, _SELL);
        _vault25();

        uint256 payoff;

        if (!FLAG_SLIPPAGE) {
            (uint256 preTradeRY, uint256 preTradePremium, uint256 uPreTrade) = _getPreTradeRY(ig.currentStrike());
            ryInfo_VAULT_2_1 = RYInfo(preTradeRY, preTradePremium, uPreTrade);
        }
        hevm.prank(buyInfo_.recipient);
        try
            ig.burn(
                buyInfo_.epoch,
                buyInfo_.recipient,
                buyInfo_.strike,
                buyInfo_.amountUp,
                buyInfo_.amountDown,
                expectedPayoff,
                ACCEPTED_SLIPPAGE,
                0
            )
        returns (uint256 payoff_) {
            payoff = payoff_;
        } catch (bytes memory err) {
            if (!FLAG_SLIPPAGE) {
                _shouldNotRevertUnless(err, _GENERAL_6);
            } else {
                revert(string(err));
            }
        }

        if (!FLAG_SLIPPAGE) {
            uint256 postTradeRY = _getPostTradeRY(
                buyInfo_.strike,
                ryInfo_VAULT_2_1,
                buyInfo_.amountUp,
                buyInfo_.amountDown
            );
            t(postTradeRY - ryInfo_VAULT_2_1.tradeRY >= 0, _VAULT_02_1.desc);
        }

        _updateT1RY(); // VAULT_25

        if (totalAmountBought.up > 0) {
            totalAmountBought.up -= buyInfo_.amountUp;
        }
        if (totalAmountBought.down > 0) {
            totalAmountBought.down -= buyInfo_.amountDown;
        }

        uint256 minPayoff = expectedPayoff - ((ACCEPTED_SLIPPAGE * expectedPayoff) / 1e18); // ACCEPTED_SLIPPAGE has 18 decimals

        _sellAssertion(buyInfo_, sellType, payoff, minPayoff, sellTokenPrice, ig.getUtilizationRate());
        lte(payoff / 10 ** (BASE_TOKEN_DECIMALS / 2), expectedPayoff / 10 ** (BASE_TOKEN_DECIMALS / 2), _IG_03_4.desc); // see test_19

        return payoff;
    }

    function _getMarketValueWithCustomIV(
        uint256 iv,
        Amount memory amount,
        address baseToken,
        uint256 swapPrice
    ) internal view returns (uint256) {
        return
            FinanceIG.getMarketValue(
                TestOptionsFinanceHelper.getFinanceParameters(ig),
                amount,
                iv,
                swapPrice,
                _getRiskFreeRate(address(baseToken)),
                BASE_TOKEN_DECIMALS
            );
    }

    function _getExpiryPayoff() internal view returns (uint256, uint256) {
        uint256 price = _getTokenPrice(address(vault.sideToken()));
        FinanceParameters memory financeParameters = TestOptionsFinanceHelper.getFinanceParameters(ig);
        return FinanceIG.getPayoffPercentages(financeParameters, price);
    }

    function _getIVMaxMin(uint256 duration) internal view returns (uint256, uint256) {
        // iv_min =  sigma0 * 0.9 * (T - 0.25 * t) / T
        // iv_max = 2 iv_min
        FinanceParameters memory fp = TestOptionsFinanceHelper.getFinanceParameters(ig);
        uint256 timeElapsed = block.timestamp - (ig.getEpoch().current - duration);
        UD60x18 timeFactor = (convert(duration).sub(convert(timeElapsed).div(convert(4)))).div(convert(duration));
        uint256 ivMin = ud(fp.sigmaZero).mul(timeFactor).unwrap();
        TimeLockedFinanceValues memory fv = TestOptionsFinanceHelper.getTimeLockedFinanceParameters(ig);

        return (ud(fv.tradeVolatilityUtilizationRateFactor).mul(ud(ivMin)).unwrap(), ivMin);
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

    function _shouldNotRevertUnless(bytes memory err, InvariantInfo memory _invariant) internal {
        if (!_ACCEPTED_REVERTS[_invariant.code][keccak256(err)]) {
            emit DebugBool(_invariant.code, _ACCEPTED_REVERTS[_invariant.code][keccak256(err)]);
            t(false, _invariant.desc);
        }
        revert(string(err));
    }

    function _checkProfit(
        uint256 payoff,
        uint256 premium,
        bool isEpochRolled,
        uint8 sellType,
        uint256 sellTokenPrice,
        uint256 buyTokenPrice,
        uint256 sellUtilizationRate,
        uint256 buyUtilizationRate,
        uint256 buyRiskFreeRate,
        uint256 buyTau
    ) internal {
        // For BEAR and SMILE payoff => payoff * discount
        if (
            sellType == _BULL &&
            sellTokenPrice <= buyTokenPrice &&
            (isEpochRolled || sellUtilizationRate <= buyUtilizationRate)
        ) {
            t(!(payoff > premium), _IG_04_1.desc);
        } else {
            uint256 ert = FinanceIGPrice.ert(buyRiskFreeRate, buyTau);
            uint256 discountedPayoff = ((payoff * ert) * 999) / (1e18 * 1000); // discount + approx

            if (!FLAG_SLIPPAGE) {
                if (
                    sellType == _BEAR &&
                    sellTokenPrice >= buyTokenPrice &&
                    (isEpochRolled || sellUtilizationRate <= buyUtilizationRate)
                ) {
                    t(!(discountedPayoff > premium), _IG_04_2.desc);
                }
                if (
                    sellType == _SMILEE &&
                    sellTokenPrice == buyTokenPrice &&
                    (isEpochRolled || sellUtilizationRate <= buyUtilizationRate)
                ) {
                    t(!(discountedPayoff > premium), _IG_04_2.desc);
                }
            }
        }
    }

    function _checkFee(uint256 fee, uint8 operation) internal {
        FeeManager feeManager = FeeManager(ap.feeManager());
        (
            uint256 timeToExpiryThreshold,
            uint256 minFeeBeforeTimeThreshold,
            uint256 minFeeAfterTimeThreshold,
            ,
            ,
            ,
            ,

        ) = feeManager.dvpsFeeParams(address(ig));

        if (operation == _BUY) {
            if ((ig.getEpoch().current - block.timestamp) > timeToExpiryThreshold) {
                gte(fee, minFeeAfterTimeThreshold, _IG_21.desc);
            } else {
                gte(fee, minFeeBeforeTimeThreshold, _IG_21.desc);
            }
        } else {
            gte(fee, minFeeAfterTimeThreshold, _IG_21.desc);
        }
    }

    function _buyAssertion(uint256 buyTokenPrice) internal {
        if (!FLAG_SLIPPAGE) {
            // This invariant are valid only at the same istant of time (or very close)
            if (lastBuy.epoch == ig.getEpoch().current && lastBuy.timestamp == block.timestamp) {
                (uint256 invariantPremium, ) = ig.premium(lastBuy.strike, lastBuy.amountUp, lastBuy.amountDown);
                Amount memory amount = Amount(lastBuy.amountUp, lastBuy.amountDown);
                (uint256 currentSigma, ) = ig.getPostTradeVolatility(
                    lastBuy.strike, //TestOptionsFinanceHelper.getFinanceParameters(ig).currentStrike,
                    amount,
                    true
                );

                if (currentSigma == lastBuy.sigma) {
                    // price grow bull premium grow, bear premium decrease
                    if (buyTokenPrice > lastBuy.buyTokenPrice) {
                        if (lastBuy.buyType == _BULL) {
                            gte(invariantPremium, lastBuy.expectedPremium, _IG_24_1.desc);
                        } else if (lastBuy.buyType == _BEAR) {
                            lte(invariantPremium, lastBuy.expectedPremium, _IG_24_1.desc);
                        }
                    } else if (buyTokenPrice < lastBuy.buyTokenPrice) {
                        if (lastBuy.buyType == _BULL) {
                            lte(invariantPremium, lastBuy.expectedPremium, _IG_24_1.desc);
                        } else if (lastBuy.buyType == _BEAR) {
                            gte(invariantPremium, lastBuy.expectedPremium, _IG_24_1.desc);
                        }
                    }
                }

                // volatility grow, premium grow
                if (buyTokenPrice == lastBuy.buyTokenPrice) {
                    if (currentSigma > lastBuy.sigma) {
                        gte(invariantPremium, lastBuy.expectedPremium, _IG_24_2.desc);
                    } else {
                        lte(invariantPremium, lastBuy.expectedPremium, _IG_24_2.desc);
                    }
                }
            }
        }
    }

    function _sellAssertion(
        BuyInfo memory buyInfo_,
        uint8 sellType,
        uint256 payoff,
        uint256 minPayoff,
        uint256 sellTokenPrice,
        uint256 sellUtilizationRate
    ) internal {
        gte(payoff, minPayoff, _IG_11.desc);

        if (epochs.length > buyInfo_.epochCounter) {
            _checkProfit(
                payoff,
                buyInfo_.premium,
                true,
                _SMILEE,
                sellTokenPrice,
                buyInfo_.buyTokenPrice,
                sellUtilizationRate,
                buyInfo_.utilizationRate,
                buyInfo_.riskFreeRate,
                buyInfo_.tau
            );

            uint256 minPriceDiff = BASE_TOKEN_DECIMALS <= 6 ? buyInfo_.strike / 0.5e6 : buyInfo_.strike / 10e12;

            if (!FLAG_SLIPPAGE) {
                if (sellType == _BULL) {
                    if (sellTokenPrice > buyInfo_.strike && (sellTokenPrice - buyInfo_.strike) > minPriceDiff) {
                        t(payoff > 0, _IG_12.desc);
                    } else {
                        t(payoff == 0, _IG_12.desc);
                    }
                } else if (sellType == _BEAR) {
                    if (sellTokenPrice < buyInfo_.strike && (buyInfo_.strike - sellTokenPrice) > minPriceDiff) {
                        t(payoff > 0, _IG_13.desc);
                    } else {
                        t(payoff == 0, _IG_13.desc);
                    }
                } else if (sellType == _SMILEE) {
                    int256 diff = int256(sellTokenPrice) - int256(buyInfo_.strike);
                    diff = diff > 0 ? diff : -diff;

                    if (diff > 1e9) {
                        t(payoff > 0, _IG_27.desc);
                    } else {
                        t(payoff == 0, _IG_27.desc);
                    }
                }
            }
        } else {
            t(true, ""); // TODO: implement invariant
        }
    }

    function _compareFinanceParameters(
        FinanceParameters memory ifp,
        FinanceParameters memory efp
    ) internal pure returns (bool) {
        return (ifp.maturity == efp.maturity &&
            ifp.currentStrike == efp.currentStrike &&
            ifp.initialLiquidity.up == efp.initialLiquidity.up &&
            ifp.initialLiquidity.down == efp.initialLiquidity.down &&
            ifp.kA == efp.kA &&
            ifp.kB == efp.kB &&
            ifp.theta == efp.theta &&
            ifp.sigmaZero == efp.sigmaZero);
    }

    function _rollepochAssertionBefore() internal {
        // after first epoch
        if (_initialVaultState.liquidity.lockedInitially > 0) {
            eq(_initialVaultState.liquidity.lockedInitially, _endingVaultState.liquidity.lockedInitially, _IG_15.desc);
            eq(_initialStrike, _endingStrike, _IG_16.desc);
            t(_compareFinanceParameters(_initialFinanceParameters, _endingFinanceParameters), _IG_17.desc);
            lte(
                (totalAmountBought.up + totalAmountBought.down),
                _initialVaultState.liquidity.lockedInitially,
                _IG_18.desc
            );
            gte(
                _initialVaultState.liquidity.pendingWithdrawals,
                _endingVaultState.liquidity.pendingWithdrawals,
                _VAULT_17.desc
            );
            gte(
                _initialVaultState.liquidity.pendingPayoffs,
                _endingVaultState.liquidity.pendingPayoffs,
                _VAULT_17.desc
            );
            eq(
                _initialVaultState.liquidity.newPendingPayoffs,
                _endingVaultState.liquidity.newPendingPayoffs,
                _VAULT_18.desc
            );

            lte(_endingVaultState.withdrawals.heldShares, _initialVaultState.withdrawals.heldShares, _VAULT_13.desc); // shares are minted at roll epoch
            lte(_endingVaultTotalSupply, _initialVaultTotalSupply, _VAULT_13.desc); // shares are minted at roll epoch
            eq(_initialSharePrice, _endingSharePrice, _VAULT_08.desc);

            if (block.timestamp < ig.getEpoch().current) {
                Amount memory amount = Amount(totalAmountBought.up, totalAmountBought.down);
                (uint256 sigma, ) = ig.getPostTradeVolatility(_endingFinanceParameters.currentStrike, amount, false);
                uint256 price = _getTokenPrice(address(vault.sideToken()));
                uint256 totalExpectedPremium = _getMarketValueWithCustomIV(sigma, amount, address(baseToken), price);

                FinanceIGPrice.Parameters memory priceParams;
                {
                    priceParams.r = _getRiskFreeRate(vault.baseToken());
                    priceParams.sigma = sigma;
                    priceParams.k = _endingFinanceParameters.currentStrike;
                    priceParams.s = price;
                    priceParams.tau = WadTime.yearsToTimestamp(_endingFinanceParameters.maturity);
                    priceParams.ka = _endingFinanceParameters.kA;
                    priceParams.kb = _endingFinanceParameters.kB;
                    priceParams.theta = _endingFinanceParameters.theta;
                }

                if (!FLAG_SLIPPAGE) {
                    gte(
                        EchidnaVaultUtils.getAssetsValue(vault, ap),
                        _endingVaultState.liquidity.pendingPayoffs +
                            _endingVaultState.liquidity.pendingWithdrawals +
                            _endingVaultState.liquidity.pendingDeposits +
                            (TestOptionsFinanceHelper.lpPrice(priceParams) *
                                (_endingVaultState.liquidity.lockedInitially / 1e18)) +
                            totalExpectedPremium,
                        _VAULT_20.desc
                    );
                }
            }
        }
    }

    function _rollepochAssertionAfter() internal {
        if (_endingVaultState.liquidity.lockedInitially > 0) {
            if (!FLAG_SLIPPAGE) {
                gte(
                    IERC20(vault.baseToken()).balanceOf(address(vault)),
                    _initialVaultState.liquidity.pendingWithdrawals +
                        _initialVaultState.liquidity.pendingPayoffs +
                        _initialVaultState.liquidity.pendingDeposits,
                    _VAULT_04.desc
                );
            }

            (uint256 vaultBaseTokens, ) = vault.balances();
            (uint256 minStv, uint256 maxStv) = _ewSideTokenMinMax();
            if (!FLAG_SLIPPAGE) {
                gte(vaultBaseTokens, minStv, _VAULT_06.desc);
                lte(vaultBaseTokens, maxStv, _VAULT_06.desc);
            }

            uint256 expectedPendingWithdrawals = (_endingVaultState.withdrawals.newHeldShares *
                vault.epochPricePerShare(ig.getEpoch().previous)) / (BT_UNIT);
            eq(
                _initialVaultState.liquidity.pendingWithdrawals,
                _endingVaultState.liquidity.pendingWithdrawals + expectedPendingWithdrawals,
                _VAULT_19.desc
            );
            eq(
                _initialVaultState.withdrawals.heldShares,
                _endingVaultState.withdrawals.heldShares + _endingVaultState.withdrawals.newHeldShares,
                _VAULT_23.desc
            );

            eq(
                (_endingVaultState.liquidity.pendingDeposits * (BT_UNIT)) /
                    vault.epochPricePerShare(ig.getEpoch().previous),
                _initialVaultTotalSupply - _endingVaultTotalSupply,
                _VAULT_15.desc
            );
        }
    }

    // Returns min and max of sideToken value to have an acceptable equal weight portfolio
    function _ewSideTokenMinMax() internal view returns (uint256 min, uint256 max) {
        uint256 sideTokenValue = EchidnaVaultUtils.getSideTokenValue(vault, ap);
        uint256 sideTokenPrice = _getTokenPrice(vault.sideToken());
        uint256 ewTolerance1 = sideTokenPrice > BT_UNIT ? sideTokenPrice / BT_UNIT : 1; //sideTokenPrice * (vaultBaseTokens / 1e4) / 10 ** baseTokenDecimals; // TODO: check if margin is too high
        uint256 ewTolerance2 = sideTokenValue / 10 ** (BASE_TOKEN_DECIMALS / 2);
        // For really small deposit ewTolerance1 should be > ewTolerance2.
        uint256 ewTolerance = ewTolerance1 > ewTolerance2 ? ewTolerance1 : ewTolerance2;
        min = sideTokenValue < (2 * ewTolerance) ? 0 : sideTokenValue - (2 * ewTolerance);
        max = sideTokenValue + (2 * ewTolerance);
    }

    function _getMaxPremiumApprox() internal view returns (uint256) {
        // 6 DECIMALS -> 1
        // 18 DECIMALS -> 1.00...0100 (15 zeri)
        uint256 res = (BT_UNIT + (10 ** (BASE_TOKEN_DECIMALS - 1 - (BASE_TOKEN_DECIMALS * 5) / 6)));
        return res;
    }

    function _getTradeRY(
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) internal view returns (uint256, uint256, uint256) {
        // RY = notional - (premium_pre * V0 / 2) * u_pre
        uint256 premium = _getRYPremium(strike, amountUp, amountDown);
        uint256 ry = vault.notional() - premium;
        return (ry, premium, ig.getUtilizationRate());
    }

    function _getPreTradeRY(uint256 strike) internal view returns (uint256, uint256, uint256) {
        // RY = notional - (premium_pre * V0 / 2) * u_pre
        (uint256 usedAmountUp, uint256 usedAmountDown) = _usedNotional();
        uint256 premium = _getRYPremium(strike, usedAmountUp, usedAmountDown);

        uint256 ry = vault.notional() - premium;
        return (ry, premium, ig.getUtilizationRate());
    }

    function _getPostTradeRY(
        uint256 strike,
        RYInfo memory ryPre,
        uint256 amountUp,
        uint256 amountDown
    ) internal view returns (uint256 tradeRY) {
        uint256 premium = _getRYPremium(strike, amountUp, amountDown);

        // (premium_post * V0) * (u_post - u_pre)
        uint256 ur = ig.getUtilizationRate();
        if (ur > ryPre.uTrade) {
            tradeRY = vault.notional() - ryPre.tradePremium - premium;
        } else {
            tradeRY = vault.notional() - ryPre.tradePremium + premium;
        }
    }

    function _getRYPremium(uint256 strike, uint256 amountUp, uint256 amountDown) internal view returns (uint256 p) {
        Amount memory amount = Amount(amountUp, amountDown);
        Amount memory hypAmount = Amount(amountUp > 0 ? 1 : 0, amountDown > 0 ? 1 : 0);
        uint256 sideTokenPrice = _getTokenPrice(vault.sideToken());
        (uint256 iv, ) = ig.getPostTradeVolatility(strike, hypAmount, true);
        p = _getMarketValueWithCustomIV(iv, amount, address(baseToken), sideTokenPrice);
    }

    function _updateT1RY() internal {
        (uint256 usedAmountUp, uint256 usedAmountDown) = _usedNotional();
        (uint256 tradeRY, uint256 tradePremium, uint256 uTrade) = _getTradeRY(
            ig.currentStrike(),
            usedAmountUp,
            usedAmountDown
        );
        RYInfo memory ryInfo = RYInfo(tradeRY, tradePremium, uTrade);

        t1Vault25 = RYInfoPostTrade(
            ryInfo,
            ig.getEpoch().current,
            _getTotalExpiryPayoff(),
            _getTokenPrice(address(vault.sideToken()))
        );
    }

    function _vault25() internal {
        // precondition s > k/2
        precondition(_getTokenPrice(address(vault.sideToken())) > (ig.currentStrike() / 2));
        if (t1Vault25.epoch == ig.getEpoch().current) {
            (uint256 usedAmountUp, uint256 usedAmountDown) = _usedNotional();

            (uint256 ryT2, , ) = _getTradeRY(ig.currentStrike(), usedAmountUp, usedAmountDown);
            uint256 ryT1 = t1Vault25.ryInfo.tradeRY;

            uint256 payoffT1 = t1Vault25.payoff;
            uint256 payoffT2 = _getTotalExpiryPayoff();
            uint256 ewT1 = _initialEwBaseTokens +
                (_initialEwSideTokens * t1Vault25.tokenPrice * BT_UNIT) /
                (1e18 * ST_UNIT);
            uint256 ewT2 = _initialEwBaseTokens +
                (_initialEwSideTokens * _getTokenPrice(address(vault.sideToken())) * BT_UNIT) /
                (1e18 * ST_UNIT);

            int256 vaultPnl = int256(ryT2) - int256(ryT1);
            int256 lpPnl = int256(ewT2) - int256(payoffT2) - int256(ewT1) + int256(payoffT1);

            // lpPnl can be greater then vaultPnl if time pass but nothing happened and price goes down before (bear)
            uint256 tolerance = ryT1 / 1e4 < BT_UNIT ? BT_UNIT : ryT1 / 1e4;
            t(((vaultPnl >= lpPnl) || (uint256(lpPnl - vaultPnl) < tolerance)), _VAULT_25.desc);
        }
    }

    function _usedNotional() internal view returns (uint256 usedAmountUp, uint256 usedAmountDown) {
        (uint256 bearNotional, uint256 bullNotional, uint256 bearAvailNotional, uint256 bullAvailNotional) = ig
            .notional();
        usedAmountUp = bullNotional - bullAvailNotional;
        usedAmountDown = bearNotional - bearAvailNotional;
    }

    function _getTotalExpiryPayoff() internal view returns (uint256 payoff) {
        uint256 v0mezzi = vault.v0() / 2;
        return _getTradeExpiryPayoff(v0mezzi, v0mezzi);
    }

    function _getTradeExpiryPayoff(uint256 amountUp, uint256 amountDown) internal view returns (uint256 payoff) {
        (uint256 pUp, uint256 pDown) = _getExpiryPayoff();
        uint256 payOffUp = pUp * 2 * amountUp;
        uint256 payOffDown = pDown * 2 * amountDown;
        payoff = (payOffUp + payOffDown) / 1e18;
    }
}
