// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SD59x18, sd} from "@prb/math/SD59x18.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
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
    uint256 sigmaZero;
    VolatilityParameters internalVolatilityParameters;
}

struct VolatilityParameters {
    uint256 epochStart;
    uint256 v_previous;
    uint256 t_previous;
    uint256 u_previous;
    uint256 avg_u;
    uint256 omega;
}

struct TimeLockedFinanceParameters {
    TimeLockedUInt sigmaMultiplier; // m
    TimeLockedUInt tradeVolatilityUtilizationRateFactor; // N
    TimeLockedUInt tradeVolatilityTimeDecay; // theta
    TimeLockedUInt volatilityPriceDiscountFactor; // rho
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

    // Get real epoch duration
    function _durationInYears(uint256 t0, uint256 t1) private pure returns (uint256 durationInYears) {
        durationInYears = WadTime.rangeInYears(t0, t1);
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
    ) public view returns (int256 tokensToSwap, int256 deltaTrade) {
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
        deltaTrade = FinanceIGDelta.deltaTrade(
            amount.up,
            amount.down,
            deltaHedgeParams.igDBull,
            deltaHedgeParams.igDBear,
            baseTokenDecimals
        );
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

    /**
       @notice Checks if there was approximation during the calculation of the finance parameters
       @param params The finance parameters of the rolled epoch
       @return isFinanceApproximated True if the finance has been approximated during the rollEpoch.
     */
    function checkFinanceApprox(FinanceParameters storage params) public view returns(bool isFinanceApproximated){
        uint256 resTetaKKartd = FinanceIGPrice._tetakkrtd(params.theta, params.currentStrike, params.kA);
        uint256 resTetaKKbrtd = FinanceIGPrice._tetakkrtd(params.theta, params.currentStrike, params.kB);

        return resTetaKKartd == 1 || resTetaKKbrtd == 1;
    }

    function updateParameters(
        FinanceParameters storage params,
        uint256 impliedVolatility,
        uint256 v0
    ) public {
        _updateSigmaZero(params, impliedVolatility);

        {
            uint256 sigmaMultiplier = params.timeLocked.sigmaMultiplier.get();
            uint256 yearsToMaturity = _durationInYears(params.internalVolatilityParameters.epochStart, params.maturity);

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
                VolatilityParameters storage vParams = params.internalVolatilityParameters;
                UD60x18 maturityWindow = convert(params.maturity - vParams.epochStart);
                UD60x18 sharedUpdateFactor = ud(vParams.v_previous).mul(maturityWindow.sub(convert(vParams.t_previous)));
                vParams.avg_u = ud(vParams.avg_u).add(ud(vParams.v_previous).mul(sharedUpdateFactor).mul(ud(vParams.u_previous))).unwrap();
                vParams.omega = ud(vParams.omega).add(sharedUpdateFactor).unwrap();
                if (vParams.omega == 0) {
                    vParams.avg_u = 0;
                } else {
                    vParams.avg_u = ud(vParams.avg_u).div(ud(vParams.omega)).unwrap();
                }
                uint256 n = params.timeLocked.tradeVolatilityUtilizationRateFactor.get();
                uint256 theta = params.timeLocked.tradeVolatilityTimeDecay.get();
                // F1 = 1 + (n - 1) * (avg_u ^ 3)
                UD60x18 factor_1 = convert(1).add(ud(n).sub(convert(1)).mul(ud(vParams.avg_u).powu(3)));
                // F2 = avg_u + (1 - θ) * (1 - avg_u)
                UD60x18 factor_2 = ud(vParams.avg_u).add(convert(1).sub(ud(theta)).mul(convert(1).sub(ud(vParams.avg_u))));
                // σ0 * F1 * F2
                params.sigmaZero = ud(params.sigmaZero).mul(factor_1).mul(factor_2).unwrap();
            }
        }
        params.internalVolatilityParameters.avg_u = 0;
        params.internalVolatilityParameters.omega = 0;
        params.internalVolatilityParameters.t_previous = 0;
        params.internalVolatilityParameters.u_previous = 0;
        params.internalVolatilityParameters.v_previous = 1e18;
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
        if (proposed.sigmaMultiplier < 0.01e18 || proposed.sigmaMultiplier > 10e18) {
            revert OutOfAllowedRange();
        }
        if (proposed.volatilityPriceDiscountFactor < 0.5e18 || proposed.volatilityPriceDiscountFactor > 1.25e18) {
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

    function updateVolatilityOnTrade(
        FinanceParameters storage params,
        uint256 oraclePrice,
        uint256 postTradeUtilizationRate
    ) external {
        uint256 timeElapsed = block.timestamp - params.internalVolatilityParameters.epochStart;
        uint256 v_i;
        {
            UD60x18 z_abs;
            {
                SD59x18 z_numerator = ud(oraclePrice).intoSD59x18().div(ud(params.currentStrike).intoSD59x18()).ln();
                uint256 tau = WadTime.rangeInYears(params.internalVolatilityParameters.epochStart, params.maturity);
                uint256 volatilityPriceDiscountFactor = params.timeLocked.volatilityPriceDiscountFactor.get();
                // NOTE: sigma zero must be the original one, without the discount factor, hence the division.
                SD59x18 z_denominator = ud(params.sigmaZero).div(ud(volatilityPriceDiscountFactor)).mul(ud(tau).sqrt()).intoSD59x18();

                z_abs = z_numerator.div(z_denominator).abs().intoUD60x18();
            }
            UD60x18 maturityWindow = convert(params.maturity - params.internalVolatilityParameters.epochStart);
            UD60x18 numerator = (maturityWindow.sub(convert(timeElapsed))).div(maturityWindow);
            UD60x18 denominator = convert(1).add(z_abs.div(convert(3)).powu(5));

            v_i = numerator.div(denominator).unwrap();
        }

        {
            UD60x18 sharedUpdateFactor = ud(params.internalVolatilityParameters.v_previous).mul(convert(timeElapsed).sub(convert(params.internalVolatilityParameters.t_previous)));
            params.internalVolatilityParameters.avg_u = ud(params.internalVolatilityParameters.avg_u).add(sharedUpdateFactor.mul(ud(params.internalVolatilityParameters.u_previous))).unwrap();
            params.internalVolatilityParameters.omega = ud(params.internalVolatilityParameters.omega).add(sharedUpdateFactor).unwrap();
        }

        params.internalVolatilityParameters.t_previous = timeElapsed;
        params.internalVolatilityParameters.u_previous = postTradeUtilizationRate;
        params.internalVolatilityParameters.v_previous = v_i;
    }
}
