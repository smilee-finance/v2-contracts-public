// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Amount, AmountHelper} from "./Amount.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {FinanceIGDelta} from "./FinanceIGDelta.sol";
import {FinanceIGPayoff} from "./FinanceIGPayoff.sol";
import {FinanceIGPrice} from "./FinanceIGPrice.sol";
import {SignedMath} from "./SignedMath.sol";
import {TimeLock, TimeLockedBool, TimeLockedUInt} from "./TimeLock.sol";
import {WadTime} from "./WadTime.sol";

struct FinanceParameters {
    uint256 maturity;
    uint256 currentStrike;
    Amount initialLiquidity;
    uint256 kA;
    uint256 kB;
    uint256 theta;
    int256 limSup;
    int256 limInf;
    TimeLockedFinanceParameters timeLocked;
    uint256 averageSigma;
    uint256 totalTradedNotional;
    uint256 sigmaZero;
}

struct TimeLockedFinanceParameters {
    TimeLockedUInt sigmaMultiplier;
    TimeLockedUInt tradeVolatilityUtilizationRateFactor;
    TimeLockedUInt tradeVolatilityTimeDecay;
    TimeLockedUInt volatilityPriceDiscountFactor;
    TimeLockedBool useOracleImpliedVolatility;
}

struct TimeLockedFinanceValues {
    uint256 sigmaMultiplier;
    uint256 tradeVolatilityUtilizationRateFactor;
    uint256 tradeVolatilityTimeDecay;
    uint256 volatilityPriceDiscountFactor;
    bool useOracleImpliedVolatility;
}

