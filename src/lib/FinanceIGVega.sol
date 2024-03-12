// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {SD59x18, sd, convert as convertint} from "@prb/math/SD59x18.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {Gaussian} from "@solstat/Gaussian.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";
import {FinanceIGPrice} from "./FinanceIGPrice.sol";

/// @title Implementation of core financial computations for vega functions
library FinanceIGVega {
    error PositiveSumLtZero();

    struct Params {
        FinanceIGPrice.Parameters inp;
        FinanceIGPrice.DTerms ds;
        FinanceIGPrice.DTerms das;
        FinanceIGPrice.DTerms dbs;
        FinanceIGPrice.NTerms cdfs;
        FinanceIGPrice.NTerms cdfas;
        FinanceIGPrice.NTerms cdfbs;
        FinanceIGPrice.NTerms pdfs;
        FinanceIGPrice.NTerms pdfas;
        FinanceIGPrice.NTerms pdfbs;
    }

    function igVega(
        FinanceIGPrice.Parameters calldata inp,
        uint256 v0
    ) external view returns (uint256 vBull, uint256 vBear) {
        {
            (
                FinanceIGPrice.DTerms memory ds,
                FinanceIGPrice.DTerms memory das,
                FinanceIGPrice.DTerms memory dbs
            ) = FinanceIGPrice.dTerms(inp);

            FinanceIGPrice.NTerms memory cdfs = FinanceIGPrice.nTerms(ds);
            FinanceIGPrice.NTerms memory cdfas = FinanceIGPrice.nTerms(das);
            FinanceIGPrice.NTerms memory cdfbs = FinanceIGPrice.nTerms(dbs);

            FinanceIGPrice.NTerms memory pdfs = _pdfTerms(ds);
            FinanceIGPrice.NTerms memory pdfas = _pdfTerms(das);
            FinanceIGPrice.NTerms memory pdfbs = _pdfTerms(dbs);

            Params memory p = Params(inp, ds, das, dbs, cdfs, cdfas, cdfbs, pdfs, pdfas, pdfbs);

            uint256 ert = FinanceIGPrice.ert(p.inp.r, p.inp.tau);

            int256 v1_ = v1(ert, p.ds.d1, p.pdfs.n2);

            int256 v2_ = v2(p.inp.s, p.inp.k, p.ds.d2, p.pdfs.n1);

            vBull = bullVega(p, ert, v1_, v2_);
            vBear = bearVega(p, ert, v1_, v2_);
        }
        {
        }
        vBull = (v0 * vBull) / inp.theta / 100;
        vBear = (v0 * vBear) / inp.theta / 100;
    }

    function bullVega(Params memory p, uint256 ert, int256 v1_, int256 v2_) public view returns (uint256) {
        uint256 er2sig8 = FinanceIGPrice.er2sig8(p.inp.r, p.inp.sigma, p.inp.tau);
        uint256 sdivkRtd = ud(p.inp.s).div(ud(p.inp.k)).sqrt().unwrap();

        int256 v3_ = vBull3(sdivkRtd, p.inp.sigma, p.inp.tau, er2sig8, p.cdfs.n3, p.cdfbs.n3);
        int256 v4_ = vBull4(sdivkRtd, er2sig8, p.ds.d3, p.dbs.d3, p.pdfs.n3, p.pdfbs.n3);
        int256 v5_ = v5(p.inp.s, p.inp.k, p.inp.kb, p.dbs.d2, p.pdfbs.n1);
        int256 v6_ = v6(p.inp.k, p.inp.kb, ert, p.dbs.d1, p.pdfbs.n2);

        int256 sum = (-v1_ - v2_ - v3_ - v4_ + v5_ + v6_);
        if (sum < 0) {
            // NOTE: rounding errors may yields a slightly negative number
            if (sum < -1e9) {
                revert PositiveSumLtZero();
            }
            return 0;
        }

        return (SignedMath.abs(sum) * 1e18) / p.inp.sigma;
    }

    function bearVega(Params memory p, uint256 ert, int256 v1_, int256 v2_) public view returns (uint256) {
        uint256 er2sig8 = FinanceIGPrice.er2sig8(p.inp.r, p.inp.sigma, p.inp.tau);
        uint256 sdivkRtd = ud(p.inp.s).div(ud(p.inp.k)).sqrt().unwrap();

        int256 v3_ = vBear3(sdivkRtd, p.inp.sigma, p.inp.tau, er2sig8, p.cdfs.n3, p.cdfas.n3);
        int256 v4_ = vBear4(sdivkRtd, er2sig8, p.ds.d3, p.das.d3, p.pdfs.n3, p.pdfas.n3);
        int256 v5_ = v5(p.inp.s, p.inp.k, p.inp.ka, p.das.d2, p.pdfas.n1);
        int256 v6_ = v6(p.inp.k, p.inp.ka, ert, p.das.d1, p.pdfas.n2);

        int256 sum = (v1_ + v2_ - v3_ - v4_ - v5_ - v6_);
        if (sum < 0) {
            // NOTE: rounding errors may yields a slightly negative number
            if (sum < -1e9) {
                revert PositiveSumLtZero();
            }
            return 0;
        }

        return (SignedMath.abs(sum) * 1e18) / p.inp.sigma;
    }

    /// @dev e^-(r τ) * N(d2) * d1
    function v1(uint256 ert, int256 d1, uint256 n2) public pure returns (int256) {
        return sd(int256(ert)).mul(sd(int256(n2))).mul(sd(d1)).unwrap();
    }

    /// @dev S / K * N(d1) * d2
    function v2(uint256 s, uint256 k, int256 d2, uint256 n1) public pure returns (int256) {
        return sd(int256((s * n1) / k)).mul(sd(d2)).unwrap();
    }

    /// @dev sigma^2 * tau * √(S / K) * er2sig8 * ndiff / 2
    function v3(
        uint256 sdivkRtd,
        uint256 sigma,
        uint256 tau,
        uint256 er2sig8,
        SD59x18 ndiff
    ) public pure returns (int256) {
        UD60x18 e = ud(sigma).mul(ud(sigma)).mul(ud(tau)).mul(ud(sdivkRtd)).mul(ud(er2sig8));
        return e.intoSD59x18().mul(ndiff).unwrap() / 2;
    }

    /// @dev sigma^2 * tau * √(S / K) * er2sig8 * ( N(d3) - N(d3a) ) / 2
    function vBear3(
        uint256 sdivkRtd,
        uint256 sigma,
        uint256 tau,
        uint256 er2sig8,
        uint256 n3,
        uint256 n3a
    ) public pure returns (int256) {
        SD59x18 ndiff = sd(int256(n3)).sub(sd(int256(n3a)));
        return v3(sdivkRtd, sigma, tau, er2sig8, ndiff);
    }

    /// @dev sigma^2 * tau * √(S / K) * er2sig8 * ( N(d3b) - N(d3) ) / 2
    function vBull3(
        uint256 sdivkRtd,
        uint256 sigma,
        uint256 tau,
        uint256 er2sig8,
        uint256 n3,
        uint256 n3b
    ) public pure returns (int256) {
        SD59x18 ndiff = sd(int256(n3b)).sub(sd(int256(n3)));
        return v3(sdivkRtd, sigma, tau, er2sig8, ndiff);
    }

    /// @dev 2 √(S / K) * er2sig8 * ndiff
    function v4(uint256 sdivkRtd, uint256 er2sig8, SD59x18 ndiff) public pure returns (int256) {
        SD59x18 e = ud(2 * sdivkRtd).mul(ud(er2sig8)).intoSD59x18();
        return e.mul(ndiff).unwrap();
    }

    /// @dev 2 √(S / K) * er2sig8 * ( d3 * N(d3) - d3a * N(d3a) )
    function vBear4(
        uint256 sdivkRtd,
        uint256 er2sig8,
        int256 d3,
        int256 d3a,
        uint256 n3,
        uint256 n3a
    ) public pure returns (int256) {
        // d3 * n3 - d3a * n3a
        SD59x18 ndiff = sd(d3).mul(sd(int256(n3))).sub(sd(d3a).mul(sd(int256(n3a))));

        return v4(sdivkRtd, er2sig8, ndiff);
    }

    /// @dev 2 √(S / K) * er2sig8 * ( d3b * N(d3b) - d3 * N(d3) )
    function vBull4(
        uint256 sdivkRtd,
        uint256 er2sig8,
        int256 d3,
        int256 d3b,
        uint256 n3,
        uint256 n3b
    ) public pure returns (int256) {
        // d3b * n3b - d3 * n3
        SD59x18 ndiff = sd(d3b).mul(sd(int256(n3b))).sub(sd(d3).mul(sd(int256(n3))));

        return v4(sdivkRtd, er2sig8, ndiff);
    }

    /// @dev  S * N(<d1a, d1b>) / √(K * <Ka, Kb>) * <d2a, d2b>
    /// @dev use A edge for bear, B edge for bull
    function v5(uint256 s, uint256 k, uint256 kedge, int256 d2edge, uint256 n1edge) public pure returns (int256) {
        uint256 kkedgertd = FinanceIGPrice.kkrtd(k, kedge);
        uint256 e = ((s * n1edge) / kkedgertd);

        return sd(int256(e)).mul(sd(d2edge)).unwrap();
    }

    /// @dev e^-(r τ) * √(<Ka, Kb> / K) * N(<d2a, d2b>) * <d1a, d1b>
    /// @dev use A edge for bear, B edge for bull
    function v6(uint256 k, uint256 kedge, uint256 ert, int256 d1edge, uint256 n2edge) public pure returns (int256) {
        SD59x18 kedgedivkrtd = sd(int256(FinanceIGPrice.kdivkrtd(k, kedge)));
        SD59x18 sdErt = sd(int256(ert));

        return sdErt.mul(kedgedivkrtd).mul(sd(int256(n2edge))).mul(sd(d1edge)).unwrap();
    }

    function _pdfTerms(FinanceIGPrice.DTerms memory ds) internal pure returns (FinanceIGPrice.NTerms memory) {
        return
            FinanceIGPrice.NTerms(
                uint256(Gaussian.pdf(ds.d1)),
                uint256(Gaussian.pdf(ds.d2)),
                uint256(Gaussian.pdf(ds.d3))
            );
    }
}
