// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

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
        // TODO
        uint256 teta;
        // concentrated liquidity range lower bound
        uint256 ka;
        // concentrated liquidity range upper bound
        uint256 kb;
    }

    /// @notice A wrapper for delta function intermediate steps
    struct DeltaIGAddends {
        // [ e^-(r τ) / 2 ] x [ e^-( d2^2 / 2) / Sσ√(2 pi τ)  ]
        uint256 c1;
        // N(d1) / 2K
        uint256 c2;
        // e^-( d1^2 / 2) / Kσ√(2 pi τ)
        uint256 c3;
        // [ 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)τ ] x N(d3)
        uint256 c4;
        // [ 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)τ ] x [ e^-( d3^2 / 2) / o√(2 pi τ) ]
        uint256 c5;
        // 1 / 2K
        uint256 c6;
        // 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)τ
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

    // /**
    //     @notice Computes unitary delta hedge quantity for up/down options
    //     @param params The set of DeltaPriceParams to compute deltas
    //     @return igDUp The unitary integer quantity of side token to hedge an up position
    //     @return igDDown The unitary integer quantity of side token to hedge a down position
    //  */
    // function igDeltas(DeltaPriceParams memory params) public pure returns (int256 igDUp, int256 igDDown) {
    //     (int256 d1_, int256 d2_, int256 d3_, uint256 sigmaTaurtd) = ds(params);
    //     uint256 sigmaTaurtdPi2rtd = sigmaTaurtd.wmul(PI2_RTD);
    //     {
    //         DeltaIGAddends memory cs_ = cs(params, d1_, d2_, d3_, sigmaTaurtdPi2rtd);
    //         uint256 c123 = cs_.c1 + cs_.c2 + cs_.c3;
    //         uint256 c45 = cs_.c4 + cs_.c5;
    //         igDUp = int256(c123) + SignedMath.neg(c45);
    //         igDDown = int256(cs_.c6) - int256(cs_.c7) - igDUp;
    //     }
    // }

    /**
        @notice Computes unitary price for up/down options
        @param params The set of DeltaPriceParams to compute the option price
        @return igPBull The unitary price for an up position
        @return igPBear The unitary price for a down position
     */
    function igPrices(DeltaPriceParams memory params) public pure returns (uint256 igPBull, uint256 igPBear) {
        (DTerms memory ds, DTerms memory das, DTerms memory dbs) = dTerms(params);
        NTerms memory ns = nTerms(ds);
        NTerms memory nas = nTerms(das);
        NTerms memory nbs = nTerms(dbs);

        uint256 ert = _ert(params.r, params.tau);
        uint256 sdivk = (params.s).wdiv(params.k);

        // Assume the price (up and down) is always >= 0
        {
            PriceParts memory ps = pBullParts(params, ert, sdivk, ns, nbs);
            igPBull = ps.p1 + ps.p2 - ps.p3 - ps.p4 - ps.p5;
        }
        {
            PriceParts memory ps = pBearParts(params, ert, sdivk, ns, nas);
            igPBear = ps.p1 + ps.p2 - ps.p3 - ps.p4 - ps.p5;
        }
    }

    //////  COMMON COMPONENTS //////

    struct DTerms {
        int256 d1; // [ ln(S / K) + ( r + σ^2 / 2 ) τ ] / σ√τ
        int256 d2; // d1 - σ√τ
        int256 d3; // d2 + σ√τ / 2
    }

    struct NTerms {
        uint256 n1; // N(d1)
        uint256 n2; // N(d2)
        uint256 n3; // N(d3)
    }

    function nTerms(DTerms memory ds) public pure returns (NTerms memory) {
        return NTerms(uint256(Gaussian.cdf(ds.d1)), uint256(Gaussian.cdf(ds.d2)), uint256(Gaussian.cdf(ds.d3)));
    }

    /**
        @notice Computes base components for delta and price formulas
        @param params The set of DeltaPriceParams to compute the option price
        @return ds ds terms computed with (price / K)
        @return das ds terms computed with (price / Ka)
        @return dbs ds terms computed with (price / Kb)
     */
    function dTerms(
        DeltaPriceParams memory params
    ) public pure returns (DTerms memory ds, DTerms memory das, DTerms memory dbs) {
        if (params.s == 0) {
            revert PriceZero();
        }

        uint256 r = params.s.wdiv(params.k); // S / K
        uint256 ra = params.s.wdiv(params.ka); // S / Ka
        uint256 rb = params.s.wdiv(params.kb); // S / Kb

        (uint256 sigmaTaurtd, uint256 q1) = d1Parts(params.r, params.sigma, params.tau);

        {
            int256 d1_ = d1(r, q1, sigmaTaurtd);
            int256 d2_ = d2(d1_, sigmaTaurtd);
            int256 d3_ = d3(d2_, sigmaTaurtd);
            ds = DTerms(d1_, d2_, d3_);
        }

        {
            int256 d1a_ = d1(ra, q1, sigmaTaurtd);
            int256 d2a_ = d2(d1a_, sigmaTaurtd);
            int256 d3a_ = d3(d2a_, sigmaTaurtd);
            das = DTerms(d1a_, d2a_, d3a_);
        }

        {
            int256 d1b_ = d1(rb, q1, sigmaTaurtd);
            int256 d2b_ = d2(d1b_, sigmaTaurtd);
            int256 d3b_ = d3(d2b_, sigmaTaurtd);
            dbs = DTerms(d1b_, d2b_, d3b_);
        }
    }

    /// @dev σ√τ AND ( r + σ^2 / 2 ) τ
    function d1Parts(uint256 r, uint256 sigma, uint256 tau) public pure returns (uint256 sigmaTaurtd, uint256 q1) {
        q1 = (r + (sigma.wmul(sigma) / 2)).wmul(tau);
        sigmaTaurtd = sigma.wmul(FixedPointMathLib.sqrt(tau));
    }

    /// @dev [ ln(S / K) + ( r + σ^2 / 2 ) τ ] / σ√τ
    function d1(uint256 priceStrikeRt, uint256 q1, uint256 sigmaTaurtd) public pure returns (int256 d1_) {
        int256 q0 = FixedPointMathLib.ln(SignedMath.castInt(priceStrikeRt));
        (uint256 sumQty, bool sumPos) = SignedMath.sum(q0, q1);
        uint256 res = sumQty.wdiv(sigmaTaurtd);

        return SignedMath.revabs(res, sumPos);
    }

    /// @dev d1 - σ√τ
    function d2(int256 d1_, uint256 sigmaTaurtd) public pure returns (int256) {
        return d1_ - SignedMath.castInt(sigmaTaurtd);
    }

    /// @dev d2 + σ√τ / 2
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
        @param sigmaTaurtdPi2rtd σ√(2 pi τ)
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

    /// @dev [ e^-(r τ) / 2 ] x [ e^-( d2^2 / 2) / Sσ√(2 pi τ)  ]
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

    /// @dev e^-( d1^2 / 2) / Kσ√(2 pi τ)
    function c3(int256 d1_, uint256 k, uint256 sigmaTaurtdPi2rtd) public pure returns (uint256) {
        uint256 q = FixedPointMathLib.exp(SignedMath.neg(SignedMath.pow2(d1_) / 2));
        uint256 den = k.wmul(sigmaTaurtdPi2rtd);
        return q.wdiv(den) / 2;
    }

    /// @dev [ 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)τ ] x N(d3)
    function c4(uint256 bo, int256 d3_) public pure returns (uint256) {
        return (bo / 2).wmul(uint256(Gaussian.cdf(d3_)));
    }

    /// @dev [ 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)τ ] x [ e^-( d3^2 / 2) / o√(2 pi τ) ]
    function c5(uint256 bo, int256 d3_, uint256 sigmaTaurtdPi2rtd) public pure returns (uint256) {
        uint256 q2 = FixedPointMathLib.exp(SignedMath.neg(SignedMath.pow2(d3_) / 2));
        q2 = q2.wdiv(sigmaTaurtdPi2rtd);

        return bo.wmul(q2);
    }

    /// @dev 1 / 2K
    function c6(uint256 k) public pure returns (uint256) {
        return AmountsMath.wrap(1).wdiv(2 * k);
    }

    /// @dev 1 / 2√(KS) x e^-(r / 2 + σ^2 / 8)τ
    function c7(uint256 bo) public pure returns (uint256) {
        return bo / 2;
    }

    ////// PRICING COMPONENTS //////

    struct PriceParts {
        uint256 p1;
        uint256 p2;
        uint256 p3;
        uint256 p4;
        uint256 p5;
    }

    function pBullParts(
        DeltaPriceParams memory params,
        uint256 ert,
        uint256 sdivk,
        NTerms memory ns,
        NTerms memory nbs
    ) public pure returns (PriceParts memory) {
        uint256 ertdivteta = ert.wdiv(params.teta);
        return
            PriceParts(
                pbull1(ertdivteta, ns.n2),
                pbull2(sdivk, params.teta, ns.n1),
                pbull3(sdivk, params.sigma, params.r, params.tau, params.teta, ns.n3, nbs.n3),
                pbull4(params.s, _tetakkrtd(params.teta, params.k, params.kb), nbs.n1),
                pbull5(ert, _kdivkrtddivteta(params.teta, params.k, params.kb), nbs.n2)
            );
    }

    function pBearParts(
        DeltaPriceParams memory params,
        uint256 ert,
        uint256 sdivk,
        NTerms memory ns,
        NTerms memory nas
    ) public pure returns (PriceParts memory) {
        uint256 ertdivteta = ert.wdiv(params.teta);
        return
            PriceParts(
                pbear1(ertdivteta, ns.n2),
                pbear2(sdivk, params.teta, ns.n1),
                pbear3(sdivk, params.sigma, params.r, params.tau, params.teta, ns.n3, nas.n3),
                pbear4(params.s, _tetakkrtd(params.teta, params.k, params.ka), nas.n1),
                pbear5(ert, _kdivkrtddivteta(params.teta, params.k, params.ka), nas.n2)
            );
    }

    /////// BEAR PRICE COMPONENTS ///////

    /// @dev [ e^-(r τ) / θ ] * (1 - N(d2))
    function pbear1(uint256 ertdivteta, uint256 n2) public pure returns (uint256) {
        return ertdivteta.wmul(1e18 - n2);
    }

    /// @dev S/θK * (1 - N(d1))
    function pbear2(uint256 sdivk, uint256 teta, uint256 n1) public pure returns (uint256) {
        return sdivk.wdiv(teta).wmul(1e18 - n1);
    }

    /// @dev [ 2/θ * √(S / K) e^-(r / 2 + σ^2 / 8)τ ] * [ N(d3a) - N(d3) ]
    function pbear3(
        uint256 sdivk,
        uint256 sigma,
        uint256 r,
        uint256 tau,
        uint256 teta,
        uint256 n3,
        uint256 n3a
    ) public pure returns (uint256) {
        uint256 e1 = FixedPointMathLib.exp(SignedMath.neg(_boexp(r, sigma, tau)));
        uint256 coeff = (FixedPointMathLib.sqrt(sdivk).wmul(e1) * 2).wdiv(teta);
        return coeff.wmul(n3a - n3);
    }

    /// @dev [ s / θ√(K K_b) ] * (1 - N(d1a))
    function pbear4(uint256 s, uint256 tetakkartd, uint256 n1a) public pure returns (uint256) {
        return s.wdiv(tetakkartd).wmul(1e18 - n1a);
    }

    /// @dev 1/θ * √(K_b / K) * N(1 - d2a)
    function pbear5(uint256 ert, uint256 kadivkrtddivteta, uint256 n2a) public pure returns (uint256) {
        return ert.wmul(kadivkrtddivteta.wmul(1e18 - n2a));
    }

    /////// BULL PRICE COMPONENTS ///////

    /// @dev [ e^-(r τ) / θ ] * N(d2)
    function pbull1(uint256 ertdivteta, uint256 n2) public pure returns (uint256) {
        return ertdivteta.wmul(n2);
    }

    /// @dev S/θK * N(d1)
    function pbull2(uint256 sdivk, uint256 teta, uint256 n1) public pure returns (uint256) {
        return sdivk.wdiv(teta).wmul(n1);
    }

    /// @dev [ 2/θ * √(S / K) e^-(r / 2 + σ^2 / 8)τ ] * [ N(d3) - N(d3b) ]
    function pbull3(
        uint256 sdivk,
        uint256 sigma,
        uint256 r,
        uint256 tau,
        uint256 teta,
        uint256 n3,
        uint256 n3b
    ) public pure returns (uint256) {
        uint256 e1 = FixedPointMathLib.exp(SignedMath.neg(_boexp(r, sigma, tau)));
        uint256 coeff = (FixedPointMathLib.sqrt(sdivk).wmul(e1) * 2).wdiv(teta);
        return coeff.wmul(n3 - n3b);
    }

    /// @dev [ s / θ√(K K_b) ] * N(d1b)
    function pbull4(uint256 s, uint256 tetakkbrtd, uint256 n1b) public pure returns (uint256) {
        return s.wdiv(tetakkbrtd).wmul(n1b);
    }

    /// @dev 1/θ * √(K_b / K) * N(d2b)
    function pbull5(uint256 ert, uint256 kbdivkrtddivteta, uint256 n2b) public pure returns (uint256) {
        return ert.wmul(kbdivkrtddivteta.wmul(n2b));
    }

    ////// HELPERS //////

    /// @dev √(KS)
    function _ksrtd(uint256 k, uint256 s) public pure returns (uint256) {
        return FixedPointMathLib.sqrt(k.wmul(s));
    }

    /// @dev (r / 2 + σ^2 / 8)τ
    function _boexp(uint256 r, uint256 sigma, uint256 tau) public pure returns (uint256) {
        return tau.wmul(r / 2 + SignedMath.pow2(int256(sigma)) / 8);
    }

    /// @dev 1 / √(KS) x e^-(r / 2 + σ^2 / 8)τ
    function _bo(DeltaPriceParams memory params) public pure returns (uint256) {
        uint256 e1 = FixedPointMathLib.exp(SignedMath.neg(_boexp(params.r, params.sigma, params.tau)));
        return e1.wdiv(_ksrtd(params.k, params.s));
    }

    /// @dev e^-(r τ)
    function _ert(uint256 r, uint256 tau) public pure returns (uint256) {
        return FixedPointMathLib.exp(SignedMath.neg(r.wmul(tau)));
    }

    /// @dev θ * √(K K_<a|b>)
    function _tetakkrtd(uint256 teta, uint256 k, uint256 krange) public pure returns (uint256) {
        return teta.wmul(FixedPointMathLib.sqrt(k.wmul(krange)));
    }

    /// @dev 1/θ * √(K_<a|b> / K)
    function _kdivkrtddivteta(uint256 teta, uint256 k, uint256 krange) public pure returns (uint256) {
        return FixedPointMathLib.sqrt(krange.wdiv(k)).wdiv(teta);
    }

    /// @dev θ = 2 - √(Ka / K) - √(K / Kb)
    function _teta(uint256 k, uint256 ka, uint256 kb) public pure returns (uint256 teta) {
        return 2e18 - FixedPointMathLib.sqrt(ka.wdiv(k)) - FixedPointMathLib.sqrt(k.wdiv(kb));
    }
}
