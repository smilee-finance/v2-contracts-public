// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
  function setUp() public {
    setup();
  }

  function testIncrementRandom() public {
    increment(115792089237316195423570985008687907853269984665640564039457584007913129639935);
  }
}