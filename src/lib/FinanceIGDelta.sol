// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;
import {console} from "forge-std/console.sol";
import {InverseTrigonometry} from "@trigonometry/InverseTrigonometry.sol";
import {Trigonometry} from "@trigonometry/Trigonometry.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
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

    struct DeltaExpParamentersAbs {
        uint256 m;
        uint256 x;
        uint256 p;
        uint256 q;
    }

    int256 internal constant MAX_EXP = 135305999368893231589;

    ////// DELTA //////
    /**
     * @param alfa2 σB
     * @return m
     * @return q
     * @dev m = (-0.22)σB + 1.8 + (σB^2 / 100)
     * @dev q = 0.95σB - (σB^2 / 10)
     */
    function _mqParams(int256 alfa2) internal pure returns (int256 m, int256 q) {
        uint256 alfaAbs = SignedMath.abs(alfa2);
        uint256 alfaPow = SignedMath.pow2(alfa2);

        m =
            SignedMath.revabs(AmountsMath.wrapDecimals(22, 2).wmul(alfaAbs), false) +
            SignedMath.castInt(AmountsMath.wrapDecimals(18, 1).add((alfaPow / 100)));

        q = SignedMath.castInt(AmountsMath.wrapDecimals(95, 2).wmul(alfaAbs)) - (SignedMath.castInt(alfaPow) / 10);
    }

    /**
        @notice Computes unitary delta hedge quantity for bull/bear options
        @param params The set of Parameters to compute deltas
        @return igDBull The unitary integer quantity of side token to hedge a bull position
        @return igDBear The unitary integer quantity of side token to hedge a bear position
        @dev the formulas are the ones for different ranges of liquidity
    */
    function igDeltas(Parameters calldata params) external view returns (int256 igDBull, int256 igDBear) {
        uint256 sigmaTaurtd = _sigmaTaurtd(params.sigma, params.tau);
        int256 x = _x(params.s, params.k, sigmaTaurtd);
        (int256 m, int256 q) = _mqParams(params.alfa2);

        igDBull = bullDelta(x, sigmaTaurtd, params.limSup, m, q);
        igDBear = bearDelta(x, sigmaTaurtd, params.limInf, m, q);
    }

    /// @dev limSup / (1 + e^(-m*z + a*q))
    function bullDelta(int256 x, uint256 sigmaTaurtd, int256 limSup, int256 m, int256 q) public pure returns (int256) {
        uint256 sigmaTaurtdPow = sigmaTaurtd.wmul(sigmaTaurtd);
        int256 a = SignedMath.castInt(AmountsMath.wrapDecimals(9, 1)) -
            (SignedMath.castInt(sigmaTaurtd) / 2) -
            SignedMath.castInt(AmountsMath.wrapDecimals(4, 2).wmul(sigmaTaurtdPow));

        // Avoid Stack Too Deep
        DeltaExpParamentersAbs memory dParams = DeltaExpParamentersAbs(
            SignedMath.abs(m),
            SignedMath.abs(x),
            SignedMath.abs(a),
            SignedMath.abs(q)
        );

        int256 expE = SignedMath.revabs(dParams.m.wmul(dParams.x), (m > 0 && x < 0) || (m < 0 && x > 0)) +
            SignedMath.revabs(dParams.p.wmul(dParams.q), (a > 0 && q > 0) || (a < 0 && q < 0));
        if (expE > MAX_EXP) {
            return 0;
        }
        uint256 denom = 1e18 + FixedPointMathLib.exp(expE);

        return SignedMath.castInt(uint256(limSup).wdiv(denom));
    }

    /// @dev liminf / (1 + e^(m*z + b*q))
    function bearDelta(int256 x, uint256 sigmaTaurtd, int256 limInf, int256 m, int256 q) public view returns (int256) {
        uint256 sigmaTaurtdPow = SignedMath.pow2(SignedMath.castInt(sigmaTaurtd));

        uint256 b = AmountsMath.wrapDecimals(95, 2).add(sigmaTaurtd / 2).add(
            (AmountsMath.wrapDecimals(8, 2).wmul(sigmaTaurtdPow))
        );

        //ToDo: Fix
        DeltaExpParamentersAbs memory dParams = DeltaExpParamentersAbs(
            SignedMath.abs(m),
            SignedMath.abs(x),
            SignedMath.abs(0),
            SignedMath.abs(q)
        );

        int256 expE = SignedMath.revabs(dParams.m.wmul(dParams.x), (m > 0 && x > 0) || (m < 0 && x < 0)) +
            SignedMath.revabs(b.wmul(dParams.q), (q > 0));
        if (expE > MAX_EXP) {
            return 0;
        }

        uint256 denom = 1e18 + FixedPointMathLib.exp(expE);
        return SignedMath.revabs(SignedMath.abs(limInf).wdiv(denom), limInf > 0);
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
    }

    function h(DeltaHedgeParameters memory params) public view returns (int256 tokensToSwap) {
        // {
        //     console.log("params.igDBull");
        //     console.logInt(params.igDBull);
        //     console.log("params.igDBear");
        //     console.logInt(params.igDBear);
        //     console.log("baseTokenDecimals", params.baseTokenDecimals);
        //     console.log("sideTokenDecimals", params.sideTokenDecimals);
        //     console.log("initialLiquidityBull", params.initialLiquidityBull);
        //     console.log("initialLiquidityBear", params.initialLiquidityBear);
        //     console.log("availableLiquidityBull", params.availableLiquidityBull);
        //     console.log("availableLiquidityBear", params.availableLiquidityBear);
        //     console.log("sideTokensAmount", params.sideTokensAmount);
        //     console.log("notionalUp");
        //     console.logInt(params.notionalUp);
        //     console.log("notionalDown");
        //     console.logInt(params.notionalDown);
        //     console.log("strike", params.strike);
        // }
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
        uint256 two = AmountsMath.wrap(2);

        uint256 notionalBull = params.availableLiquidityBull;
        if (params.notionalUp >= 0) {
            notionalBull = notionalBull.sub(notionalUp);
        } else {
            notionalBull = notionalBull.add(notionalUp);
        }
        uint256 notionalBear = params.availableLiquidityBear;
        if (params.notionalDown >= 0) {
            notionalBear = notionalBear.sub(notionalDown);
        } else {
            notionalBear = notionalBear.add(notionalDown);
        }

        uint256 up = SignedMath.abs(params.igDBull).wmul(notionalBull).wdiv(params.initialLiquidityBull);
        uint256 down = SignedMath.abs(params.igDBear).wmul(notionalBear).wdiv(params.initialLiquidityBear);

        uint256 deltaLimit;
        {
            uint256 v0 = params.initialLiquidityBull + params.initialLiquidityBear;
            deltaLimit = v0.wdiv(params.strike.wmul(two));
        }

        tokensToSwap =
            SignedMath.revabs(up, params.igDBull >= 0) +
            SignedMath.revabs(down, params.igDBear >= 0) +
            SignedMath.castInt(params.sideTokensAmount) -
            SignedMath.castInt(deltaLimit);

        params.sideTokensAmount = SignedMath.abs(tokensToSwap);
        params.sideTokensAmount = AmountsMath.unwrapDecimals(params.sideTokensAmount, params.sideTokenDecimals);
        tokensToSwap = SignedMath.revabs(params.sideTokensAmount, tokensToSwap >= 0);
        // console.log("Token to Swap");
        // console.logInt(tokensToSwap);
    }

    ////// HELPERS //////

    function lims(
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 teta,
        uint256 v0
    ) public pure returns (int256 limSup, int256 limInf) {
        uint256 krtd = FixedPointMathLib.sqrt(k);
        uint256 tetaK = teta.wmul(k);
        limSup = _limSup(krtd, kb, tetaK, v0);
        limInf = _limInf(krtd, ka, tetaK, v0);
    }

    /// @dev V0 * ((√Kb - √K) / (θ K √Kb))
    function _limSup(uint256 krtd, uint256 kb, uint256 tetaK, uint256 v0) public pure returns (int256) {
        uint256 kbrtd = FixedPointMathLib.sqrt(kb);
        return SignedMath.castInt((kbrtd - krtd).wdiv(tetaK.wmul(kbrtd)).wmul(v0));
    }

    /// @dev V0 * (√Ka - √K) / (θ K √Ka)
    function _limInf(uint256 krtd, uint256 ka, uint256 tetaK, uint256 v0) public pure returns (int256) {
        uint256 kartd = FixedPointMathLib.sqrt(ka);
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
    function _alfas(
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 sigma,
        uint256 t
    ) public pure returns (int256 alfa1, int256 alfa2) {
        uint256 sigmaTrtd = _sigmaTaurtd(sigma, t);
        int256 alfa1Num = FixedPointMathLib.ln(SignedMath.castInt(ka.wdiv(k)));
        int256 alfa2Num = FixedPointMathLib.ln(SignedMath.castInt(kb.wdiv(k)));
        alfa1 = SignedMath.revabs((SignedMath.abs(alfa1Num).wdiv(sigmaTrtd)), alfa1Num > 0);
        alfa2 = SignedMath.revabs((SignedMath.abs(alfa2Num).wdiv(sigmaTrtd)), alfa2Num > 0);
    }

    /// @dev arctanx = arcsin x / √(1 + x^2)
    function atan(int256 x) public pure returns (int256 result) {
        uint256 xAbs = SignedMath.abs(x);
        uint256 den = FixedPointMathLib.sqrt(1e18 + xAbs.wmul(xAbs));
        return InverseTrigonometry.arcsin(SignedMath.revabs(xAbs.wdiv(den), x > 0));
    }

    /// @dev σ√τ
    function _sigmaTaurtd(uint256 sigma, uint256 tau) public pure returns (uint256) {
        return sigma.wmul(FixedPointMathLib.sqrt(tau));
    }

    // ToDo: rename "_z" in order to match the paper
    /// @dev ln(S / K) / σ√τ
    function _x(uint256 s, uint256 k, uint256 sigmaTaurtd) public pure returns (int256) {
        int256 n = FixedPointMathLib.ln(SignedMath.castInt(s.wdiv(k)));
        return SignedMath.revabs(SignedMath.abs(n).wdiv(sigmaTaurtd), n > 0);
    }
}
