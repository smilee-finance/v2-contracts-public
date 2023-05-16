// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {FixedPointMathLib} from "../src/lib/FixedPointMathLib.sol";

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {AmountsMath} from "../src/lib/AmountsMath.sol";
import {Finance} from "../src/lib/Finance.sol";
import {WadTime} from "../src/lib/WadTime.sol";
import {Normal} from "../src/lib/Normal.sol";

contract FinanceLibTest is Test {
    using AmountsMath for uint256;
    uint256 V0 = 1e24; // 1,000,000 (1M)
    uint256 r = 2e16; // 0.02 or 2%
    uint256 sigma = 5e17; // 0.5 or 50%

    struct TestCase {
        // inputs
        uint256 V0;
        uint256 r;
        uint256 sigma;
        uint256 K;
        uint256 S;
        uint256 tau;
        // results
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

    mapping(uint256 => TestCase) testCases;
    uint256 testCasesNum = 0;

    /// @dev Accepted delta on comparisons (up to 1e-9)
    uint256 constant ERR = 1e9;

    function setUp() public {
        testCases[0] = TestCase(
            V0,
            r,
            sigma,
            2e21, // 2000 strike price
            3e21, // 3000 current price
            WadTime.nYears(WadTime.daysFraction(5, 6)), // 5/6 of a day
            16985368844e9, // 16.98
            16961477920e9, // 16.96
            16973423382e9, // 16.97
            0, // 0.000000000
            250000e9, // 0.000250000
            0, // 0.000000000
            204105e9, // 0.000204105
            0, // 0.000000000
            250000e9, // 0.000250000
            204105e9, // 0.000204105
            45895077883e9,
            0
        );

        testCases[1] = TestCase(
            V0,
            r,
            sigma,
            2e21, // 2000 strike price
            1e17, // 0.1 current price
            WadTime.nYears(WadTime.daysFraction(4, 6)), // 2/3 of a day
            -463445429364e9, // -463.44
            -463466798056e9, // -463.46
            -463456113710e9, // -463.45
            0, // 0.000000000
            0, // 0.000000000
            0, // 0.000000000
            0, // 0.000000000
            0, // 0.000000000
            250000e9, // 0.000250000
            35352675e9, // 0.035352675
            0,
            -35102675401250e9
        );

        testCases[2] = TestCase(
            V0,
            r,
            sigma,
            2e21, // 2000 strike price
            15e20, // 1500 current price
            WadTime.nYears(WadTime.daysFraction(3, 6)), // half of a day
            -15534749771e9, // -15.53
            -15553255601e9, // -15.55
            -15544002686e9, // -15.54
            0, // 0.000000000
            0, // 0.000000000
            0, // 0.000000000
            0, // 0.000000000
            0, // 0.000000000
            250000e9, // 0.000250000
            288659e9, // 0.000288659
            0,
            -38658822933e9
        );

        testCases[3] = TestCase(
            V0,
            r,
            sigma,
            2e21, // 2000 strike price
            201e19, // 2010 current price
            WadTime.nYears(WadTime.daysFraction(2, 6)), // 1/3 of a day
            338847089e9, // 0.338847089,
            323737142e9, // 0.323737142,
            331292116e9, // 0.331292116,
            6232393e9, // 0.006232393,
            158159e9, // 0.000158159,
            6232393e9, // 0.006232393,
            157049e9, // 0.000157049,
            12464787e9, // 0.012464787,
            250000e9, // 0.000250000,
            249368e9, // 0.000249368,
            1110429038e9, // 1.110429038,
            -478368890e9 // -0.478368890
        );

        testCases[4] = TestCase(
            V0,
            r,
            sigma,
            2e21, // 2000 strike price
            199e19, // 1990 current price
            WadTime.nYears(WadTime.daysFraction(1, 6)), // 1/3 of a day
            -462951288e9, // -0.462951288
            -473635634e9, // -0.473635634
            -468293461e9, // -0.468293461
            8386143e9, // 0.008386143
            80425e9, // 0.000080425
            8386143e9, // 0.008386143
            80146e9, // 0.000080146
            16772287e9, // 0.016772287
            250000e9, // 0.000250000
            250623e9, // 0.000250623
            278957332e9, // 0.278957332
            -901590214e9 // -0.901590214
        );

        testCases[5] = TestCase(
            V0,
            r,
            sigma,
            2e21, // 2000 strike price
            2e21, // 2000 current price
            WadTime.nYears(WadTime.daysFraction(1, 100)), // 1/100 of a day
            0e9, // 0.000000000
            0e9, // 0.000000000
            0e9, // 0.000000000
            38108887e9, // 0.038108887
            125000e9, // 0.000125000
            38108908e9, // 0.038108908
            125000e9, // 0.000125000
            76217730e9, // 0.076217730
            250000e9, // 0.000250000
            250000e9, // 0.000250000
            65396203e9, // 0.065396203
            -65113669e9 // -0.065113669
        );

        testCasesNum = 6;
    }

    function testTermsDs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (int256 d1, int256 d2, int256 d3, ) = Finance.ds(
                Finance.DeltaIGParams(
                    testCases[i].r,
                    testCases[i].sigma,
                    testCases[i].K,
                    testCases[i].S,
                    testCases[i].tau
                )
            );

            assertApproxEqAbs(testCases[i].d1, d1, ERR);
            assertApproxEqAbs(testCases[i].d2, d2, ERR);
            assertApproxEqAbs(testCases[i].d3, d3, ERR);
        }
    }

    function testTermsCs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            Finance.DeltaIGParams memory params = Finance.DeltaIGParams(
                testCases[i].r,
                testCases[i].sigma,
                testCases[i].K,
                testCases[i].S,
                testCases[i].tau
            );

            (int256 d1, int256 d2, int256 d3, uint256 sigmaTaurtd) = Finance.ds(params);
            uint256 sigmaTaurtdPi2rtd = sigmaTaurtd.wmul(Finance.PI2_RTD);
            Finance.DeltaIGComponents memory cs_ = Finance.cs(params, d1, d2, d3, sigmaTaurtdPi2rtd);

            assertApproxEqAbs(testCases[i].c1, cs_.c1, ERR);
            assertApproxEqAbs(testCases[i].c2, cs_.c2, ERR);
            assertApproxEqAbs(testCases[i].c3, cs_.c3, ERR);
            assertApproxEqAbs(testCases[i].c4, cs_.c4, ERR);
            assertApproxEqAbs(testCases[i].c5, cs_.c5, ERR);
            assertApproxEqAbs(testCases[i].c6, cs_.c6, ERR);
            assertApproxEqAbs(testCases[i].c7, cs_.c7, ERR);
        }
    }

    function testDeltas() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            Finance.DeltaIGParams memory params = Finance.DeltaIGParams(
                testCases[i].r,
                testCases[i].sigma,
                testCases[i].K,
                testCases[i].S,
                testCases[i].tau
            );

            (int256 igDUp, int256 igDDown) = Finance.igDeltas(params);

            igDUp = (int256(testCases[i].V0) * igDUp) / (10 ** 18);
            igDDown = (int256(testCases[i].V0) * igDDown) / (10 ** 18);

            assertApproxEqAbs(testCases[i].igDUp, igDUp, ERR);
            assertApproxEqAbs(testCases[i].igDDown, igDDown, ERR);
        }
    }
}
