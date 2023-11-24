// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";

contract EpochFrequencyTest is Test {
    bytes4 constant MissingNextEpoch = bytes4(keccak256("MissingNextEpoch()"));

    uint256 constant dailyPeriod = EpochFrequency.DAILY;
    uint256 constant weeklyPeriod = EpochFrequency.WEEKLY;

    uint256 referenceTime;

    constructor() {
        referenceTime = 1698393600; // 1682064000; // fri20230421
    }

    function setUp() public {}

    function testDaily() public {
        uint256 sat20230422 = referenceTime + 1 days; // 1682150400; // EpochFrequency.REF + 1 day
        uint256 sun20230423 = referenceTime + 2 days; // 1682236800; // EpochFrequency.REF + 2 day

        assertEq(referenceTime, EpochFrequency.nextExpiry(referenceTime - 1, dailyPeriod));
        assertEq(sat20230422, EpochFrequency.nextExpiry(referenceTime, dailyPeriod));
        assertEq(sat20230422, EpochFrequency.nextExpiry(referenceTime + 1, dailyPeriod));
        assertEq(sun20230423, EpochFrequency.nextExpiry(sat20230422, dailyPeriod));
    }

    function testWeekly() public {
        uint256 fri20230428 = referenceTime + 7 days; // 1682668800; // EpochFrequency.REF + 1 week
        uint256 fri20230505 = referenceTime + 14 days; // 1683273600; // EpochFrequency.REF + 2 week

        assertEq(referenceTime, EpochFrequency.nextExpiry(referenceTime - 1, weeklyPeriod));
        assertEq(fri20230428, EpochFrequency.nextExpiry(referenceTime, weeklyPeriod));
        assertEq(fri20230428, EpochFrequency.nextExpiry(referenceTime + 1, weeklyPeriod));
        assertEq(fri20230505, EpochFrequency.nextExpiry(fri20230428, weeklyPeriod));
    }

}
