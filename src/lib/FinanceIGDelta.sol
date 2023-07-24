// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

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

    ////// DELTA //////

    /**
        @notice Computes unitary delta hedge quantity for bull/bear options
        @param params The set of Parameters to compute deltas
        @return igDBull The unitary integer quantity of side token to hedge a bull position
        @return igDBear The unitary integer quantity of side token to hedge a bear position
        @dev the formulas are the ones for different ranges of liquidity
     */
    function igDeltas(Parameters calldata params) external pure returns (int256 igDBull, int256 igDBear) {
        uint256 sigmaTaurtd = _sigmaTaurtd(params.sigma, params.tau);
        int256 x = _x(params.s, params.k, sigmaTaurtd);
        (int256 bullAtanArg_, int256 bearAtanArg_) = atanArgs(x, params.alfa1, params.alfa2);

        igDBull = bullDelta(x, params.limSup, bullAtanArg_);
        igDBear = bearDelta(x, params.limInf, bearAtanArg_);
    }

    /// @dev 2/π * limSup * atan(arg)
    function bullDelta(int256 x, int256 limSup, int256 atanArg) public pure returns (int256) {
        if (x < 0) {
            return 0;
        }
        uint256 num = SignedMath.abs(2 * limSup);
        int256 atan_ = atan(atanArg);
        num = num.wmul(SignedMath.abs(atan_));
        int256 res = SignedMath.castInt(num.wdiv(Trigonometry.PI));
        return (limSup < 0 && atan_ >= 0) || (limSup >= 0 && atan_ < 0) ? -res : res;
    }

    /// @dev -2/π * limInf * atan(arg)
    function bearDelta(int256 x, int256 limInf, int256 atanArg) public pure returns (int256) {
        if (x > 0) {
            return 0;
        }
        uint256 num = SignedMath.abs(2 * limInf);
        int256 atan_ = atan(atanArg);
        num = num.wmul(SignedMath.abs(atan_));
        int256 res = SignedMath.castInt(num.wdiv(Trigonometry.PI));
        return (limInf < 0 && atan_ >= 0) || (limInf >= 0 && atan_ < 0) ? res : -res;
    }

    /// @dev bullAtanArg_ = 2x/α2 - [ (α2/2 - x) / (α2 - α1) ] * x^2/2
    /// @dev bearAtanArg_ = 2x/α2 + [ (x - α1/2) / (α2 - α1) ] * x^2/2
    function atanArgs(
        int256 x,
        int256 alfa1,
        int256 alfa2
    ) public pure returns (int256 bullAtanArg_, int256 bearAtanArg_) {
        uint256 xAbs = SignedMath.abs(x);
        uint256 c1 = (2 * xAbs).wdiv(SignedMath.abs(alfa2));
        uint256 c22 = xAbs.wmul(xAbs) / 2;

        bullAtanArg_ = bullAtanArg(x, alfa1, alfa2, c1, c22);
        bearAtanArg_ = bearAtanArg(x, alfa1, alfa2, c1, c22);
    }

    function bullAtanArg(int256 x, int256 alfa1, int256 alfa2, uint256 c1, uint256 c22) public pure returns (int256) {
        int256 c21Num = (alfa2 / 2) - x;
        uint256 c21Abs = SignedMath.abs(c21Num).wdiv(SignedMath.abs(alfa2 - alfa1));
        uint256 c2 = c21Abs.wmul(c22);

        return SignedMath.revabs(c1, x > 0) - SignedMath.revabs(c2, c21Num > 0);
    }

    function bearAtanArg(int256 x, int256 alfa1, int256 alfa2, uint256 c1, uint256 c22) public pure returns (int256) {
        int256 c21Num = x - (alfa1 / 2);
        uint256 c21Abs = SignedMath.abs(c21Num).wdiv(SignedMath.abs(alfa2 - alfa1));
        uint256 c2 = c21Abs.wmul(c22);

        return SignedMath.revabs(c1, x > 0) + SignedMath.revabs(c2, c21Num > 0);
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

    function h(DeltaHedgeParameters memory params) public pure returns (int256 tokensToSwap) {
        params.initialLiquidityBull = AmountsMath.wrapDecimals(params.initialLiquidityBull, params.baseTokenDecimals);
        params.initialLiquidityBear = AmountsMath.wrapDecimals(params.initialLiquidityBear, params.baseTokenDecimals);
        params.availableLiquidityBull = AmountsMath.wrapDecimals(params.availableLiquidityBull, params.baseTokenDecimals);
        params.availableLiquidityBear = AmountsMath.wrapDecimals(params.availableLiquidityBear, params.baseTokenDecimals);
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
        if (params.notionalUp >= 0) {
            notionalBear = notionalBear.sub(notionalDown);
        } else {
            notionalBear = notionalBear.add(notionalDown);
        }
        uint256 up = SignedMath.abs(params.igDBull).wmul(two).wmul(notionalBull);
        uint256 down = SignedMath.abs(params.igDBear).wmul(two).wmul(notionalBear);

        uint256 deltaLimit;
        {
            uint256 v0 = params.initialLiquidityBull + params.initialLiquidityBear;
            deltaLimit = v0.wdiv(params.strike.wmul(two));
        }

        tokensToSwap = SignedMath.revabs(up, params.igDBull >= 0) + SignedMath.revabs(down, params.igDBear >= 0) + SignedMath.castInt(params.sideTokensAmount) - SignedMath.castInt(deltaLimit);
        params.sideTokensAmount = SignedMath.abs(tokensToSwap);
        params.sideTokensAmount = AmountsMath.unwrapDecimals(params.sideTokensAmount, params.sideTokenDecimals);
        tokensToSwap = SignedMath.revabs(params.sideTokensAmount, tokensToSwap >= 0);
    }

    ////// HELPERS //////

    function lims(uint256 k, uint256 ka, uint256 kb, uint256 teta) public pure returns (int256 limSup, int256 limInf) {
        uint256 krtd = FixedPointMathLib.sqrt(k);
        uint256 tetaK = teta.wmul(k);
        limSup = _limSup(krtd, kb, tetaK);
        limInf = _limInf(krtd, ka, tetaK);
    }

    /// @dev (√Kb - √K) / (θ K √Kb)
    function _limSup(uint256 krtd, uint256 kb, uint256 tetaK) public pure returns (int256) {
        uint256 kbrtd = FixedPointMathLib.sqrt(kb);
        return SignedMath.castInt((kbrtd - krtd).wdiv(tetaK.wmul(kbrtd)));
    }

    /// @dev (√Ka - √K) / (θ K √Ka)
    function _limInf(uint256 krtd, uint256 ka, uint256 tetaK) public pure returns (int256) {
        uint256 kartd = FixedPointMathLib.sqrt(ka);
        return SignedMath.revabs((krtd - kartd).wdiv(tetaK.wmul(kartd)), false);
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
