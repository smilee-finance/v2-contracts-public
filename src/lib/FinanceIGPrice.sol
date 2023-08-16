// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Gaussian} from "@solstat/Gaussian.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {SignedMath} from "./SignedMath.sol";

/// @title Implementation of core financial computations for Smilee protocol
library FinanceIGPrice {
    using AmountsMath for uint256;

    error PriceZero();
    error OutOfRange(string varname, uint256 value);

    /// @notice A wrapper for the input parameters of delta and price functions
    struct Parameters {
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
    }

    /**
        @notice Computes unitary price for up/down options
        @param params The set of Parameters to compute the option price
        @return igPBull The unitary price for an up position
        @return igPBear The unitary price for a down position
     */
    function igPrices(Parameters calldata params) external pure returns (uint256 igPBull, uint256 igPBear) {
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
        @param params The set of Parameters to compute the option price
        @return ds ds terms computed with (price / K)
        @return das ds terms computed with (price / Ka)
        @return dbs ds terms computed with (price / Kb)
     */
    function dTerms(
        Parameters calldata params
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
        Parameters memory params,
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
        Parameters memory params,
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

    /// @dev (r / 2 + σ^2 / 8)τ
    function _boexp(uint256 r, uint256 sigma, uint256 tau) public pure returns (uint256) {
        return tau.wmul(r / 2 + SignedMath.pow2(int256(sigma)) / 8);
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

    /// @dev σ√τ
    function _sigmaTaurtd(uint256 sigma, uint256 tau) public pure returns (uint256) {
        return sigma.wmul(FixedPointMathLib.sqrt(tau));
    }

    //////  OTHER //////

    struct LiquidityRangeParams {
        uint256 k;
        uint256 sigma;
        uint256 sigmaMultiplier;
        uint256 yearsOfMaturity;
    }

    // @param k The reference strike.
    // @param sigma The token's pair volatility; symbolic values in [0, 1] ?
    // @param sigmaMultiplier A multiplier for the token's pair volatility.
    // @param yearsOfMaturity Number of years for the maturity.
    /**
        @notice Computes the range (kA, kB)
        @param params The parameters.
        @return kA The lower limit of the liquidity range.
        @return kB The upper limit of the liquidity range.
        @dev All the values are expressed in Wad.
     */
    function liquidityRange(LiquidityRangeParams calldata params) public pure returns (uint256 kA, uint256 kB) {
        uint256 mSigmaT = params.sigma.wmul(params.sigmaMultiplier).wmul(FixedPointMathLib.sqrt(params.yearsOfMaturity));

        kA = params.k.wmul(FixedPointMathLib.exp(int256(SignedMath.neg(mSigmaT))));
        kB = params.k.wmul(FixedPointMathLib.exp(int256(mSigmaT)));
    }

    struct TradeVolatilityParams {
        // The baseline volatility at epoch start
        uint256 sigma0;
        // A multiplier for the utilization rate; must be greater or equal to one
        uint256 utilizationRateFactor;
        // A time decay factor
        uint256 timeDecay;
        // The utilization rate of the vault deposits
        uint256 utilizationRate;
        // The epoch duration (maturity timestamp - last maturity timestamp)
        uint256 duration;
        // The epoch start timestamp
        uint256 initialTime;
    }

    /**
        @notice Computes the trade volatility
        @param params The parameters
        @return sigma_hat the trade volatility.
        @dev All the non-timestamp values are expressed in Wad.
     */
    function tradeVolatility(TradeVolatilityParams calldata params) public view returns (uint256 sigma_hat) {
        uint256 baselineVolatilityFactor = AmountsMath.wrap(1) + uint256(SignedMath.pow3(int256(params.utilizationRate))).wmul(params.utilizationRateFactor.sub(AmountsMath.wrap(1)));
        uint256 timeFactor = (AmountsMath.wrap(params.duration) - params.timeDecay.wmul(AmountsMath.wrap(block.timestamp - params.initialTime))).wdiv(AmountsMath.wrap(params.duration));

        return params.sigma0.wmul(baselineVolatilityFactor).wmul(timeFactor);
    }

}
