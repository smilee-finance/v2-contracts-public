// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";

/**
 * medusa fuzz --no-color
 * echidna . --contract CryticTester --config config.yaml
 */
abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    function setup() internal virtual override {
      deploy();
    }

    function increment(uint256 value) public {
      // bound input
      value = between(value, 0, type(uint256).max / 2);

      __before();

      counter.increment(value);

      __after();
      // assertions

      lt(_before.value, _after.value, COUNTER_01);
    }
}