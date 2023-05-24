// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {FixedPointMathLib} from "../src/lib/FixedPointMathLib.sol";

import {Gaussian} from "@solstat/Gaussian.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {AmountsMath} from "../src/lib/AmountsMath.sol";
import {Finance} from "../src/lib/Finance.sol";
import {WadTime} from "../src/lib/WadTime.sol";

contract FinanceLibTest is Test {
    using AmountsMath for uint256;

    struct DeltaComponents {
        int256 d1;
        int256 d2;
        int256 d3;
        uint256 c1;
        uint256 c2;
        uint256 c3;
        uint256 c4;
        uint256 c5;
        uint256 c6;
        uint256 c7;
        int256 igDUp;
        int256 igDDown;
    }

    struct PriceComponents {
        uint256 pu1;
        uint256 pu2;
        uint256 pu3;
        uint256 pd1;
        uint256 pd2;
        uint256 pd3;
        uint256 igPUp;
        uint256 igPDown;
    }

    struct Payoff {
        uint256 igUp;
        uint256 igDown;
    }

    struct TestCase {
        // inputs
        uint256 v0;
        Finance.DeltaPriceParams params;
        // results
        DeltaComponents delta;
        PriceComponents price;
        Payoff payoff;
    }

    uint256 v0 = 1e24; // 1,000,000 (1M)
    uint256 r = 2e16; // 0.02 (2 %)
    uint256 sigma = 5e17; // 0.5 (50 %)
    mapping(uint256 => TestCase) testCases;
    uint256 testCasesNum = 0;

    /**
        @dev Accepted delta on comparisons (up to 5e-7)
        This is mainly due to limitations of `Gaussian.cdf()` computation error.
     */
    uint256 constant ERR = 5e11;

    function setUp() public {
        // 3000 current price
        testCases[0] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 2e21, 3e21, WadTime.nYears(WadTime.daysFraction(5, 6))),
            DeltaComponents(16985368844e9, 16961477920e9, 16973423382e9, 0e9, 250000e9, 0, 204105e9, 0, 250000e9, 204105e9, 45895077883e9, 0),
            PriceComponents(499977169e9, 750000000e9, 1224629533e9, 0e9, 0e9, 0e9, 25347636771321e9, 0e9),
            Payoff(0, 0)
        );

        // 0.1 current price
        testCases[1] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 2e21, 1e17, WadTime.nYears(WadTime.daysFraction(4, 6))),
            DeltaComponents(-463445429364e9, -463466798056e9, -463456113710e9, 0, 0, 0, 0, 0, 250000e9, 35352675e9, 0, -35102675401250e9),
            PriceComponents(0e0, 0e0, 0e0, 499981735e9, 25000e9, 7070535e9, 0e9, 492936200413168e9),
            Payoff(0, 0)
        );

        // 1500 current price
        testCases[2] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 2e21, 15e20, WadTime.nYears(WadTime.daysFraction(3, 6))),
            DeltaComponents(-15534749771e9, -15553255601e9, -15544002686e9, 0, 0, 0, 0, 0, 250000e9, 288659e9, 0, -38658822933e9),
            PriceComponents(0e9, 0e9, 0e9, 499986302e9, 375000000e9, 865976469e9, 0e9, 9009832757476e9),
            Payoff(0, 0)
        );

        // 2010 current price
        testCases[3] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 2e21, 201e19, WadTime.nYears(WadTime.daysFraction(2, 6))),
            DeltaComponents(338847089e9, 323737142e9, 331292116e9, 6232393e9, 158159e9, 6232393e9, 157049e9, 12464787e9, 250000e9, 249368e9, 1110429038e9, -478368890e9),
            PriceComponents(313460012e9, 317900362e9, 631336800e9, 186530855e9, 184599638e9, 371122318e9, 23574756999e9, 8174700345e9),
            Payoff(0, 0)
        );

        // 1990 current price
        testCases[4] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 2e21, 199e19, WadTime.nYears(WadTime.daysFraction(1, 6))),
            DeltaComponents(-462951288e9, -473635634e9, -468293461e9, 8386143e9, 80425e9, 8386143e9, 80146e9, 16772287e9, 250000e9, 250623e9, 278957332e9, -901590214e9),
            PriceComponents(158938489e9, 160045572e9, 318980893e9, 341056945e9, 337454428e9, 678497185e9, 3166897805e9, 14188041442e9),
            Payoff(0, 0)
        );

        // 2000 current price
        testCases[5] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 2e21, 2e21, WadTime.nYears(WadTime.daysFraction(1, 6))),
            DeltaComponents(6196921e9, -4487425e9, 854748e9, 9334559e9, 125618e9, 9334559e9, 125083e9, 18669117e9, 250000e9, 249995e9, 535156764e9, -530447904e9),
            PriceComponents(249102616e9, 251236099e9, 500331571e9, 250892818e9, 248763901e9, 499649594e9, 7144356430e9, 7124893424e9),
            Payoff(0, 0)
        );

        testCasesNum = 6;
    }

    function testTermsDs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (int256 d1, int256 d2, int256 d3, ) = Finance.ds(testCases[i].params);

            assertApproxEqAbs(testCases[i].delta.d1, d1, ERR);
            assertApproxEqAbs(testCases[i].delta.d2, d2, ERR);
            assertApproxEqAbs(testCases[i].delta.d3, d3, ERR);
        }
    }

    function testTermsCs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (int256 d1, int256 d2, int256 d3, uint256 sigmaTaurtd) = Finance.ds(testCases[i].params);
            uint256 sigmaTaurtdPi2rtd = sigmaTaurtd.wmul(Finance.PI2_RTD);
            Finance.DeltaIGAddends memory cs_ = Finance.cs(testCases[i].params, d1, d2, d3, sigmaTaurtdPi2rtd);

            assertApproxEqAbs(testCases[i].delta.c1, cs_.c1, ERR);
            assertApproxEqAbs(testCases[i].delta.c2, cs_.c2, ERR);
            assertApproxEqAbs(testCases[i].delta.c3, cs_.c3, ERR);
            assertApproxEqAbs(testCases[i].delta.c4, cs_.c4, ERR);
            assertApproxEqAbs(testCases[i].delta.c5, cs_.c5, ERR);
            assertApproxEqAbs(testCases[i].delta.c6, cs_.c6, ERR);
            assertApproxEqAbs(testCases[i].delta.c7, cs_.c7, ERR);
        }
    }

    function testDeltas() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (int256 igDUp, int256 igDDown) = Finance.igDeltas(testCases[i].params);

            igDUp = (int256(testCases[i].v0) * igDUp) / (10 ** 18);
            igDDown = (int256(testCases[i].v0) * igDDown) / (10 ** 18);

            assertApproxEqAbs(testCases[i].delta.igDUp, igDUp, 1e13);
            assertApproxEqAbs(testCases[i].delta.igDDown, igDDown, 1e13);
        }
    }

    function testPs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (uint256 p1_, uint256 p2_, uint256 p3_) = Finance.ps(testCases[i].params);
            (int256 d1_, int256 d2_, int256 d3_, ) = Finance.ds(testCases[i].params);
            uint256 n1 = uint256(Gaussian.cdf(d1_));
            uint256 n2 = uint256(Gaussian.cdf(d2_));
            uint256 n3 = uint256(Gaussian.cdf(d3_));

            {
                (uint256 pu1, uint256 pu2, uint256 pu3) = Finance.pus(p1_, p2_, p3_, n1, n2, n3);
                assertApproxEqAbs(testCases[i].price.pu1, pu1, ERR);
                assertApproxEqAbs(testCases[i].price.pu2, pu2, ERR);
                assertApproxEqAbs(testCases[i].price.pu3, pu3, ERR);
            }

            {
                (uint256 pd1, uint256 pd2, uint256 pd3) = Finance.pds(p1_, p2_, p3_, n1, n2, n3);
                assertApproxEqAbs(testCases[i].price.pd1, pd1, ERR);
                assertApproxEqAbs(testCases[i].price.pd2, pd2, ERR);
                assertApproxEqAbs(testCases[i].price.pd3, pd3, ERR);
            }
        }
    }

    function testPrices() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (uint256 igPUp, uint256 igPDown) = Finance.igPrices(testCases[i].params);
            assertApproxEqAbs(testCases[i].price.igPUp, testCases[i].v0.wmul(igPUp), 15e15); // TODO actually e13 is more than needed, but 2000-2000 test is less accurate
            assertApproxEqAbs(testCases[i].price.igPDown, testCases[i].v0.wmul(igPDown), 15e15); // TODO actually e13 is more than needed, but 2000-2000 test is less accurate
        }
    }

    function testPayoff() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (uint256 poUp, uint256 poDown) = Finance.igPayoffPerc(testCases[i].params.s, testCases[i].params.k);
            assertApproxEqAbs(testCases[i].payoff.igUp, poUp, ERR);
            assertApproxEqAbs(testCases[i].payoff.igDown, poDown, ERR);
        }
    }
}
