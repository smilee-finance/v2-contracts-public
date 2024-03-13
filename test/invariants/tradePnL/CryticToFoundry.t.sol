// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {console} from "forge-std/console.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {

    /**
        IMPORTANT!
        Before run this test make sure to select the right scenario
        `cp test/invariants/utils/scenarios/Parameters_*.sol test/invariants/utils/scenarios/Parameters.sol`
     */

    function setUp() public {
        setup();
    }
}
