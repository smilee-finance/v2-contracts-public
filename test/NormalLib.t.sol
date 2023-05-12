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

contract NormalLibTest is Test {
    function setUp() public {}

    function testCdfGas() public pure {
        Normal.cdf(341);
        Normal.cdf(342);
        Normal.cdf(345);
        Normal.cdf(385);
        Normal.cdf(399);
        Normal.cdf(400);
        Normal.cdf(401);
        Normal.cdf(500);
        Normal.cdf(-341);
        Normal.cdf(-342);
        Normal.cdf(-345);
        Normal.cdf(-385);
        Normal.cdf(-399);
        Normal.cdf(-400);
        Normal.cdf(-401);
        Normal.cdf(-500);
        Normal.cdf(11);
        Normal.cdf(5);
        Normal.cdf(1);
        Normal.cdf(0);
        Normal.cdf(-1);
        Normal.cdf(-5);
        Normal.cdf(-11);
    }

    function testCdf() public {
        assertEq(99968e13, Normal.cdf(341));
        assertEq(99969e13, Normal.cdf(342));
        assertEq(99972e13, Normal.cdf(345));
        assertEq(99994e13, Normal.cdf(385));
        assertEq(99997e13, Normal.cdf(399));
        assertEq(1e18, Normal.cdf(400));
        assertEq(1e18, Normal.cdf(401));
        assertEq(1e18, Normal.cdf(500));

        assertEq(32e13, Normal.cdf(-341));
        assertEq(31e13, Normal.cdf(-342));
        assertEq(28e13, Normal.cdf(-345));
        assertEq(6e13, Normal.cdf(-385));
        assertEq(3e13, Normal.cdf(-399));
        assertEq(0, Normal.cdf(-400));
        assertEq(0, Normal.cdf(-401));
        assertEq(0, Normal.cdf(-500));

        assertEq(54380e13, Normal.cdf(11));
        assertEq(51994e13, Normal.cdf(5));
        assertEq(50399e13, Normal.cdf(1));
        assertEq(5e17, Normal.cdf(0));
        assertEq(49601e13, Normal.cdf(-1));
        assertEq(48006e13, Normal.cdf(-5));
        assertEq(45620e13, Normal.cdf(-11));
    }

    function testWcdf() public {
        assertEq(99968e13, Normal.wcdf(3_411250000123000123));
        assertEq(99969e13, Normal.wcdf(3_421250000123000123));
        assertEq(99972e13, Normal.wcdf(3_451250000123000123));
        assertEq(99994e13, Normal.wcdf(3_851250000123000123));
        assertEq(99997e13, Normal.wcdf(3_991250000123000123));
        assertEq(1e18, Normal.wcdf(4_001250000123000123));
        assertEq(1e18, Normal.wcdf(4_011250000123000123));
        assertEq(1e18, Normal.wcdf(5_001250000123000123));

        assertEq(32e13, Normal.wcdf(-3_411250000123000123));
        assertEq(31e13, Normal.wcdf(-3_421250000123000123));
        assertEq(28e13, Normal.wcdf(-3_451250000123000123));
        assertEq(6e13, Normal.wcdf(-3_851250000123000123));
        assertEq(3e13, Normal.wcdf(-3_991250000123000123));
        assertEq(0, Normal.wcdf(-4_001250000123000123));
        assertEq(0, Normal.wcdf(-4_011250000123000123));
        assertEq(0, Normal.wcdf(-5_001250000123000123));

        assertEq(54380e13, Normal.wcdf(111250000123000123));
        assertEq(51994e13, Normal.wcdf(51250000123000123));
        assertEq(50399e13, Normal.wcdf(11250000123000123));
        assertEq(5e17, Normal.wcdf(1250000123000123));
        assertEq(49601e13, Normal.wcdf(-11250000123000123));
        assertEq(48006e13, Normal.wcdf(-51250000123000123));
        assertEq(45620e13, Normal.wcdf(-111250000123000123));
    }
}
