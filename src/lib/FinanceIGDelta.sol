// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

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

    ////// DELTA //////
    /**
     * @param alfa2 σB
     * @return m
     * @return q
     * @dev m = (-0.22)σB + 1.8 + (σB^2 / 100)
     * @dev q = 0.95σB - (σB^2 / 10)
     */
    function mqParams(int256 alfa2) internal pure returns (int256 m, int256 q) {
        uint256 alfaAbs = SignedMath.abs(alfa2);
        uint256 alfaSqrd = SignedMath.pow2(alfa2);

        m = SignedMath.revabs((alfaAbs * 22) / 100, false) + SignedMath.castInt(uint256(1.8e18).add((alfaSqrd / 100)));
        q = SignedMath.castInt((alfaAbs * 95) / 100) - (SignedMath.castInt(alfaSqrd) / 10);
    }

    /**
        @notice Computes unitary delta hedge quantity for bull/bear options
        @param params The set of Parameters to compute deltas
        @return igDBull The unitary integer quantity of side token to hedge a bull position
        @return igDBear The unitary integer quantity of side token to hedge a bear position
        @dev the formulas are the ones for different ranges of liquidity
    */
    function deltaHedgePercentages(Parameters calldata params) external pure returns (int256 igDBull, int256 igDBear) {
        uint256 sigmaTaurtd = _sigmaTaurtd(params.sigma, params.tau);
        int256 z = _z(params.s, params.k, sigmaTaurtd);
        (int256 m, int256 q) = mqParams(params.alfa2);

        igDBull = bullDelta(z, sigmaTaurtd, params.limSup, m, q);
        igDBear = bearDelta(z, sigmaTaurtd, params.limInf, m, q);
    }

    /// @dev limSup / (1 + e^(-m*z + a*q))
    function bullDelta(
        int256 z,
        uint256 sigmaTaurtd,
        int256 limSup,
        int256 m,
        int256 q
    ) internal pure returns (int256) {
        uint256 sigmaTaurtdSquared = sigmaTaurtd.wmul(sigmaTaurtd);

        // a := 0.9 - σ√τ / 2 - 0.04 * (σ√τ)^2
        int256 a = int256(0.9e18) -
            (SignedMath.castInt(sigmaTaurtd) / 2) -
            SignedMath.castInt((sigmaTaurtdSquared * 4) / 100);

        // -m*z + a*q
        int256 expE = SignedMath.revabs(
            SignedMath.abs(m).wmul(SignedMath.abs(z)),
            (m > 0 && z < 0) || (m < 0 && z > 0)
        ) + SignedMath.revabs(SignedMath.abs(a).wmul(SignedMath.abs(q)), (a > 0 && q > 0) || (a < 0 && q < 0));
        if (expE > _MAX_EXP) {
            return 0;
        }
        uint256 denom = 1e18 + sd(expE).exp().intoUint256();

        return SignedMath.castInt(uint256(limSup).wdiv(denom));
    }

    /// @dev liminf / (1 + e^(m*z + b*q))
    function bearDelta(
        int256 z,
        uint256 sigmaTaurtd,
        int256 limInf,
        int256 m,
        int256 q
    ) internal pure returns (int256) {
        uint256 sigmaTaurtdSquared = sigmaTaurtd.wmul(sigmaTaurtd);

        // b := 0.95 + σ√τ / 2 + 0.08 * (σ√τ)^2
        uint256 b = uint256(0.95e18).add(sigmaTaurtd / 2).add(((sigmaTaurtdSquared * 8) / 100));

        // m*z + b*q
        int256 expE = SignedMath.revabs(
            SignedMath.abs(m).wmul(SignedMath.abs(z)),
            (m > 0 && z > 0) || (m < 0 && z < 0)
        ) + SignedMath.revabs(b.wmul(SignedMath.abs(q)), (q > 0));
        if (expE > _MAX_EXP) {
            return 0;
        }

        uint256 denom = 1e18 + sd(expE).exp().intoUint256();
        return SignedMath.revabs(SignedMath.abs(limInf).wdiv(denom), limInf > 0);
    }

    function deltaHedgeAmount(DeltaHedgeParameters memory params) public pure returns (int256 tokensToSwap) {
        return _h(params);
    }

    /**
        @notice Return the amount of side tokens to swap.
        @param params The DeltaHedgeParameters info
        @return tokensToSwap An integer amount, positive when there are side tokens in excess (need to sell) and negative vice versa
     */
    function _h(DeltaHedgeParameters memory params) internal pure returns (int256 tokensToSwap) {
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

        uint256 notionalUp = AmountsMath.wrapDecimals(SignedMath.abs(params.notionalUp), params.baseTokenDecimals);
        uint256 notionalDown = AmountsMath.wrapDecimals(SignedMath.abs(params.notionalDown), params.baseTokenDecimals);
        params.sideTokensAmount = AmountsMath.wrapDecimals(params.sideTokensAmount, params.sideTokenDecimals);

        uint256 protoNotionalUp = params.availableLiquidityBull;
        if (params.notionalUp >= 0) {
            protoNotionalUp = protoNotionalUp.sub(notionalUp);
        } else {
            protoNotionalUp = protoNotionalUp.add(notionalUp);
        }
        uint256 protoNotionalDown = params.availableLiquidityBear;
        if (params.notionalDown >= 0) {
            protoNotionalDown = protoNotionalDown.sub(notionalDown);
        } else {
            protoNotionalDown = protoNotionalDown.add(notionalDown);
        }

        uint256 protoDeltaUp = SignedMath.abs(params.igDBull).wmul(protoNotionalUp).wdiv(params.initialLiquidityBull);
        uint256 protoDeltaDown = SignedMath.abs(params.igDBear).wmul(protoNotionalDown).wdiv(params.initialLiquidityBear);

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
            SignedMath.revabs(protoDeltaUp, params.igDBull >= 0) +
            SignedMath.revabs(protoDeltaDown, params.igDBear >= 0) +
            SignedMath.castInt(params.sideTokensAmount) -
            SignedMath.castInt(deltaLimit);

        params.sideTokensAmount = SignedMath.abs(tokensToSwap);
        params.sideTokensAmount = AmountsMath.unwrapDecimals(params.sideTokensAmount, params.sideTokenDecimals);
        tokensToSwap = SignedMath.revabs(params.sideTokensAmount, tokensToSwap >= 0);
    }

    ////// HELPERS //////

    function lims(
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 teta,
        uint256 v0
    ) public pure returns (int256 limSup_, int256 limInf_) {
        uint256 krtd = ud(k).sqrt().unwrap();
        uint256 tetaK = teta.wmul(k);
        limSup_ = _limSup(krtd, kb, tetaK, v0);
        limInf_ = _limInf(krtd, ka, tetaK, v0);
    }

    /// @dev V0 * ((√Kb - √K) / (θ K √Kb))
    function _limSup(uint256 krtd, uint256 kb, uint256 tetaK, uint256 v0) internal pure returns (int256) {
        uint256 kbrtd = ud(kb).sqrt().unwrap();
        return SignedMath.castInt((kbrtd - krtd).wdiv(tetaK.wmul(kbrtd)).wmul(v0));
    }

    /// @dev V0 * (√Ka - √K) / (θ K √Ka)
    function _limInf(uint256 krtd, uint256 ka, uint256 tetaK, uint256 v0) internal pure returns (int256) {
        uint256 kartd = ud(ka).sqrt().unwrap();
        return SignedMath.revabs((krtd - kartd).wdiv(tetaK.wmul(kartd)).wmul(v0), false);
    }

    /**
        @notice Computes auxiliary params α1, α2
        @param k Strike
        @param ka Lower bound concentrated liquidity range
        @param kb Upper bound concentrated liquidity range
        @param sigma Implied vol.
        @param t Epoch duration in years
        @return alfa1 α1 = ln(Ka / K) / σ√T
        @return alfa2 α2 = ln(Kb / K) / σ√T [= -α1 when log-symmetric Ka - K - Kb]
        // T è D-X/365 dove D è il giorno della scadenza e X è il giorno attuale (7-2/365);
     */
    function alfas(
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 sigma,
        uint256 t
    ) public pure returns (int256 alfa1, int256 alfa2) {
        uint256 sigmaTrtd = _sigmaTaurtd(sigma, t);
        {
            int256 alfa1Num = ud(ka.wdiv(k)).intoSD59x18().ln().unwrap();
            alfa1 = SignedMath.revabs((SignedMath.abs(alfa1Num).wdiv(sigmaTrtd)), alfa1Num > 0);
        }
        {
            int256 alfa2Num = ud(kb.wdiv(k)).intoSD59x18().ln().unwrap();
            alfa2 = SignedMath.revabs((SignedMath.abs(alfa2Num).wdiv(sigmaTrtd)), alfa2Num > 0);
        }
    }

    /// @dev σ√τ
    function _sigmaTaurtd(uint256 sigma, uint256 tau) internal pure returns (uint256) {
        return sigma.wmul(ud(tau).sqrt().unwrap());
    }

    /// @dev ln(S / K) / σ√τ
    function _z(uint256 s, uint256 k, uint256 sigmaTaurtd) internal pure returns (int256) {
        int256 n = sd(SignedMath.castInt(s.wdiv(k))).ln().unwrap();
        return SignedMath.revabs(SignedMath.abs(n).wdiv(sigmaTaurtd), n > 0);
    }
}
