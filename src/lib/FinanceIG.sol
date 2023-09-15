// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Amount} from "./Amount.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {FinanceIGDelta} from "./FinanceIGDelta.sol";
import {FinanceIGPayoff} from "./FinanceIGPayoff.sol";
import {FinanceIGPrice} from "./FinanceIGPrice.sol";
import {SignedMath} from "./SignedMath.sol";
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
    uint256 sigmaZero;
    uint256 sigmaMultiplier;
    uint256 tradeVolatilityUtilizationRateFactor;
    uint256 tradeVolatilityTimeDecay;
}

/// @title Implementation of core financial computations for Smilee protocol
library FinanceIG {
    using AmountsMath for uint256;

    function _yearsToMaturity(uint256 maturity) private view returns (uint256 yearsToMaturity) {
        yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(block.timestamp, maturity));
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
        // ToDo: review FinanceIGDelta.DeltaHedgeParameters (add tradeIsBuy ?)
        FinanceIGDelta.DeltaHedgeParameters memory deltaHedgeParams;

        deltaHedgeParams.notionalUp = SignedMath.revabs(amount.up, tradeIsBuy);
        deltaHedgeParams.notionalDown = SignedMath.revabs(amount.down, tradeIsBuy);

        (deltaHedgeParams.igDBull, deltaHedgeParams.igDBear) = _getDeltaHedgePercentages(params, postTradeVolatility, oraclePrice);

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

        (deltaParams.alfa1, deltaParams.alfa2) = FinanceIGDelta.alfas(
            params.currentStrike,
            params.kA,
            params.kB,
            postTradeVolatility,
            _yearsToMaturity(params.maturity)
        );

        deltaParams.sigma = postTradeVolatility;
        deltaParams.k = params.currentStrike;
        deltaParams.s = oraclePrice;
        deltaParams.tau = WadTime.nYears(WadTime.daysFromTs(block.timestamp, params.maturity));
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
        // TBD: move everything to the FinanceIGPrice library
        FinanceIGPrice.Parameters memory priceParams;
        {
            uint256 yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(block.timestamp, params.maturity));

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
        return FinanceIGPayoff.igPayoffPerc(
            oraclePrice,
            params.currentStrike, // ToDo: Verify that is always the current one
            params.kA,
            params.kB,
            params.theta
        );
    }

    function updateStrike(
        FinanceParameters storage params,
        uint256 oraclePrice,
        uint256 baseTokenAmount,
        uint256 sideTokenAmount,
        uint8 baseTokenDecimals,
        uint8 sideTokenDecimals
    ) public {
        // NOTE: both amounts are after equal weight rebalance, hence we can just compute their ratio.
        // Protect against division by zero
        // TBD: review expected strike when baseTokenAmount == 0
        // ---- maybe the finance formulas doen't like a zero strike ?
        if (baseTokenAmount == 0 || sideTokenAmount == 0) {
            params.currentStrike = oraclePrice;
        } else {
            baseTokenAmount = AmountsMath.wrapDecimals(baseTokenAmount, baseTokenDecimals);
            sideTokenAmount = AmountsMath.wrapDecimals(sideTokenAmount, sideTokenDecimals);

            params.currentStrike = baseTokenAmount.wdiv(sideTokenAmount);
        }
    }

    function updateParameters(
        FinanceParameters storage params,
        uint256 impliedVolatility,
        uint256 v0,
        uint256 previousMaturity // ToDo: check why it differs from block.timestamp
    ) public {
        // TBD: if there's no liquidity, we may avoid those computations
        params.sigmaZero = impliedVolatility;

        uint256 yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(previousMaturity, params.maturity));
        (params.kA, params.kB) = FinanceIGPrice.liquidityRange(
            FinanceIGPrice.LiquidityRangeParams(
                params.currentStrike,
                params.sigmaZero,
                params.sigmaMultiplier,
                yearsToMaturity
            )
        );

        // Multiply baselineVolatility for a safety margin of 0.9 after have calculated kA and Kb.
        params.sigmaZero = (params.sigmaZero * 90) / 100;

        params.theta = FinanceIGPrice._teta(
            params.currentStrike,
            params.kA,
            params.kB
        );

        (params.limSup, params.limInf) = FinanceIGDelta.lims(
            params.currentStrike,
            params.kA,
            params.kB,
            params.theta,
            v0
        );
    }
}
