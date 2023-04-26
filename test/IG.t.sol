// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {IG} from "../src/IG.sol";

contract IGTest is Test {
    bytes4 private constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 private constant AddressZero = bytes4(keccak256("AddressZero()"));

    address baseToken = address(0x1);
    address sideToken = address(0x2);

    function setUp() public {}

    function testCantCreate() public {
        vm.expectRevert(AddressZero);
        IG ig = new IG(address(0x0), address(0x0), 0, 0);
    }

    function testCantUse() public {
        IG ig = new IG(baseToken, sideToken, 0, 0);

        vm.expectRevert(NoActiveEpoch);
        ig.mint(address(0x1), 0, 0, 1);
    }

    function testCanUse() public {
        IG ig = new IG(baseToken, sideToken, EpochFrequency.DAILY, 0);
        ig.rollEpoch();
        ig.mint(address(0x1), 0, 0, 1);
    }

    function testOptionMint() public {
        address owner = address(0x3);
        uint256 inputStrategy = 0;
        uint256 inputAmount = 1;

        IG ig = new IG(baseToken, sideToken, EpochFrequency.DAILY, 0);
        ig.rollEpoch();
        ig.mint(owner, 0, inputStrategy, inputAmount);

        bytes32 posId = keccak256(abi.encodePacked(owner, ig.currentStrike(), inputStrategy));

        (uint256 amount, uint256 strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(inputStrategy, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testOptionMintDouble() public {
        address owner = address(0x3);
        uint256 inputStrategy = 0;
        uint256 inputAmount = 1;

        IG ig = new IG(baseToken, sideToken, EpochFrequency.DAILY, 0);
        ig.rollEpoch();
        ig.mint(owner, 0, inputStrategy, inputAmount);
        ig.mint(owner, 0, inputStrategy, inputAmount);

        bytes32 posId = keccak256(abi.encodePacked(owner, ig.currentStrike(), inputStrategy));

        (uint256 amount, uint256 strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(inputStrategy, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(2 * inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testOptionMintAndBurn() public {
        address owner = address(0x3);
        uint256 inputStrategy = 0;
        uint256 inputAmount = 1;

        IG ig = new IG(baseToken, sideToken, EpochFrequency.DAILY, 0);
        ig.rollEpoch();
        ig.mint(owner, 0, inputStrategy, inputAmount);
        ig.mint(owner, 0, inputStrategy, inputAmount);
        ig.burn(ig.currentEpoch(), owner, 0, inputStrategy, inputAmount);

        bytes32 posId = keccak256(abi.encodePacked(owner, ig.currentStrike(), inputStrategy));

        (uint256 amount, uint256 strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(inputStrategy, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }
}
