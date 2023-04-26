// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {IG} from "../src/IG.sol";

import {console} from "forge-std/console.sol";

contract IGTest is Test {
    // Errors hashes
    bytes4 private constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 private constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 private constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 private constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));

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

    function testMint() public {
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

    function testMintDouble() public {
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

    function testMintAndBurn() public {
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

    function testMintMultiple() public {
        address owner1 = address(0x3);
        address owner2 = address(0x4);
        uint256 inputStrategy1 = 0;
        uint256 inputStrategy2 = 0;
        uint256 inputAmount = 1;

        IG ig = new IG(baseToken, sideToken, EpochFrequency.DAILY, 0);
        ig.rollEpoch();
        ig.mint(owner1, 0, inputStrategy1, inputAmount);
        ig.mint(owner2, 0, inputStrategy2, inputAmount);

        bytes32 posId1 = keccak256(abi.encodePacked(owner1, ig.currentStrike(), inputStrategy1));
        bytes32 posId2 = keccak256(abi.encodePacked(owner2, ig.currentStrike(), inputStrategy2));

        {
            (uint256 amount1, uint256 strategy1, uint256 strike1, uint256 epoch1) = ig.positions(posId1);
            assertEq(inputStrategy1, strategy1);
            assertEq(inputAmount, amount1);
        }

        {
            (uint256 amount2, uint256 strategy2, uint256 strike2, uint256 epoch2) = ig.positions(posId2);
            assertEq(inputStrategy2, strategy2);
            assertEq(inputAmount, amount2);
        }

        ig.burn(ig.currentEpoch(), owner1, 0, inputStrategy1, inputAmount);
        ig.burn(ig.currentEpoch(), owner2, 0, inputStrategy2, inputAmount);

        {
            (uint256 amount1, , , ) = ig.positions(posId1);
            assertEq(0, amount1);
        }

        {
            (uint256 amount2, , , ) = ig.positions(posId2);
            assertEq(0, amount2);
        }
    }

    function testCantMintZero() public {
        address owner = address(0x3);
        uint256 inputStrategy = 0;

        IG ig = new IG(baseToken, sideToken, EpochFrequency.DAILY, 0);
        ig.rollEpoch();

        vm.expectRevert(AmountZero);
        ig.mint(owner, 0, inputStrategy, 0);
    }

    function testCantBurnMoreThanMinted() public {
        address owner = address(0x3);
        uint256 inputStrategy = 0;
        uint256 inputAmount = 1;

        IG ig = new IG(baseToken, sideToken, EpochFrequency.DAILY, 0);
        ig.rollEpoch();
        ig.mint(owner, 0, inputStrategy, inputAmount);

        uint256 epoch = ig.currentEpoch();
        vm.expectRevert(CantBurnMoreThanMinted);
        ig.burn(epoch, owner, 0, inputStrategy, inputAmount + 1);
    }
}
