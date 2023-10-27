// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SD59x18, sd} from "@prb/math/SD59x18.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";

/// @title Implementation of core financial computations for Smilee protocol
library FinanceIGDelta {
    using AmountsMath for uint256;

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
            ? params.availableLiquidityBull.sub(notionalBull)
            : params.availableLiquidityBull.add(notionalBull);

        uint256 protoNotionalBear = params.notionalDown >= 0
            ? params.availableLiquidityBear.sub(notionalBear)
            : params.availableLiquidityBear.add(notionalBear);

        uint256 protoDBull = SignedMath.abs(params.igDBull).wmul(protoNotionalBull).wdiv(params.initialLiquidityBull);
        uint256 protoDBear = SignedMath.abs(params.igDBear).wmul(protoNotionalBear).wdiv(params.initialLiquidityBear);

        uint256 deltaLimit;
        {
            uint256 v0 = params.initialLiquidityBull + params.initialLiquidityBear;
            uint256 strike = params.strike;
            uint256 theta = params.theta;
            uint256 kb = params.kb;
            // DeltaLimit := v0 / (θ * k) - v0 / (θ * √(K * Kb))
            deltaLimit = v0.wdiv(theta.wmul(strike)).sub(v0.wdiv(theta.wmul(ud((strike.wmul(kb))).sqrt().unwrap())));
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
        uint256 tetaK = teta.wmul(k);
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
        uint256 sigmaTrtd_ = sigmaTaurtd(sigma, t);
        {
            int256 alfa1Num = ud(ka.wdiv(k)).intoSD59x18().ln().unwrap();
            alfa1 = SignedMath.revabs((SignedMath.abs(alfa1Num).wdiv(sigmaTrtd_)), alfa1Num > 0);
        }
        {
            int256 alfa2Num = ud(kb.wdiv(k)).intoSD59x18().ln().unwrap();
            alfa2 = SignedMath.revabs((SignedMath.abs(alfa2Num).wdiv(sigmaTrtd_)), alfa2Num > 0);
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
        uint256 sigmaTaurtdSquared = sigmaTrtd.wmul(sigmaTrtd);

        // a := 0.9 - σ√τ / 2 - 0.04 * (σ√τ)^2
        int256 a = int256(0.9e18) -
            (SignedMath.castInt(sigmaTrtd) / 2) -
            SignedMath.castInt((sigmaTaurtdSquared * 4) / 100);

        // expE := -m*z + a*q
        int256 expE = SignedMath.revabs(
            SignedMath.abs(m).wmul(SignedMath.abs(z_)),
            (m > 0 && z_ < 0) || (m < 0 && z_ > 0)
        ) + SignedMath.revabs(SignedMath.abs(a).wmul(SignedMath.abs(q)), (a > 0 && q > 0) || (a < 0 && q < 0));
        if (expE > _MAX_EXP) {
            return 0;
        }

        // d := 1 + e^(expE)
        uint256 denom = 1e18 + sd(expE).exp().intoUint256();
        return SignedMath.castInt(uint256(limSup_).wdiv(denom));
    }

    /// @dev Δ_bear := liminf / (1 + e^(m*z + b*q))
    function bearDelta(
        int256 z_,
        uint256 sigmaTrtd,
        int256 limInf_,
        int256 m,
        int256 q
    ) internal pure returns (int256) {
        uint256 sigmaTaurtdSquared = sigmaTrtd.wmul(sigmaTrtd);

        // b := 0.95 + σ√τ / 2 + 0.08 * (σ√τ)^2
        uint256 b = uint256(0.95e18).add(sigmaTrtd / 2).add(((sigmaTaurtdSquared * 8) / 100));

        // expE := m*z + b*q
        int256 expE = SignedMath.revabs(
            SignedMath.abs(m).wmul(SignedMath.abs(z_)),
            (m > 0 && z_ > 0) || (m < 0 && z_ < 0)
        ) + SignedMath.revabs(b.wmul(SignedMath.abs(q)), (q > 0));
        if (expE > _MAX_EXP) {
            return 0;
        }

        // d := 1 + e^(expE)
        uint256 denom = 1e18 + sd(expE).exp().intoUint256();
        return SignedMath.revabs(SignedMath.abs(limInf_).wdiv(denom), limInf_ > 0);
    }

    /**
        @param alfa2 := σB
        @return m := (-0.22)σB + 1.8 + (σB^2 / 100)
        @return q := 0.95σB - (σB^2 / 10)
     */
    function mqParams(int256 alfa2) internal pure returns (int256 m, int256 q) {
        uint256 alfaAbs = SignedMath.abs(alfa2);
        uint256 alfaSqrd = SignedMath.pow2(alfa2);

        m = SignedMath.revabs((alfaAbs * 22) / 100, false) + SignedMath.castInt(uint256(1.8e18).add((alfaSqrd / 100)));
        q = SignedMath.castInt((alfaAbs * 95) / 100) - (SignedMath.castInt(alfaSqrd) / 10);
    }

    /// @dev limSup := V0 * (√Kb - √K) / (θ K √Kb)
    function limSup(uint256 krtd, uint256 kb, uint256 tetaK, uint256 v0) internal pure returns (int256) {
        uint256 kbrtd = ud(kb).sqrt().unwrap();
        return SignedMath.castInt((kbrtd - krtd).wdiv(tetaK.wmul(kbrtd)).wmul(v0));
    }

    /// @dev limInf := V0 * (√Ka - √K) / (θ K √Ka)
    function limInf(uint256 krtd, uint256 ka, uint256 tetaK, uint256 v0) internal pure returns (int256) {
        uint256 kartd = ud(ka).sqrt().unwrap();
        return SignedMath.revabs((krtd - kartd).wdiv(tetaK.wmul(kartd)).wmul(v0), false);
    }

    /// @dev σ√τ
    function sigmaTaurtd(uint256 sigma, uint256 tau) internal pure returns (uint256) {
        return sigma.wmul(ud(tau).sqrt().unwrap());
    }

    /// @dev z := ln(S / K) / σ√τ
    function z(uint256 s, uint256 k, uint256 sigmaTrtd) internal pure returns (int256) {
        int256 n = sd(SignedMath.castInt(s.wdiv(k))).ln().unwrap();
        return SignedMath.revabs(SignedMath.abs(n).wdiv(sigmaTrtd), n > 0);
    }
}
