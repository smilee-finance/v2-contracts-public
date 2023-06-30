// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/console.sol";

import {Gaussian} from "@solstat/Gaussian.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";
import {InverseTrigonometry} from "@trigonometry/InverseTrigonometry.sol";
import {Trigonometry} from "@trigonometry/Trigonometry.sol";

/// @title Implementation of core financial computations for Smilee protocol
library Finance {
    using AmountsMath for uint256;

    error PriceZero();
    error OutOfRange(string varname, uint256 value);

    /// @notice A wrapper for the input parameters of delta and price functions
    struct DeltaPriceParams {
        ////// INPUTS //////
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
        // concentrated liquidity range lower bound
        uint256 ka;
        // concentrated liquidity range upper bound
        uint256 kb;
        ////// DERIVED //////
        // θ = 2 - √(Ka / K) - √(K / Kb)
        uint256 teta;
        // (√Kb - √K) / (θ K √Kb)
        int256 limSup;
        // (√Ka - √K) / (θ K √Ka)
        int256 limInf;
        // ln(Ka / K) / σ√τ
        int256 alfa1;
        // ln(Kb / K) / σ√τ
        int256 alfa2;
    }

    ////// PAYOFF //////

    /**
        @notice Computes concentrated liquidity impermanent gain percentage when current price falls in liquidity range
        @param sdivk Current side token price over strike price
        @param teta Theta coefficient
        @return inRangePayoffPerc The impermanent gain
     */
    function igPayoffInRange(uint256 sdivk, uint256 teta) public pure returns (uint256 inRangePayoffPerc) {
        return (AmountsMath.wrap(1) + sdivk - 2 * FixedPointMathLib.sqrt(sdivk)).wdiv(teta);
    }

    /**
        @notice Computes concentrated liquidity impermanent gain percentage when current price falls out of liquidity range
        @param sdivk Current side token price over strike price
        @param teta Theta coefficient
        @param k Ref. strike
        @param kbound Upper or lower bound of the range
        @return outRangePayoffPerc The impermanent gain
     */
    function igPayoffOutRange(
        uint256 sdivk,
        uint256 teta,
        uint256 k,
        uint256 kbound
    ) public pure returns (uint256 outRangePayoffPerc) {
        uint256 one = AmountsMath.wrap(1);
        uint256 kDivKboundRtd = FixedPointMathLib.sqrt(k.wdiv(kbound));
        uint256 kboundDivKRtd = FixedPointMathLib.sqrt(kbound.wdiv(k));

        bool c2Pos = kDivKboundRtd >= one;
        uint256 c2Abs = sdivk.wmul(c2Pos ? kDivKboundRtd - one : one - kDivKboundRtd);
        uint256 num;
        if (c2Pos) {
            num = one - c2Abs - kboundDivKRtd;
        } else {
            num = one + c2Abs - kboundDivKRtd;
        }
        return num.wdiv(teta);
    }

    /**
        @notice Computes payoff percentage for impermanent gain up / down strategies
        @param s Current side token price
        @param k Ref. strike
        @return igPOBull The percentage payoff for bull strategy
        @return igPOBear The percentage payoff for bear strategy
     */
    function igPayoffPerc(
        uint256 s,
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 teta
    ) public pure returns (uint256 igPOBull, uint256 igPOBear) {
        igPOBull = s <= k ? 0 : s > kb ? igPayoffOutRange(s.wdiv(k), teta, k, kb) : igPayoffInRange(s.wdiv(k), teta);
        igPOBear = s >= k ? 0 : s < ka ? igPayoffOutRange(s.wdiv(k), teta, k, ka) : igPayoffInRange(s.wdiv(k), teta);
    }

    ////// DELTA //////

    /**
        @notice Computes unitary delta hedge quantity for bull/bear options
        @param params The set of DeltaPriceParams to compute deltas
        @return igDBull The unitary integer quantity of side token to hedge an bull position
        @return igDBear The unitary integer quantity of side token to hedge a bear position
     */
    function igDeltas(DeltaPriceParams memory params) public pure returns (int256 igDBull, int256 igDBear) {
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

    ////// PRICING //////

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

    struct PriceParts {
        uint256 p1;
        uint256 p2;
        uint256 p3;
        uint256 p4;
        uint256 p5;
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

    function nTerms(DTerms memory ds) public pure returns (NTerms memory) {
        return NTerms(uint256(Gaussian.cdf(ds.d1)), uint256(Gaussian.cdf(ds.d2)), uint256(Gaussian.cdf(ds.d3)));
    }

    /// @dev σ√τ AND ( r + σ^2 / 2 ) τ
    function d1Parts(uint256 r, uint256 sigma, uint256 tau) public pure returns (uint256 sigmaTaurtd, uint256 q1) {
        q1 = (r + (sigma.wmul(sigma) / 2)).wmul(tau);
        sigmaTaurtd = _sigmaTaurtd(sigma, tau);
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

    /// @dev 2 - √(Ka / K) - √(K / Kb)
    function _teta(uint256 k, uint256 ka, uint256 kb) public pure returns (uint256 teta) {
        return 2e18 - FixedPointMathLib.sqrt(ka.wdiv(k)) - FixedPointMathLib.sqrt(k.wdiv(kb));
    }

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

    /// @dev ln(S / K) / σ√τ
    function _x(uint256 s, uint256 k, uint256 sigmaTaurtd) public pure returns (int256) {
        int256 n = FixedPointMathLib.ln(SignedMath.castInt(s.wdiv(k)));
        return SignedMath.revabs(SignedMath.abs(n).wdiv(sigmaTaurtd), n > 0);
    }
}
