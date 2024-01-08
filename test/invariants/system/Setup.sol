// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// sample contract
// remove when using your own
contract Counter {
  uint256 public value;

  function increment(uint256 amount) public {
    value += amount;
  }
}

abstract contract Setup {
  Counter internal counter;

  function deploy() internal {
    counter = new Counter();
  }
}