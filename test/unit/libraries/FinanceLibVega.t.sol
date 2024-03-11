// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {FinanceIGPrice} from "@project/lib/FinanceIGPrice.sol";
import {FinanceIGVega} from "@project/lib/FinanceIGVega.sol";
import {ud} from "@prb/math/UD60x18.sol";
import {SignedMath} from "@project/lib/SignedMath.sol";

contract FinanceLibVegaTest is Test {
    struct Inputs {
        uint256 r;
        uint256 sigma;
        uint256 k;
        uint256 s;
        uint256 tau;
        uint256 ka;
        uint256 kb;
        uint256 theta;
        uint256 v0;
    }

    struct Outputs {
        uint256 vBear;
        uint256 vBull;
        uint256 vBear1; // abs value
        uint256 vBear2; // abs value
        uint256 vBear3; // abs value
        uint256 vBear4; // abs value
        uint256 vBear5; // abs value
        uint256 vBear6; // abs value
        uint256 vBull1; // abs value
        uint256 vBull2; // abs value
        uint256 vBull3; // abs value
        uint256 vBull4; // abs value
        uint256 vBull5; // abs value
        uint256 vBull6; // abs value
    }

    struct Scenario {
        Inputs inp;
        Outputs outp;
    }

    Scenario[] private _scenarios;
    uint256 private _ns = 0;

    uint256 constant ERR = 1e12;

    constructor() {}

    // TBD: Move all in the constructor?
    function setUp() public {
        _init();
    }

    function _init() internal {
        _scenarios.push(
            Scenario(
                Inputs(
                    500000000000000000, // r
                    500000000000000000, // sigma
                    1000000000000000000000, // K
                    1000000000000000000000, // S
                    100000000000000000, // tau
                    622294609898280395000, // KA
                    1606955908172591950000, // KB
                    422286959047013009, // theta
                    1000000000000000000000000 // V0
                ),
                Outputs(
                    216112493543719296000,
                    357125893347404548000,
                    291689514822194367,
                    175013708893316618,
                    9126148771064514,
                    445648378066529143,
                    10276455186213952,
                    10778390462767958,
                    291689514822194367,
                    175013708893316618,
                    15080960749862161,
                    580326997401225405,
                    58485417091813309,
                    55138356593900936
                )
            )
        );

        _ns = 1;
    }

    function checkInt(uint256 e1, int256 e2) public {
        assertApproxEqAbs(e1, SignedMath.abs(e2), ERR);
    }

    function test() public {
        for (uint i = 0; i < _ns; i++) {
            Scenario memory s = _scenarios[i];
            FinanceIGVega.Params memory p;

            {
                FinanceIGPrice.Parameters memory inputParams = FinanceIGPrice.Parameters(s.inp.r, s.inp.sigma, s.inp.k, s.inp.s, s.inp.tau, s.inp.ka, s.inp.kb, s.inp.theta);
                (FinanceIGPrice.DTerms memory ds, FinanceIGPrice.DTerms memory das, FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(inputParams);
                FinanceIGPrice.NTerms memory cdfs = FinanceIGPrice.nTerms(ds);
                FinanceIGPrice.NTerms memory cdfas = FinanceIGPrice.nTerms(das);
                FinanceIGPrice.NTerms memory cdfbs = FinanceIGPrice.nTerms(dbs);
                FinanceIGPrice.NTerms memory pdfs = FinanceIGVega._pdfTerms(ds);
                FinanceIGPrice.NTerms memory pdfas = FinanceIGVega._pdfTerms(das);
                FinanceIGPrice.NTerms memory pdfbs = FinanceIGVega._pdfTerms(dbs);

                p = FinanceIGVega.Params(inputParams, ds, das, dbs, cdfs, cdfas, cdfbs, pdfs, pdfas, pdfbs);
            }

            {
                // BULL
                uint256 ert = FinanceIGPrice.ert(p.inp.r, p.inp.tau);
                uint256 er2sig8 = FinanceIGPrice.er2sig8(p.inp.r, p.inp.sigma, p.inp.tau);
                uint256 sdivkRtd = ud(p.inp.s).div(ud(p.inp.k)).sqrt().unwrap();

                checkInt((s.outp.vBull1 * s.inp.sigma) / 1e18, FinanceIGVega.v1(ert, p.ds.d1, p.pdfs.n2));
                checkInt((s.outp.vBull2 * s.inp.sigma) / 1e18, FinanceIGVega.v2(p.inp.s, p.inp.k, p.ds.d2, p.pdfs.n1));
                checkInt((s.outp.vBull3 * s.inp.sigma) / 1e18, FinanceIGVega.vBull3(sdivkRtd, p.inp.sigma, p.inp.tau, er2sig8, p.cdfs.n3, p.cdfbs.n3));
                checkInt((s.outp.vBull4 * s.inp.sigma) / 1e18, FinanceIGVega.vBull4(sdivkRtd, er2sig8, p.ds.d3, p.dbs.d3, p.pdfs.n3, p.pdfbs.n3));
                checkInt((s.outp.vBull5 * s.inp.sigma) / 1e18, FinanceIGVega.v5(p.inp.s, p.inp.k, p.inp.kb, p.dbs.d2, p.pdfbs.n1));
                checkInt((s.outp.vBull6 * s.inp.sigma) / 1e18, FinanceIGVega.v6(p.inp.k, p.inp.kb, ert, p.dbs.d1, p.pdfbs.n2));
            }

            {
                // BEAR
                uint256 ert = FinanceIGPrice.ert(p.inp.r, p.inp.tau);
                uint256 er2sig8 = FinanceIGPrice.er2sig8(p.inp.r, p.inp.sigma, p.inp.tau);
                uint256 sdivkRtd = ud(p.inp.s).div(ud(p.inp.k)).sqrt().unwrap();

                checkInt((s.outp.vBear3 * s.inp.sigma) / 1e18, FinanceIGVega.vBear3(sdivkRtd, p.inp.sigma, p.inp.tau, er2sig8, p.cdfs.n3, p.cdfas.n3));
                checkInt((s.outp.vBear4 * s.inp.sigma) / 1e18, FinanceIGVega.vBear4(sdivkRtd, er2sig8, p.ds.d3, p.das.d3, p.pdfs.n3, p.pdfas.n3));
                checkInt((s.outp.vBear5 * s.inp.sigma) / 1e18, FinanceIGVega.v5(p.inp.s, p.inp.k, p.inp.ka, p.das.d2, p.pdfas.n1));
                checkInt((s.outp.vBear6 * s.inp.sigma) / 1e18, FinanceIGVega.v6(p.inp.k, p.inp.ka, ert, p.das.d1, p.pdfas.n2));
            }

            {
                (uint256 vBull, uint256 vBear) = FinanceIGVega.igVega(p.inp, s.inp.v0);
                assertApproxEqAbs(s.outp.vBull, vBull, 6 * ERR);
                assertApproxEqAbs(s.outp.vBear, vBear, 6 * ERR);
            }
        }
    }
}
