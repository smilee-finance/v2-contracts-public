// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/console.sol";

import {Gaussian} from "@solstat/Gaussian.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";

/// @title Implementation of core financial computations for Smilee protocol
library Finance {
    using AmountsMath for uint256;

    /// @dev √(2 pi)
    uint256 public constant PI2_RTD = 2_506628274631000502;

    error PriceZero();
    error OutOfRange(string varname, uint256 value);

    /// @notice A wrapper for the input parameters of delta and price functions
    struct DeltaPriceParams {
        // risk free rate
        uint256 r;
        // implied volatility
        uint256 sigma;
        // strike
        uint256 k;
        // reference price
        uint256 s;
        // time (denominated in years)
        uint256 tau;
    }

    /// @notice A wrapper for delta function intermediate steps
    struct DeltaIGAddends {
        // [ e^-(r t) / 2 ] x [ e^-( d2^2 / 2) / Sσ√(2 pi t)  ]
        uint256 c1;
        // N(d1) / 2K
        uint256 c2;
        // e^-( d1^2 / 2) / Kσ√(2 pi t)
        uint256 c3;
        // [ 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)t ] x N(d3)
        uint256 c4;
        // [ 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)t ] x [ e^-( d3^2 / 2) / o√(2 pi t) ]
        uint256 c5;
        // 1 / 2K
        uint256 c6;
        // 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)t
        uint256 c7;
    }

    /**
        @notice Computes impermanent gain percentage
        @dev Only depends on current price and strike
        @param s Current side token price
        @param k Ref. strike
        @return payoffPerc The impermanent gain
     */
    function igPerc(uint256 s, uint256 k) public pure returns (uint256 payoffPerc) {
        uint256 sdivk = s.wdiv(k);
        return AmountsMath.wrap(1) / 2 + sdivk / 2 - FixedPointMathLib.sqrt(sdivk);
    }

    /**
        @notice Computes payoff percentage for impermanent gain up / down strategies
        @param s Current side token price
        @param k Ref. strike
        @return payoffUp The percentage payoff for up strategy
        @return payoffDown The percentage payoff for down strategy
     */
    function igPayoffPerc(uint256 s, uint256 k) public pure returns (uint256 payoffUp, uint256 payoffDown) {
        payoffUp = s > k ? igPerc(s, k) : 0;
        payoffDown = s < k ? igPerc(s, k) : 0;
    }

    /**
        @notice Computes unitary delta hedge quantity for up/down options
        @param params The set of DeltaPriceParams to compute deltas
        @return igDUp The unitary integer quantity of side token to hedge an up position
        @return igDDown The unitary integer quantity of side token to hedge a down position
     */
    function igDeltas(DeltaPriceParams memory params) public pure returns (int256 igDUp, int256 igDDown) {
        (int256 d1_, int256 d2_, int256 d3_, uint256 sigmaTaurtd) = ds(params);
        uint256 sigmaTaurtdPi2rtd = sigmaTaurtd.wmul(PI2_RTD);
        {
            DeltaIGAddends memory cs_ = cs(params, d1_, d2_, d3_, sigmaTaurtdPi2rtd);
            uint256 c123 = cs_.c1 + cs_.c2 + cs_.c3;
            uint256 c45 = cs_.c4 + cs_.c5;
            igDUp = int256(c123) + SignedMath.neg(c45);
            igDDown = int256(cs_.c6) - int256(cs_.c7) - igDUp;
        }
    }

    /**
        @notice Computes unitary price for up/down options
        @param params The set of DeltaPriceParams to compute the option price
        @return igPUp The unitary price for an up position
        @return igPDown The unitary price for a down position
     */
    function igPrices(DeltaPriceParams memory params) public pure returns (uint256 igPUp, uint256 igPDown) {
        (uint256 p1_, uint256 p2_, uint256 p3_) = ps(params);
        (int256 d1_, int256 d2_, int256 d3_, ) = ds(params);
        uint256 n1 = uint256(Gaussian.cdf(d1_));
        uint256 n2 = uint256(Gaussian.cdf(d2_));
        uint256 n3 = uint256(Gaussian.cdf(d3_));

        // Assume the price (up and down) is always >= 0
        {
            // p1 x N(d2) + p2 x N(d1) - p3 N(d3)
            (uint256 pu1, uint256 pu2, uint256 pu3) = pus(p1_, p2_, p3_, n1, n2, n3);
            igPUp = pu1 + pu2 - pu3;
        }
        {
            // p1 x (1 - N(d2)) + p2 x (1 - N(d1)) - p3 (1 - N(d3))
            (uint256 pd1, uint256 pd2, uint256 pd3) = pds(p1_, p2_, p3_, n1, n2, n3);
            igPDown = pd1 + pd2 - pd3;
        }
    }

    ////// COMMON COMPONENTS //////

    /**
        @notice Computes base components for delta and price formulas
        @param params The set of DeltaPriceParams to compute the option price
        @return d1_ [ ln(S / K) + ( r + σ^2 / 2 ) t ] / σ√t
        @return d2_  d1_ - σ√t
        @return d3_  d2_ + σ√t / 2
        @return sigmaTaurtd σ√t is a d1_ subproduct, reused by callers
     */
    function ds(
        DeltaPriceParams memory params
    ) public pure returns (int256 d1_, int256 d2_, int256 d3_, uint256 sigmaTaurtd) {
        if (params.s == 0) {
            revert PriceZero();
        }

        uint256 priceStrikeRt = params.s.wdiv(params.k);
        (d1_, sigmaTaurtd) = d1(params.r, params.sigma, SignedMath.castInt(priceStrikeRt), params.tau);
        d2_ = d2(d1_, sigmaTaurtd);
        d3_ = d3(d2_, sigmaTaurtd);
    }

    /// @dev [ ln(S / K) + ( r + σ^2 / 2 ) t ] / σ√t
    function d1(
        uint256 r,
        uint256 sigma,
        int256 priceStrikeRt,
        uint256 tau
    ) public pure returns (int256 d1_, uint256 sigmaTaurtd) {
        int256 q0 = FixedPointMathLib.ln(priceStrikeRt);
        uint256 q1 = (r + (sigma.wmul(sigma) / 2)).wmul(tau);
        sigmaTaurtd = sigma.wmul(FixedPointMathLib.sqrt(tau));
        (uint256 sumQty, bool sumPos) = SignedMath.sum(q0, q1);
        uint256 res = sumQty.wdiv(sigmaTaurtd);

        return (SignedMath.revabs(res, sumPos), sigmaTaurtd);
    }

    /// @dev d1 - σ√t
    function d2(int256 d1_, uint256 sigmaTaurtd) public pure returns (int256) {
        return d1_ - SignedMath.castInt(sigmaTaurtd);
    }

    /// @dev d2 + σ√t / 2
    function d3(int256 d2_, uint256 sigmaTaurtd) public pure returns (int256) {
        return d2_ + int256(sigmaTaurtd / 2);
    }

    ////// DELTA COMPONENTS //////

    /**
        @notice Computes components for delta formulas
        @param params The parameters set
        @param d1_ See `Finance.ds()`
        @param d2_ See `Finance.ds()`
        @param d3_ See `Finance.ds()`
        @param sigmaTaurtdPi2rtd σ√(2 pi t)
        @return cs_ The DeltaIGAddends wrapper for delta addends
     */
    function cs(
        DeltaPriceParams memory params,
        int256 d1_,
        int256 d2_,
        int256 d3_,
        uint256 sigmaTaurtdPi2rtd
    ) public pure returns (DeltaIGAddends memory cs_) {
        uint256 bo = _bo(params);
        uint256 c1_ = c1(params.r, params.tau, d2_, params.s, sigmaTaurtdPi2rtd);
        uint256 c2_ = c2(params.k, d1_);
        uint256 c3_ = c3(d1_, params.k, sigmaTaurtdPi2rtd);
        uint256 c4_ = c4(bo, d3_);
        uint256 c5_ = c5(bo, d3_, sigmaTaurtdPi2rtd);
        uint256 c6_ = c6(params.k);
        uint256 c7_ = c7(bo);
        return DeltaIGAddends(c1_, c2_, c3_, c4_, c5_, c6_, c7_);
    }

    /// @dev [ e^-(r t) / 2 ] x [ e^-( d2^2 / 2) / Sσ√(2 pi t)  ]
    function c1(
        uint256 r,
        uint256 tau,
        int256 d2_,
        uint256 s,
        uint256 sigmaTaurtdPi2rtd
    ) public pure returns (uint256) {
        uint256 e1 = _ert(r, tau);
        uint256 e2 = FixedPointMathLib.exp(SignedMath.neg(SignedMath.pow2(d2_) / 2));
        uint256 den = s.wmul(sigmaTaurtdPi2rtd);

        return e1.wmul(e2).wdiv(den) / 2;
    }

    /// @dev N(d1) / 2K
    function c2(uint256 k, int256 d1_) public pure returns (uint256) {
        return uint256(Gaussian.cdf(d1_)).wdiv(2 * k);
    }

    /// @dev e^-( d1^2 / 2) / Kσ√(2 pi t)
    function c3(int256 d1_, uint256 k, uint256 sigmaTaurtdPi2rtd) public pure returns (uint256) {
        uint256 q = FixedPointMathLib.exp(SignedMath.neg(SignedMath.pow2(d1_) / 2));
        uint256 den = k.wmul(sigmaTaurtdPi2rtd);
        return q.wdiv(den) / 2;
    }

    /// @dev [ 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)t ] x N(d3)
    function c4(uint256 bo, int256 d3_) public pure returns (uint256) {
        return (bo / 2).wmul(uint256(Gaussian.cdf(d3_)));
    }

    /// @dev [ 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)t ] x [ e^-( d3^2 / 2) / o√(2 pi t) ]
    function c5(uint256 bo, int256 d3_, uint256 sigmaTaurtdPi2rtd) public pure returns (uint256) {
        uint256 q2 = FixedPointMathLib.exp(SignedMath.neg(SignedMath.pow2(d3_) / 2));
        q2 = q2.wdiv(sigmaTaurtdPi2rtd);

        return bo.wmul(q2);
    }

    /// @dev 1 / 2K
    function c6(uint256 k) public pure returns (uint256) {
        return AmountsMath.wrap(1).wdiv(2 * k);
    }

    /// @dev 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)t
    function c7(uint256 bo) public pure returns (uint256) {
        return bo / 2;
    }

    ////// PRICING COMPONENTS //////

    function pus(
        uint256 p1_,
        uint256 p2_,
        uint256 p3_,
        uint256 n1,
        uint256 n2,
        uint256 n3
    ) public pure returns (uint256 pu1, uint256 pu2, uint256 pu3) {
        return (p1_.wmul(n2), p2_.wmul(n1), p3_.wmul(n3));
    }

    function pds(
        uint256 p1_,
        uint256 p2_,
        uint256 p3_,
        uint256 n1,
        uint256 n2,
        uint256 n3
    ) public pure returns (uint256 pd1, uint256 pd2, uint256 pd3) {
        uint256 one = AmountsMath.wrap(1);
        return (p1_.wmul(one - n2), p2_.wmul(one - n1), p3_.wmul(one - n3));
    }

    function ps(DeltaPriceParams memory params) public pure returns (uint256 p1_, uint256 p2_, uint256 p3_) {
        uint256 sdivk = params.s.wdiv(params.k);
        p1_ = p1(params.r, params.tau);
        p2_ = p2(sdivk);
        p3_ = p3(sdivk, params.sigma, params.r, params.tau);
    }

    /// @dev 1 / 2 e^-(r t)
    function p1(uint256 r, uint256 tau) public pure returns (uint256) {
        return _ert(r, tau) / 2;
    }

    /// @dev S / 2K
    function p2(uint256 sdivk) public pure returns (uint256) {
        return sdivk / 2;
    }

    /// @dev √(S / k) e^-(r / 2 + σ^2 / 8)t
    function p3(uint256 sdivk, uint256 sigma, uint256 r, uint256 tau) public pure returns (uint256) {
        uint256 e1 = FixedPointMathLib.exp(SignedMath.neg(_boexp(r, sigma, tau)));
        return FixedPointMathLib.sqrt(sdivk).wmul(e1);
    }

    ////// HELPERS //////

    /// @dev √(KS)
    function _ksrtd(uint256 k, uint256 s) private pure returns (uint256) {
        return FixedPointMathLib.sqrt(k.wmul(s));
    }

    /// @dev (r / 2 + σ^2 / 8)t
    function _boexp(uint256 r, uint256 sigma, uint256 tau) private pure returns (uint256) {
        return tau.wmul(r / 2 + SignedMath.pow2(int256(sigma)) / 8);
    }

    /// @dev 1 / √(KS) x e^-(r / 2 + σ^2 / 8)t
    function _bo(DeltaPriceParams memory params) private pure returns (uint256) {
        uint256 e1 = FixedPointMathLib.exp(SignedMath.neg(_boexp(params.r, params.sigma, params.tau)));
        return e1.wdiv(_ksrtd(params.k, params.s));
    }

    /// @dev e^-(r t)
    function _ert(uint256 r, uint256 tau) private pure returns (uint256) {
        return FixedPointMathLib.exp(SignedMath.neg(r.wmul(tau)));
    }
}
