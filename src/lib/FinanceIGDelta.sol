// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SD59x18, sd} from "@prb/math/SD59x18.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";

/// @title Implementation of core financial computations for Smilee protocol
library FinanceIGDelta {
    /// @notice A wrapper for the input parameters of delta functions
    struct Parameters {
        ////// INPUTS //////
        // implied volatility
        uint256 sigma;
        // strike
        uint256 k;
        // reference price
        uint256 s;
        // time (denominated in years)
        uint256 tau;
        ////// DERIVED //////
        // (√Kb - √K) / (θ K √Kb)
        int256 limSup;
        // (√Ka - √K) / (θ K √Ka)
        int256 limInf;
        // ln(Ka / K) / σ√τ
        int256 alfa1;
        // ln(Kb / K) / σ√τ
        int256 alfa2;
    }

    struct DeltaHedgeParameters {
        int256 igDBull;
        int256 igDBear;
        uint8 baseTokenDecimals;
        uint8 sideTokenDecimals;
        uint256 initialLiquidityBull;
        uint256 initialLiquidityBear;
        uint256 availableLiquidityBull;
        uint256 availableLiquidityBear;
        uint256 sideTokensAmount;
        int256 notionalUp;
        int256 notionalDown;
        uint256 strike;
        uint256 theta;
        uint256 kb;
    }

    int256 internal constant _MAX_EXP = 135305999368893231589;

    /**
        @notice Computes unitary delta hedge quantity for bull/bear options
        @param params The set of Parameters to compute deltas
        @return igDBull The unitary integer quantity of side token to hedge a bull position
        @return igDBear The unitary integer quantity of side token to hedge a bear position
        @dev the formulas are the ones for different ranges of liquidity
    */
    function deltaHedgePercentages(Parameters calldata params) external pure returns (int256 igDBull, int256 igDBear) {
        uint256 sigmaTaurtd_ = sigmaTaurtd(params.sigma, params.tau);
        int256 z_ = z(params.s, params.k, sigmaTaurtd_);
        (int256 m, int256 q) = mqParams(params.alfa2);

        igDBull = bullDelta(z_, sigmaTaurtd_, params.limSup, m, q);
        igDBear = bearDelta(z_, sigmaTaurtd_, params.limInf, m, q);
    }

    /**
        @notice Gives the amount of side tokens to swap in order to hedge protocol delta exposure
        @param params The DeltaHedgeParameters info
        @return tokensToSwap An integer amount, positive when there are side tokens in excess (need to sell) and negative vice versa
        @dev This is what's called `h` in the papers
     */
    function deltaHedgeAmount(DeltaHedgeParameters memory params) public pure returns (int256 tokensToSwap) {
        params.initialLiquidityBull = AmountsMath.wrapDecimals(params.initialLiquidityBull, params.baseTokenDecimals);
        params.initialLiquidityBear = AmountsMath.wrapDecimals(params.initialLiquidityBear, params.baseTokenDecimals);
        params.availableLiquidityBull = AmountsMath.wrapDecimals(
            params.availableLiquidityBull,
            params.baseTokenDecimals
        );
        params.availableLiquidityBear = AmountsMath.wrapDecimals(
            params.availableLiquidityBear,
            params.baseTokenDecimals
        );

        uint256 notionalBull = AmountsMath.wrapDecimals(SignedMath.abs(params.notionalUp), params.baseTokenDecimals);
        uint256 notionalBear = AmountsMath.wrapDecimals(SignedMath.abs(params.notionalDown), params.baseTokenDecimals);
        params.sideTokensAmount = AmountsMath.wrapDecimals(params.sideTokensAmount, params.sideTokenDecimals);

        uint256 protoNotionalBull = params.notionalUp >= 0
            ? ud(params.availableLiquidityBull).sub(ud(notionalBull)).unwrap()
            : ud(params.availableLiquidityBull).add(ud(notionalBull)).unwrap();

        uint256 protoNotionalBear = params.notionalDown >= 0
            ? ud(params.availableLiquidityBear).sub(ud(notionalBear)).unwrap()
            : ud(params.availableLiquidityBear).add(ud(notionalBear)).unwrap();

        uint256 protoDBull = ud(SignedMath.abs(params.igDBull)).mul(ud(protoNotionalBull)).div(ud(params.initialLiquidityBull)).unwrap();
        uint256 protoDBear = ud(SignedMath.abs(params.igDBear)).mul(ud(protoNotionalBear)).div(ud(params.initialLiquidityBear)).unwrap();

        uint256 deltaLimit;
        {
            UD60x18 v0 = ud(params.initialLiquidityBull + params.initialLiquidityBear);
            UD60x18 strike = ud(params.strike);
            UD60x18 theta = ud(params.theta);
            UD60x18 kb = ud(params.kb);
            // DeltaLimit := v0 / (θ * k) - v0 / (θ * √(K * Kb))
            deltaLimit = v0.div(theta.mul(strike)).sub(v0.div(theta.mul(strike.mul(kb).sqrt()))).unwrap();
        }

        tokensToSwap =
            SignedMath.revabs(protoDBull, params.igDBull >= 0) +
            SignedMath.revabs(protoDBear, params.igDBear >= 0) +
            SignedMath.castInt(params.sideTokensAmount) -
            SignedMath.castInt(deltaLimit);

        params.sideTokensAmount = SignedMath.abs(tokensToSwap);
        params.sideTokensAmount = AmountsMath.unwrapDecimals(params.sideTokensAmount, params.sideTokenDecimals);
        tokensToSwap = SignedMath.revabs(params.sideTokensAmount, tokensToSwap >= 0);
    }

    /**
        @notice Calculate deltaTrade given notional and unitary integer quantity of bull and bear posizion or both.
        @param amountUp The bull notional
        @param amountDown The bear notional
        @param igDBull The unitary integer quantity of side token to hedge a bull position
        @param igDBear The unitary integer quantity of side token to hedge a bear position
        @return deltaTrade_ := amountUp * igDBull + amountDown * igDBear
     */
    function deltaTrade(
        uint256 amountUp,
        uint256 amountDown,
        int256 igDBull,
        int256 igDBear
    ) public pure returns (int256 deltaTrade_) {
        UD60x18 udAmountUp = ud(amountUp);
        UD60x18 udAmountDown = ud(amountDown);
        UD60x18 udIgDBull = ud(SignedMath.abs(igDBull));
        UD60x18 udIgDBear = ud(SignedMath.abs(igDBear));
        
        deltaTrade_ = SignedMath.revabs(udAmountUp.mul(udIgDBull).unwrap(), igDBull > 0) +
            SignedMath.revabs(udAmountDown.mul(udIgDBear).unwrap(), igDBear > 0);
    }

    ////// HELPERS //////

    /**
        @notice Computes auxiliary params limSup, limInf
        @param k Strike
        @param ka Lower bound concentrated liquidity range
        @param kb Upper bound concentrated liquidity range
        @param teta Teta
        @param v0 Initial notional
        @return limSup_ := V0 * (√Kb - √K) / (θ K √Kb)
        @return limInf_ := V0 * (√Ka - √K) / (θ K √Ka)
     */
    function lims(
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 teta,
        uint256 v0
    ) public pure returns (int256 limSup_, int256 limInf_) {
        uint256 krtd = ud(k).sqrt().unwrap();
        uint256 tetaK = ud(teta).mul(ud(k)).unwrap();
        limSup_ = limSup(krtd, kb, tetaK, v0);
        limInf_ = limInf(krtd, ka, tetaK, v0);
    }

    /**
        @notice Computes auxiliary params α1, α2
        @param k Strike
        @param ka Lower bound concentrated liquidity range
        @param kb Upper bound concentrated liquidity range
        @param sigma Implied vol.
        @param t Epoch duration in years
        @return alfa1 α1 := ln(Ka / K) / σ√T
        @return alfa2 α2 := ln(Kb / K) / σ√T [= -α1 when log-symmetric Ka - K - Kb]
     */
    function alfas(
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 sigma,
        uint256 t
    ) public pure returns (int256 alfa1, int256 alfa2) {
        UD60x18 sigmaTrtd_ = ud(sigmaTaurtd(sigma, t));
        {
            int256 alfa1Num = ud(ka).div(ud(k)).intoSD59x18().ln().unwrap();
            alfa1 = SignedMath.revabs(ud(SignedMath.abs(alfa1Num)).div(sigmaTrtd_).unwrap(), alfa1Num > 0);
        }
        {
            int256 alfa2Num = ud(kb).div(ud(k)).intoSD59x18().ln().unwrap();
            alfa2 = SignedMath.revabs(ud(SignedMath.abs(alfa2Num)).div(sigmaTrtd_).unwrap(), alfa2Num > 0);
        }
    }

    /// @dev Δ_bull := limSup / (1 + e^(-m*z + a*q))
    function bullDelta(
        int256 z_,
        uint256 sigmaTrtd,
        int256 limSup_,
        int256 m,
        int256 q
    ) internal pure returns (int256) {
        uint256 sigmaTaurtdSquared = ud(sigmaTrtd).mul(ud(sigmaTrtd)).unwrap();

        int256 expE = 0;
        {
            // a := 0.9 - σ√τ / 2 - 0.04 * (σ√τ)^2
            int256 a = int256(0.9e18) -
                (SignedMath.castInt(sigmaTrtd) / 2) -
                SignedMath.castInt((sigmaTaurtdSquared * 4) / 100);

            // expE := -m*z + a*q
            UD60x18 mz = ud(SignedMath.abs(m)).mul(ud(SignedMath.abs(z_)));
            UD60x18 aq = ud(SignedMath.abs(a)).mul(ud(SignedMath.abs(q)));
            int256 smz = SignedMath.revabs(mz.unwrap(), (m > 0 && z_ < 0) || (m < 0 && z_ > 0));
            expE = smz + SignedMath.revabs(aq.unwrap(), (a > 0 && q > 0) || (a < 0 && q < 0));
        }
        if (expE > _MAX_EXP) {
            return 0;
        }

        // d := 1 + e^(expE)
        UD60x18 denom = ud(1e18 + sd(expE).exp().intoUint256());
        return SignedMath.castInt(ud(uint256(limSup_)).div(denom).unwrap());
    }

    /// @dev Δ_bear := liminf / (1 + e^(m*z + b*q))
    function bearDelta(
        int256 z_,
        uint256 sigmaTrtd,
        int256 limInf_,
        int256 m,
        int256 q
    ) internal pure returns (int256) {
        int256 expE = 0;
        {
            // b := 0.95 + σ√τ / 2 + 0.08 * (σ√τ)^2
            UD60x18 sigmaTaurtdSquared = ud(sigmaTrtd).mul(ud(sigmaTrtd));
            UD60x18 b = ud(0.95e18).add(ud(sigmaTrtd).div(convert(2))).add(sigmaTaurtdSquared.mul(convert(8)).div(convert(100)));

            // expE := m*z + b*q
            expE = SignedMath.revabs(
                ud(SignedMath.abs(m)).mul(ud(SignedMath.abs(z_))).unwrap(),
                (m > 0 && z_ > 0) || (m < 0 && z_ < 0)
            ) + SignedMath.revabs(b.mul(ud(SignedMath.abs(q))).unwrap(), (q > 0));
        }
        if (expE > _MAX_EXP) {
            return 0;
        }

        // d := 1 + e^(expE)
        UD60x18 denom = convert(1).add(ud(sd(expE).exp().intoUint256()));
        return SignedMath.revabs(ud(SignedMath.abs(limInf_)).div(denom).unwrap(), limInf_ > 0);
    }

    /**
        @param alfa2 := σB
        @return m := (-0.22)σB + 1.8 + (σB^2 / 100)
        @return q := 0.95σB - (σB^2 / 10)
     */
    function mqParams(int256 alfa2) internal pure returns (int256 m, int256 q) {
        uint256 alfaAbs = SignedMath.abs(alfa2);
        uint256 alfaSqrd = SignedMath.pow2(alfa2);

        m = - SignedMath.revabs((alfaAbs * 22) / 100, alfa2 >= 0) + SignedMath.castInt(1.8e18 + (alfaSqrd / 100));
        q = SignedMath.revabs((alfaAbs * 95) / 100, alfa2 >= 0) - (SignedMath.castInt(alfaSqrd) / 10);
    }

    /// @dev limSup := V0 * (√Kb - √K) / (θ K √Kb)
    function limSup(uint256 krtd, uint256 kb, uint256 tetaK, uint256 v0) internal pure returns (int256) {
        UD60x18 kbrtd = ud(kb).sqrt();
        return SignedMath.castInt(kbrtd.sub(ud(krtd)).div(ud(tetaK).mul(kbrtd)).mul(ud(v0)).unwrap());
    }

    /// @dev limInf := V0 * (√Ka - √K) / (θ K √Ka)
    function limInf(uint256 krtd, uint256 ka, uint256 tetaK, uint256 v0) internal pure returns (int256) {
        UD60x18 kartd = ud(ka).sqrt();
        return SignedMath.revabs(ud(krtd).sub(kartd).div(ud(tetaK).mul(kartd)).mul(ud(v0)).unwrap(), false);
    }

    /// @dev σ√τ
    function sigmaTaurtd(uint256 sigma, uint256 tau) internal pure returns (uint256) {
        return ud(sigma).mul(ud(tau).sqrt()).unwrap();
    }

    /// @dev z := ln(S / K) / σ√τ
    function z(uint256 s, uint256 k, uint256 sigmaTrtd) internal pure returns (int256) {
        int256 n = sd(SignedMath.castInt(ud(s).div(ud(k)).unwrap())).ln().unwrap();
        return SignedMath.revabs(ud(SignedMath.abs(n)).div(ud(sigmaTrtd)).unwrap(), n > 0);
    }
}
