// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {IG} from "../src/IG.sol";

contract IGTest is Test {
    bytes4 private constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 private constant AddressZero = bytes4(keccak256("AddressZero()"));

    function setUp() public {}

    function testCantCreate() public {
        vm.expectRevert(AddressZero);
        IG ig = new IG(address(0x0), address(0x0), 0, 0);
    }

    function testCantUse() public {
        IG ig = new IG(address(0x1), address(0x2), 0, 0);

        vm.expectRevert(NoActiveEpoch);
        ig.mint(address(0x1), 0, 1);
    }

    function testCanUse() public {
        IG ig = new IG(address(0x1), address(0x2), EpochFrequency.DAILY, 0);
        ig.rollEpoch();
        ig.mint(address(0x1), 0, 1);
    }
}
