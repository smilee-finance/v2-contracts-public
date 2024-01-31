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
import {FinanceIG, FinanceParameters, VolatilityParameters, TimeLockedFinanceParameters} from "@project/lib/FinanceIG.sol";
import {Amount} from "@project/lib/Amount.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {EchidnaVaultUtils} from "../lib/EchidnaVaultUtils.sol";

/**
 * medusa fuzz --no-color
 * echidna . --contract CryticTester --config config.yaml
 */
abstract contract TargetFunctions is BaseTargetFunctions, State {
    mapping(address => bool) internal _pendingWithdraw;

    uint256 totalAmountBought = 0; // intra epoch

    function setup() internal virtual override {
        deploy();
        _initializeProperties();
    }

    //----------------------------------------------
    // VAULT
    //----------------------------------------------
    function deposit(uint256 amount) public {
        // precondition revert ExceedsMaxDeposit
        (, , , , uint256 totalDeposit, , , , ) = vault.vaultState();
        uint256 maxDeposit = vault.maxDeposit();
        uint256 depositCapacity = maxDeposit - totalDeposit;
        amount = _between(amount, MIN_VAULT_DEPOSIT, depositCapacity);

        VaultUtils.debugState(vault);

        precondition(block.timestamp < ig.getEpoch().current);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(vault), amount, _convertVm());

        console.log("** DEPOSIT", amount);
        hevm.prank(msg.sender);
        try vault.deposit(amount, msg.sender, 0) {} catch (bytes memory err) {
            if (!FLAG_SLIPPAGE) {
                _shouldNotRevertUnless(err, _GENERAL_1);
            }
        }

        _depositInfo.push(DepositInfo(msg.sender, amount, ig.getEpoch().current));
        VaultUtils.debugState(vault);
    }

    function redeem(uint256 index) public {
        precondition(_depositInfo.length > 0);
        index = _between(index, 0, _depositInfo.length - 1);
        precondition(block.timestamp < ig.getEpoch().current); // EpochFinished()

        DepositInfo storage depInfo = _depositInfo[index];
        (uint256 heldByUser, uint256 heldByVault) = vault.shareBalances(depInfo.user);
        precondition(heldByVault > 0); // can't redeem shares before mint (before epoch roll)

        console.log("** REDEEM", heldByVault);
        hevm.prank(depInfo.user);
        try vault.redeem(heldByVault) {} catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_1);
        }

        eq(vault.balanceOf(depInfo.user), heldByUser + heldByVault, "");
    }

    function initiateWithdraw(uint256 index) public {
        precondition(_depositInfo.length > 0);
        index = _between(index, 0, _depositInfo.length - 1);
        precondition(block.timestamp < ig.getEpoch().current); // EpochFinished()

        DepositInfo storage depInfo = _depositInfo[index];

        precondition(!_pendingWithdraw[depInfo.user]); // ExistingIncompleteWithdraw()
        (uint256 heldByUser, uint256 heldByVault) = vault.shareBalances(depInfo.user);
        uint256 sharesToWithdraw = heldByUser + heldByVault;
        precondition(sharesToWithdraw > 0); // AmountZero()

        console.log("** INITIATE WITHDRAW", sharesToWithdraw);
        VaultUtils.debugState(vault);

        hevm.prank(depInfo.user);
        try vault.initiateWithdraw(sharesToWithdraw) {} catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_1);
        }

        _pendingWithdraw[depInfo.user] = true;
        withdrawals.push(WithdrawInfo(depInfo.user, sharesToWithdraw, epochs.length));
        _popDepositInfo(index);
        VaultUtils.debugState(vault);
    }

    function completeWithdraw(uint256 index) public {
        precondition(withdrawals.length > 0);
        index = _between(index, 0, withdrawals.length - 1);

        WithdrawInfo storage withdrawInfo = withdrawals[index];
        precondition(withdrawInfo.epochCounter < epochs.length); // WithdrawTooEarly()

        uint256 initialUserBalance = baseToken.balanceOf(withdrawInfo.user);
        (uint256 withdrawEpoch, ) = vault.withdrawals(withdrawInfo.user);
        uint256 epochSharePrice = vault.epochPricePerShare(withdrawEpoch);
        uint256 expectedAmountToWithdraw = (withdrawInfo.amount * epochSharePrice) / 1e18;

        console.log("** WITHDRAW", expectedAmountToWithdraw);
        hevm.prank(withdrawInfo.user);
        try vault.completeWithdraw() {} catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_1);
        }

        eq(baseToken.balanceOf(withdrawInfo.user), initialUserBalance + expectedAmountToWithdraw, "");
        _pendingWithdraw[withdrawInfo.user] = false;
        _popWithdrawals(index);
    }

    //----------------------------------------------
    // USER OPs.
    //----------------------------------------------

    function buyBull(uint256 input) public {
        Amount memory amount_ = _boundBuyInput(_BULL, input);
        precondition(block.timestamp < ig.getEpoch().current);

        uint256 tokenPrice = _getTokenPrice(vault.sideToken());
        DVPUtils.debugStateIG(ig);

        uint256 strike = ig.currentStrike();
        uint256 sigma = ig.getPostTradeVolatility(strike, amount_, true);
        uint256 riskFreeRate = _getRiskFreeRate(vault.baseToken());

        console.log("** BUY BULL", amount_.up);
        uint256 premium = _buy(amount_);

        (uint256 premiumCallK, uint256 premiumCallKb) = TestOptionsFinanceHelper.equivalentOptionPremiums(
            _BULL,
            amount_.up,
            tokenPrice,
            riskFreeRate,
            sigma,
            _initialFinanceParameters
        );

        lte(premium, premiumCallK, _IG_05_1.desc);
        gte(premium, premiumCallKb, _IG_05_2.desc);
    }

    function buyBear(uint256 input) public {
        Amount memory amount_ = _boundBuyInput(_BEAR, input);
        precondition(block.timestamp < ig.getEpoch().current);

        uint256 tokenPrice = _getTokenPrice(vault.sideToken());
        DVPUtils.debugStateIG(ig);

        uint256 strike = ig.currentStrike();
        uint256 sigma = ig.getPostTradeVolatility(strike, amount_, true);
        uint256 riskFreeRate = _getRiskFreeRate(vault.baseToken());

        console.log("** BUY BEAR", amount_.down);
        uint256 premium = _buy(amount_);

        (uint256 premiumPutK, uint256 premiumPutKa) = TestOptionsFinanceHelper.equivalentOptionPremiums(
            _BEAR,
            amount_.down,
            tokenPrice,
            riskFreeRate,
            sigma,
            _initialFinanceParameters
        );

        lte(premium, amount_.down, _IG_06.desc);
        lte(premium, premiumPutK, _IG_07_1.desc);
        gte(premium, premiumPutKa, _IG_07_2.desc);
    }

    function buySmilee(uint256 input) public {
        Amount memory amount_ = _boundBuyInput(_SMILEE, input);
        precondition(block.timestamp < ig.getEpoch().current);

        uint256 tokenPrice = _getTokenPrice(vault.sideToken());
        DVPUtils.debugStateIG(ig);

        uint256 strike = ig.currentStrike();
        uint256 sigma = ig.getPostTradeVolatility(strike, amount_, true);
        uint256 riskFreeRate = _getRiskFreeRate(vault.baseToken());

        console.log("** BUY SMILEE");
        uint256 premium = _buy(amount_);

        (uint256 premiumStraddleK, uint256 premiumStrangleKaKb) = TestOptionsFinanceHelper.equivalentOptionPremiums(
            _SMILEE,
            amount_.up, // == amount_.down
            tokenPrice,
            riskFreeRate,
            sigma,
            _initialFinanceParameters
        );

        lte(premium, premiumStraddleK, _IG_08_1.desc);
        gte(premium, premiumStrangleKaKb, _IG_08_2.desc);
    }

    function sellBull(uint256 index) public {
        precondition(bullTrades.length > 0);
        index = _between(index, 0, bullTrades.length - 1);
        BuyInfo storage buyInfo_ = bullTrades[index];

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);
        console.log("** SELL BULL", buyInfo_.amountUp);
        uint256 payoff = _sell(buyInfo_, _BULL);

        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, _IG_09.desc);
        _popTrades(index, buyInfo_);
    }

    function sellBear(uint256 index) public {
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

    function sellSmilee(uint256 index) public {
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

        if (perc < 10) {
            console.log("SKIP");
            // DO NOTHING
            emit Debug("Do nothing");
            return;
        } else if (perc < 30) {
            // 20% - RollEpoch
            emit Debug("rollEpoch()");
            _rollEpoch();
        } else {
            // 70% - SetTokenPrice
            emit DebugUInt("setTokenPrice()", input);
            _setTokenPrice(input);
        }
    }

    function _rollEpoch() internal {
        console.log("** STATES PRE ROLLEPOCH");
        VaultUtils.debugState(vault);
        DVPUtils.debugStateIG(ig);

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

        epochs.push(EpochInfo(currentEpoch, _endingStrike));

        _after();

        _rollepochAssertionAfter();

        totalAmountBought = 0;

        // gte(
        //     vault.notional(),
        //     _initialVaultState.liquidity.pendingWithdrawals +
        //         _initialVaultState.liquidity.pendingPayoffs +
        //         (vault.totalSupply() * vault.epochPricePerShare(ig.getEpoch().previous)),
        //     _VAULT_03.desc
        // );

        console.log("** STATES AFTER ROLLEPOCH");
        VaultUtils.debugState(vault);
        DVPUtils.debugStateIG(ig);
    }

    function _getTokenPrice(address tokenAddress) internal view returns (uint256 tokenPrice) {
        IPriceOracle apPriceOracle = IPriceOracle(ap.priceOracle());
        tokenPrice = apPriceOracle.getPrice(tokenAddress, vault.baseToken());
    }

    function _setTokenPrice(uint256 price) internal {
        if (TOKEN_PRICE_CAN_CHANGE) {
            TestnetPriceOracle apPriceOracle = TestnetPriceOracle(ap.priceOracle());
            address sideToken = vault.sideToken();

            price = _between(price, MIN_TOKEN_PRICE, MAX_TOKEN_PRICE);
            console.log("** SET TOKEN PRICE", price);
            hevm.prank(admin);
            apPriceOracle.setTokenPrice(sideToken, price);
        }
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

    function _buy(Amount memory amount) internal returns (uint256) {
        console.log("*** AMOUNT UP", amount.up);
        console.log("*** AMOUNT DOWN", amount.down);
        uint256 currentStrike = ig.currentStrike();
        uint256 buyTokenPrice = _getTokenPrice(vault.sideToken());

        (uint256 expectedPremium, uint256 fee) = ig.premium(currentStrike, amount.up, amount.down);
        precondition(expectedPremium > 100); // Slippage has no influence for value <= 100
        uint256 maxPremium = expectedPremium + (SLIPPAGE * expectedPremium) / 1e18;
        {
            (uint256 ivMax, uint256 ivMin) = _getIVMaxMin(DURATION_SEC);
            uint256 premiumMaxIV = _getMarketValueWithCustomIV(ivMax, amount, address(baseToken), buyTokenPrice);
            uint256 premiumMinIV = _getMarketValueWithCustomIV(ivMin, amount, address(baseToken), buyTokenPrice);
            lte(expectedPremium, premiumMaxIV, _IG_03_1.desc);
            gte(expectedPremium, premiumMinIV, _IG_03_2.desc);
        }

        _checkFee(fee, _BUY);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(ig), maxPremium, _convertVm());
        uint256 initialUserBalance = baseToken.balanceOf(msg.sender);

        uint256 premium;

        hevm.prank(msg.sender);
        try ig.mint(msg.sender, buyTokenPrice, amount.up, amount.down, expectedPremium, SLIPPAGE, 0) returns (
            uint256 _premium
        ) {
            premium = _premium;
        } catch (bytes memory err) {
            if (!FLAG_SLIPPAGE) {
                _shouldNotRevertUnless(err, _GENERAL_6);
            }
        }

        VaultUtils.debugState(vault);

        totalAmountBought += amount.up + amount.down;
        gte(baseToken.balanceOf(msg.sender), initialUserBalance - premium, _IG_10.desc);
        lte(premium, maxPremium, _IG_11.desc);
        gte(premium, expectedPremium, _IG_03_3.desc);

        uint256 utilizationRate = ig.getUtilizationRate();
        BuyInfo memory buyInfo = BuyInfo(
            msg.sender,
            ig.getEpoch().current,
            epochs.length,
            amount.up,
            amount.down,
            currentStrike,
            premium,
            utilizationRate,
            buyTokenPrice
        );

        _pushTrades(buyInfo);

        return premium;
    }

    function _sell(BuyInfo memory buyInfo_, uint8 sellType) internal returns (uint256) {
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
            buyInfo_.amountDown
        );

        {
            // valid only if buy epoch is not finished yet
            if (epochs.length == buyInfo_.epochCounter) {
                (uint256 expectedPremium, ) = ig.premium(buyInfo_.strike, buyInfo_.amountUp, buyInfo_.amountDown);
                gte(expectedPremium, expectedPayoff, _IG_14.desc);

                (uint256 ivMax, uint256 ivMin) = _getIVMaxMin(DURATION_SEC);
                Amount memory amount = Amount(buyInfo_.amountUp, buyInfo_.amountDown);
                uint256 payoffMaxIV = _getMarketValueWithCustomIV(ivMax, amount, address(baseToken), sellTokenPrice);
                uint256 payoffMinIV = _getMarketValueWithCustomIV(ivMin, amount, address(baseToken), sellTokenPrice);
                lte(expectedPayoff, payoffMaxIV, _IG_03_1.desc);
                gte(expectedPayoff, payoffMinIV, _IG_03_2.desc);
            }
        }

        _checkFee(fee, _SELL);
        uint256 payoff;
        hevm.prank(buyInfo_.recipient);
        try
            ig.burn(
                buyInfo_.epoch,
                buyInfo_.recipient,
                buyInfo_.strike,
                buyInfo_.amountUp,
                buyInfo_.amountDown,
                expectedPayoff,
                SLIPPAGE
            )
        returns (uint256 _payoff) {
            payoff = _payoff;
        } catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_6);
        }

        // uint256 maxPayoff = expectedPayoff + (SLIPPAGE * expectedPayoff) / 1e18;
        uint256 minPayoff = expectedPayoff - (SLIPPAGE * expectedPayoff) / 1e18;

        _sellAssertion(buyInfo_, sellType, payoff, minPayoff, sellTokenPrice, ig.getUtilizationRate());
        lte(payoff, expectedPayoff, _IG_03_4.desc);

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
                IERC20Metadata(address(baseToken)).decimals()
            );
    }

    function _getIVMaxMin(uint256 duration) internal view returns (uint256, uint256) {
        // iv_min =  sigma0 * 0.9 * (T - 0.25 * t) / T
        // iv_max = 2 iv_min
        FinanceParameters memory fp = TestOptionsFinanceHelper.getFinanceParameters(ig);
        uint256 timeElapsed = block.timestamp - (ig.getEpoch().current - duration);
        UD60x18 timeFactor = (convert(duration).sub(convert(timeElapsed).div(convert(4)))).div(convert(duration));
        uint256 ivMin = ud(fp.sigmaZero).mul(timeFactor).unwrap();
        return (2 * ivMin, ivMin);
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
        uint256 buyUtilizationRate
    ) internal {
        if (payoff > premium) {
            bool checkTokenPrice = (sellType == _BULL && sellTokenPrice > buyTokenPrice) ||
                (sellType == _BEAR && sellTokenPrice < buyTokenPrice) ||
                (sellType == _SMILEE && sellTokenPrice != buyTokenPrice);
            t(checkTokenPrice && (isEpochRolled || sellUtilizationRate > buyUtilizationRate), _IG_04.desc);
        } else {
            t(true, _IG_04.desc); // TODO: implement invariants
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
                buyInfo_.utilizationRate
            );

            if (sellType == _BULL) {
                if (sellTokenPrice > buyInfo_.strike) {
                    t(payoff > 0, _IG_12.desc);
                } else {
                    t(payoff == 0, _IG_12.desc);
                }
            } else if (sellType == _BEAR) {
                if (sellTokenPrice < buyInfo_.strike) {
                    t(payoff > 0, _IG_13.desc);
                } else {
                    t(payoff == 0, _IG_13.desc);
                }
            } else if (sellType == _SMILEE) {
                if (sellTokenPrice != buyInfo_.strike) {
                    t(payoff > 0, _IG_27.desc);
                } else {
                    t(payoff == 0, _IG_27.desc);
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
            ifp.limSup == efp.limSup &&
            ifp.limInf == efp.limInf &&
            ifp.sigmaZero == efp.sigmaZero);
    }

    function _rollepochAssertionBefore() internal {
        // after first epoch
        if (_initialVaultState.liquidity.lockedInitially > 0) {
            eq(_initialVaultState.liquidity.lockedInitially, _endingVaultState.liquidity.lockedInitially, _IG_15.desc);
            eq(_initialStrike, _endingStrike, _IG_16.desc);
            t(_compareFinanceParameters(_initialFinanceParameters, _endingFinanceParameters), _IG_17.desc);
            t(_endingFinanceParameters.limSup > 0, _IG_22.desc);
            t(_endingFinanceParameters.limInf < 0, _IG_23.desc);
            lte(totalAmountBought, _initialVaultState.liquidity.lockedInitially, _IG_18.desc);
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
            eq(_intialSharePrice, _endingSharePrice, _VAULT_08.desc);
        }
    }

    function _rollepochAssertionAfter() internal {
        if (_endingVaultState.liquidity.lockedInitially > 0) {
            uint256 baseTokenDecimals = IERC20Metadata(baseToken).decimals();

            uint256 baseTokenBalance = IERC20(baseToken).balanceOf(address(vault));
            gte(
                baseTokenBalance,
                _endingVaultState.liquidity.pendingWithdrawals +
                    _endingVaultState.liquidity.pendingPayoffs +
                    _endingVaultState.liquidity.pendingDeposits,
                _VAULT_04.desc
            );

            (uint256 vaultBaseTokens, ) = vault.balances();
            (uint256 minStv, uint256 maxStv) = _ewSideTokenMinMax();
            gte(vaultBaseTokens, minStv, _VAULT_06.desc);
            lte(vaultBaseTokens, maxStv, _VAULT_06.desc);

            uint256 expectedPendingWithdrawals = (_endingVaultState.withdrawals.newHeldShares *
                vault.epochPricePerShare(ig.getEpoch().previous)) / (10 ** baseTokenDecimals);
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
                (_endingVaultState.liquidity.pendingDeposits * (10 ** baseTokenDecimals)) /
                    vault.epochPricePerShare(ig.getEpoch().previous),
                _initialVaultTotalSupply - _endingVaultTotalSupply,
                _VAULT_15.desc
            );
        }
    }

    // Returns min and max of sideToken value to have an acceptable equal weight portfolio
    function _ewSideTokenMinMax() internal view returns (uint256 min, uint256 max) {
        uint256 baseTokenDecimals = IERC20Metadata(baseToken).decimals();
        uint256 sideTokenValue = EchidnaVaultUtils.getSideTokenValue(vault, ap);
        uint256 sideTokenPrice = _getTokenPrice(vault.sideToken());
        uint256 ewTolerance1 = sideTokenPrice > 10 ** baseTokenDecimals ? sideTokenPrice / 10 ** baseTokenDecimals : 1; //sideTokenPrice * (vaultBaseTokens / 1e4) / 10 ** baseTokenDecimals; // TODO: check if margin is too high
        uint256 ewTolerance2 = sideTokenValue / 1e9;
        // For really small deposit ewTolerance1 should be > ewTolerance2.
        uint256 ewTolerance = ewTolerance1 > ewTolerance2 ? ewTolerance1 : ewTolerance2;
        min = sideTokenValue < (2 * ewTolerance) ? 0 : sideTokenValue - (2 * ewTolerance);
        max = sideTokenValue + (2 * ewTolerance);
    }
}
