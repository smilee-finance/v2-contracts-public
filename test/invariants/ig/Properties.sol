// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";

abstract contract Properties is Setup {
  string constant internal COUNTER_01 = "COUNTER_01: Counter always increases";
}