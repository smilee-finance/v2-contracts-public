// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
  function setUp() public {
    setup();
  }

  function test() public {
    setTokenPrice(68301153269795610821965261262755870544957354884657);
    vm.warp(94422);
    rollEpoch();
    buyBear(address(0xdeadbeef),330462567717733478051626998396089509439403038603993323892413769306807);
    buyBull(address(0xdeadbeef),19468937550547613258358766193905568760281764995701521769981870457294);
    vm.warp(82899);
    rollEpoch();
    sellBull(891389865129048891964224041492215083342213664236436752868614606394795834);
  }
}
