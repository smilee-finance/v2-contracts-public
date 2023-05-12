// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {WadTime} from "../src/lib/WadTime.sol";

contract WadTimeLibTest is Test {
    function setUp() public {}

    /// @dev Accepted delta on comparisons (up to 1e-16)
    uint256 constant ERR = 100;

    function testYearsConversion() public {
        // 5/6 of a day = 0.00228 years
        assertApproxEqAbs(2283105022831050, WadTime.nYears(WadTime.daysFraction(5, 6)), ERR);
        // 4/6 of a day = 0.00182 years
        assertApproxEqAbs(1826484018264840, WadTime.nYears(WadTime.daysFraction(4, 6)), ERR);
        // 1/2 of a day = 0.00136 years
        assertApproxEqAbs(1369863013698630, WadTime.nYears(WadTime.daysFraction(1, 2)), ERR);
        // 1/3 of a day = 0.00091 years
        assertApproxEqAbs(913242009132420, WadTime.nYears(WadTime.daysFraction(1, 3)), ERR);
        // 1/6 of a day = 0.00045 years
        assertApproxEqAbs(456621004566210, WadTime.nYears(WadTime.daysFraction(1, 6)), ERR);
    }
}
