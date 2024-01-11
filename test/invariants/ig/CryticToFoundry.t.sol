// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test() public {
        setTokenPrice(0);
        buyBull(246);
        vm.warp(block.timestamp + 87452);
        rollEpoch();
        sellBull(396205024051372058106855126321379448441821842794);
    }
}