/// @title Implementation of core financial computations for Smilee protocol
library FinanceIG {
    using AmountsMath for uint256;
    using AmountHelper for Amount;
    using TimeLock for TimeLockedBool;
    using TimeLock for TimeLockedUInt;

    error OutOfAllowedRange();

    // Allows to save on the contract size thanks to fewer delegate calls
    function _yearsToMaturity(uint256 maturity) private view returns (uint256 yearsToMaturity) {
        yearsToMaturity = WadTime.yearsToTimestamp(maturity);
    }

    function getDeltaHedgeAmount(
        FinanceParameters memory params,
        Amount memory amount,
        bool tradeIsBuy,
        uint256 postTradeVolatility,
        uint256 oraclePrice,
        uint256 sideTokensAmount,
        Amount memory availableLiquidity,
        uint8 baseTokenDecimals,
        uint8 sideTokenDecimals
    ) public view returns (int256 tokensToSwap) {
        FinanceIGDelta.DeltaHedgeParameters memory deltaHedgeParams;

        deltaHedgeParams.notionalUp = SignedMath.revabs(amount.up, tradeIsBuy);
        deltaHedgeParams.notionalDown = SignedMath.revabs(amount.down, tradeIsBuy);

        (deltaHedgeParams.igDBull, deltaHedgeParams.igDBear) = _getDeltaHedgePercentages(
            params,
            postTradeVolatility,
            oraclePrice
        );

        deltaHedgeParams.strike = params.currentStrike;
        deltaHedgeParams.sideTokensAmount = sideTokensAmount;
        deltaHedgeParams.baseTokenDecimals = baseTokenDecimals;
        deltaHedgeParams.sideTokenDecimals = sideTokenDecimals;
        deltaHedgeParams.initialLiquidityBull = params.initialLiquidity.up;
        deltaHedgeParams.initialLiquidityBear = params.initialLiquidity.down;
        deltaHedgeParams.availableLiquidityBull = availableLiquidity.up;
        deltaHedgeParams.availableLiquidityBear = availableLiquidity.down;
        deltaHedgeParams.theta = params.theta;
        deltaHedgeParams.kb = params.kB;

        tokensToSwap = FinanceIGDelta.deltaHedgeAmount(deltaHedgeParams);
    }

    function _getDeltaHedgePercentages(
        FinanceParameters memory params,
        uint256 postTradeVolatility,
        uint256 oraclePrice
    ) private view returns (int256 igDBull, int256 igDBear) {
        FinanceIGDelta.Parameters memory deltaParams;

        uint256 yearsToMaturity = _yearsToMaturity(params.maturity);

        (deltaParams.alfa1, deltaParams.alfa2) = FinanceIGDelta.alfas(
            params.currentStrike,
            params.kA,
            params.kB,
            postTradeVolatility,
            yearsToMaturity
        );

        deltaParams.sigma = postTradeVolatility;
        deltaParams.k = params.currentStrike;
        deltaParams.s = oraclePrice;
        deltaParams.tau = yearsToMaturity;
        deltaParams.limSup = params.limSup;
        deltaParams.limInf = params.limInf;

        (igDBull, igDBear) = FinanceIGDelta.deltaHedgePercentages(deltaParams);
    }

    function getMarketValue(
        FinanceParameters memory params,
        Amount memory amount,
        uint256 postTradeVolatility,
        uint256 swapPrice,
        uint256 riskFreeRate,
        uint8 baseTokenDecimals
    ) public view returns (uint256 marketValue) {
        FinanceIGPrice.Parameters memory priceParams;
        {
            uint256 yearsToMaturity = _yearsToMaturity(params.maturity);

            priceParams.r = riskFreeRate;
            priceParams.sigma = postTradeVolatility;
            priceParams.k = params.currentStrike;
            priceParams.s = swapPrice;
            priceParams.tau = yearsToMaturity;
            priceParams.ka = params.kA;
            priceParams.kb = params.kB;
            priceParams.teta = params.theta;
        }
        (uint256 igPBull, uint256 igPBear) = FinanceIGPrice.igPrices(priceParams);

        marketValue = FinanceIGPrice.getMarketValue(amount.up, igPBull, amount.down, igPBear, baseTokenDecimals);
    }

    function getPayoffPercentages(
        FinanceParameters memory params,
        uint256 oraclePrice
    ) public pure returns (uint256, uint256) {
        return
            FinanceIGPayoff.igPayoffPerc(
                oraclePrice,
                params.currentStrike,
                params.kA,
                params.kB,
                params.theta
            );
    }

    function getStrike(
        uint256 oraclePrice,
        uint256 baseTokenAmount,
        uint256 sideTokenAmount,
        uint8 baseTokenDecimals,
        uint8 sideTokenDecimals
    ) public pure returns (uint256) {
        // NOTE: both amounts are after equal weight rebalance, hence we can just compute their ratio.
        // Protect against division by zero
        if (baseTokenAmount == 0 || sideTokenAmount == 0) {
            return oraclePrice;
        }

        baseTokenAmount = AmountsMath.wrapDecimals(baseTokenAmount, baseTokenDecimals);
        sideTokenAmount = AmountsMath.wrapDecimals(sideTokenAmount, sideTokenDecimals);
        return baseTokenAmount.wdiv(sideTokenAmount);
    }

    function updateStrike(
        FinanceParameters storage params,
        uint256 oraclePrice,
        uint256 baseTokenAmount,
        uint256 sideTokenAmount,
        uint8 baseTokenDecimals,
        uint8 sideTokenDecimals
    ) public {
        params.currentStrike = getStrike(
            oraclePrice,
            baseTokenAmount,
            sideTokenAmount,
            baseTokenDecimals,
            sideTokenDecimals
        );
    }

    function updateParameters(
        FinanceParameters storage params,
        uint256 impliedVolatility,
        uint256 v0
    ) public {
        _updateSigmaZero(params, impliedVolatility);

        // Reset the average for the next epoch:
        params.averageSigma = 0;
        params.totalTradedNotional = 0;

        {
            uint256 sigmaMultiplier = params.timeLocked.sigmaMultiplier.get();
            uint256 yearsToMaturity = _yearsToMaturity(params.maturity);

            (params.kA, params.kB) = FinanceIGPrice.liquidityRange(
                FinanceIGPrice.LiquidityRangeParams(
                    params.currentStrike,
                    params.sigmaZero,
                    sigmaMultiplier,
                    yearsToMaturity
                )
            );
        }

        {
            // Multiply baselineVolatility for a safety margin after the computation of kA and kB:
            uint256 volatilityPriceDiscountFactor = params.timeLocked.volatilityPriceDiscountFactor.get();

            params.sigmaZero = params.sigmaZero.wmul(volatilityPriceDiscountFactor);
        }

        params.theta = FinanceIGPrice._teta(params.currentStrike, params.kA, params.kB);

        (params.limSup, params.limInf) = FinanceIGDelta.lims(
            params.currentStrike,
            params.kA,
            params.kB,
            params.theta,
            v0
        );
    }

    function _updateSigmaZero(FinanceParameters storage params, uint256 impliedVolatility) private {
        // Set baselineVolatility:
        if (params.timeLocked.useOracleImpliedVolatility.get()) {
            params.sigmaZero = impliedVolatility;
        } else {
            if (params.sigmaZero == 0) {
                // if it was never set, take the one from the oracle:
                params.sigmaZero = impliedVolatility;
            } else {
                if (params.averageSigma > 0) {
                    // Update with the average of the trades:
                    params.sigmaZero = params.averageSigma;
                } else {
                    uint256 rho = params.timeLocked.tradeVolatilityUtilizationRateFactor.get();
                    uint256 theta = params.timeLocked.tradeVolatilityTimeDecay.get();
                    uint256 newSigmaZero = rho.wmul(params.sigmaZero).wmul(1e18 - theta);

                    params.sigmaZero = newSigmaZero;
                }
            }
        }
    }

    function updateTimeLockedParameters(
        TimeLockedFinanceParameters storage timeLockedParams,
        TimeLockedFinanceValues memory proposed,
        uint256 timeToValidity
    ) public {
        if (proposed.tradeVolatilityUtilizationRateFactor < 1e18 || proposed.tradeVolatilityUtilizationRateFactor > 5e18) {
            revert OutOfAllowedRange();
        }
        if (proposed.tradeVolatilityTimeDecay > 0.5e18) {
            revert OutOfAllowedRange();
        }
        if (proposed.sigmaMultiplier < 0.01e18 || proposed.sigmaMultiplier > 6e18) {
            revert OutOfAllowedRange();
        }
        if (proposed.volatilityPriceDiscountFactor < 0.7e18 || proposed.volatilityPriceDiscountFactor > 1.2e18) {
            revert OutOfAllowedRange();
        }

        timeLockedParams.sigmaMultiplier.set(proposed.sigmaMultiplier, timeToValidity);
        timeLockedParams.tradeVolatilityUtilizationRateFactor.set(proposed.tradeVolatilityUtilizationRateFactor, timeToValidity);
        timeLockedParams.tradeVolatilityTimeDecay.set(proposed.tradeVolatilityTimeDecay, timeToValidity);
        timeLockedParams.volatilityPriceDiscountFactor.set(proposed.volatilityPriceDiscountFactor, timeToValidity);
        timeLockedParams.useOracleImpliedVolatility.set(proposed.useOracleImpliedVolatility, timeToValidity);
    }

    /**
        @notice Get the estimated implied volatility from a given trade.
        @param params The finance parameters.
        @param ur The post-trade utilization rate.
        @param t0 The previous epoch.
        @return sigma The estimated implied volatility.
        @dev The baseline volatility (params.sigmaZero) must be updated, computed just before the start of the epoch.
     */
    function getPostTradeVolatility(
        FinanceParameters memory params,
        uint256 ur,
        uint256 t0
    ) public view returns (uint256 sigma) {
        // NOTE: on the very first epoch, it doesn't matter if sigmaZero is zero, because the underlying vault is empty
        FinanceIGPrice.TradeVolatilityParams memory igPriceParams;
        {
            uint256 tradeVolatilityUtilizationRateFactor = params.timeLocked.tradeVolatilityUtilizationRateFactor.get();
            uint256 tradeVolatilityTimeDecay = params.timeLocked.tradeVolatilityTimeDecay.get();
            uint256 t = params.maturity - t0;

            igPriceParams = FinanceIGPrice.TradeVolatilityParams(
                params.sigmaZero,
                tradeVolatilityUtilizationRateFactor,
                tradeVolatilityTimeDecay,
                ur,
                t,
                t0
            );
        }

        sigma = FinanceIGPrice.tradeVolatility(igPriceParams);
    }

    // Average trade volatility within an epoch
    function updateAverageVolatility(
        FinanceParameters storage params,
        Amount memory tradeNotional,
        uint256 postTradeVolatility,
        uint8 tokenDecimals
    ) public {
        uint256 tradedNotional = AmountsMath.wrapDecimals(tradeNotional.getTotal(), tokenDecimals);
        uint256 totalTradedNotional = AmountsMath.wrapDecimals(params.totalTradedNotional, tokenDecimals);

        uint256 numerator = params.averageSigma.wmul(totalTradedNotional).add(tradedNotional.wmul(postTradeVolatility));
        uint256 denominator = totalTradedNotional.add(tradedNotional);

        // NOTE: denominator cannot be zero as tradeNotional is checked earlier.
        params.averageSigma = numerator.wdiv(denominator);
        params.totalTradedNotional += tradeNotional.getTotal();
    }
}
