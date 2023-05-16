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

    uint256 private constant MAX_INT = 57896044618658097711785492504343953926634992332820282019728792003956564819967;

    /// @dev √(2 pi)
    uint256 public constant PI2_RTD = 2_506628274631000502;

    error PriceZero();
    error OutOfRange(string varname, uint256 value);

    struct DeltaIGParams {
        uint256 r;
        uint256 sigma;
        uint256 K;
        uint256 S;
        uint256 tau;
    }

    struct DeltaIGComponents {
        uint256 c1;
        uint256 c2;
        uint256 c3;
        uint256 c4;
        uint256 c5;
        uint256 c6;
        uint256 c7;
    }

    function igDeltas(DeltaIGParams memory params) public pure returns (int256 igDUp, int256 igDDown) {
        (int256 d1_, int256 d2_, int256 d3_, uint256 sigmaTaurtd) = ds(params);
        uint256 sigmaTaurtdPi2rtd = sigmaTaurtd.wmul(PI2_RTD);
        {
            DeltaIGComponents memory cs_ = cs(params, d1_, d2_, d3_, sigmaTaurtdPi2rtd);
            uint256 c123 = cs_.c1 + cs_.c2 + cs_.c3;
            uint256 c45 = cs_.c4 + cs_.c5;
            igDUp = int256(c123) + SignedMath.neg(c45);
            igDDown = int256(cs_.c6) - int256(cs_.c7) - igDUp;
        }
    }

    function cs(
        DeltaIGParams memory params,
        int256 d1_,
        int256 d2_,
        int256 d3_,
        uint256 sigmaTaurtdPi2rtd
    ) public pure returns (DeltaIGComponents memory cs_) {
        uint256 bo = _bo(params);
        uint256 c1_ = c1(params.r, params.tau, d2_, params.S, sigmaTaurtdPi2rtd);
        uint256 c2_ = c2(params.K, d1_);
        uint256 c3_ = c3(d1_, params.K, sigmaTaurtdPi2rtd);
        uint256 c4_ = c4(bo, d3_);
        uint256 c5_ = c5(bo, d3_, sigmaTaurtdPi2rtd);
        uint256 c6_ = c6(params.K);
        uint256 c7_ = c7(bo);
        return DeltaIGComponents(c1_, c2_, c3_, c4_, c5_, c6_, c7_);
    }

    function ds(
        DeltaIGParams memory params
    ) public pure returns (int256 d1_, int256 d2_, int256 d3_, uint256 sigmaTaurtd) {
        if (params.S == 0) {
            revert PriceZero();
        }

        uint256 priceStrikeRt = params.S.wdiv(params.K);
        if (priceStrikeRt > MAX_INT) {
            revert OutOfRange("ds_priceStrikeRt", priceStrikeRt);
        }

        (d1_, sigmaTaurtd) = d1(params.r, params.sigma, int256(priceStrikeRt), params.tau);
        d2_ = d2(d1_, sigmaTaurtd);
        d3_ = d3(d2_, sigmaTaurtd);
    }

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

    function d2(int256 d1_, uint256 sigmaTaurtd) public pure returns (int256) {
        if (sigmaTaurtd > MAX_INT) {
            revert OutOfRange("d2_sigmaTaurtd", sigmaTaurtd);
        }
        return d1_ - int256(sigmaTaurtd);
    }

    function d3(int256 d2_, uint256 sigmaTaurtd) public pure returns (int256) {
        return d2_ + int256(sigmaTaurtd / 2);
    }

    /// @dev [ e^-(r t) / 2 ] x [ e^-( d2^2 / 2) / Sσ√(2 pi t)  ]
    function c1(
        uint256 r,
        uint256 tau,
        int256 d2_,
        uint256 S,
        uint256 sigmaTaurtdPi2rtd
    ) public pure returns (uint256) {
        uint256 e1 = FixedPointMathLib.exp(SignedMath.neg(r.wmul(tau)));
        uint256 e2 = FixedPointMathLib.exp(SignedMath.neg(SignedMath.pow2(d2_) / 2));
        uint256 den = S.wmul(sigmaTaurtdPi2rtd);

        return e1.wmul(e2).wdiv(den) / 2;
    }

    /// @dev N(d1) / 2K
    function c2(uint256 K, int256 d1_) public pure returns (uint256) {
        return uint256(Gaussian.cdf(d1_)).wdiv(2 * K);
    }

    /// @dev e^-( d1^2 / 2) / Kσ√(2 pi t)
    function c3(int256 d1_, uint256 K, uint256 sigmaTaurtdPi2rtd) public pure returns (uint256) {
        uint256 q = FixedPointMathLib.exp(SignedMath.neg(SignedMath.pow2(d1_) / 2));
        uint256 den = K.wmul(sigmaTaurtdPi2rtd);
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

    /// @dev 1 / 2 K
    function c6(uint256 K) private pure returns (uint256) {
        return AmountsMath.wrap(1).wdiv(2 * K);
    }

    /// @dev 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)t
    function c7(uint256 bo) private pure returns (uint256) {
        return bo / 2;
    }

    ////// HELPERS //////

    /// @dev √(KS)
    function _ksrtd(uint256 K, uint256 S) private pure returns (uint256) {
        return FixedPointMathLib.sqrt(K.wmul(S));
    }

    /// @dev (r / 2 + σ^2 / 8)t
    function _boexp(uint256 r, uint256 sigma, uint256 tau) private pure returns (uint256) {
        return tau.wmul(r / 2 + SignedMath.pow2(int256(sigma)) / 8);
    }

    /// @dev 1 / √(KS) x e^-(r / 2 + σ^2 / 8)t
    function _bo(DeltaIGParams memory params) private pure returns (uint256) {
        uint256 e1 = FixedPointMathLib.exp(SignedMath.neg(_boexp(params.r, params.sigma, params.tau)));
        return e1.wdiv(_ksrtd(params.K, params.S));
    }
}
