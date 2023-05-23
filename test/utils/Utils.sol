// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";

library Utils {

    // TODO - avoid additionalSecond parameter (skip one second in setup())
    function skipDay(bool additionalSecond, Vm vm) external {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        vm.warp(block.timestamp + 1 days + secondToAdd);
    }

    /**
     * Function used to skip coverage on this file
     */
    function testCoverageSkip() private view {}
}
