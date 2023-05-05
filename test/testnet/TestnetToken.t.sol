// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {Factory} from "../../src/Factory.sol";

contract TestnetTokenTest is Test {
    bytes4 constant NotInitialized = bytes4(keccak256("NotInitialized()"));
    bytes4 constant Unauthorized = bytes4(keccak256("Unauthorized()"));
    bytes4 constant CallerNotAdmin = bytes4(keccak256("CallerNotAdmin()"));

    address controller;
    address swapper = address(0x2);

    address admin = address(0x3);
    address alice = address(0x4);
    address bob = address(0x5);

    function setUp() public {
        controller = address(new Factory());
    }

    function testCantMintNotInit() public {
        vm.prank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        vm.expectRevert(NotInitialized);
        token.mint(admin, 100);
    }

    function testCantInit() public {
        vm.prank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");

        vm.expectRevert(CallerNotAdmin);
        token.setController(controller);

        vm.expectRevert(CallerNotAdmin);
        token.setSwapper(swapper);
    }

    function testInit() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);

        assertEq(controller, token.getController());
        assertEq(swapper, token.getSwapper());
    }

    function testCantMintUnauth() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(Unauthorized);
        token.mint(alice, 100);
    }

    function testMint() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        vm.stopPrank();

        vm.prank(controller);
        token.mint(alice, 100);
        assertEq(100, token.balanceOf(alice));

        vm.prank(swapper);
        token.mint(alice, 100);
        assertEq(200, token.balanceOf(alice));

        vm.prank(admin);
        token.mint(alice, 100);
        assertEq(300, token.balanceOf(alice));
    }

    function testCantTransfer() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        vm.stopPrank();

        vm.prank(controller);
        token.mint(alice, 100);
        assertEq(100, token.balanceOf(alice));

        vm.prank(alice);
        vm.expectRevert(Unauthorized);
        token.transfer(bob, 100);

        vm.prank(admin);
        vm.expectRevert("ERC20: insufficient allowance");
        token.transferFrom(alice, bob, 100);
    }

    function testTransfer() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        vm.stopPrank();

        vm.prank(controller);
        token.mint(alice, 100);
        assertEq(100, token.balanceOf(alice));

        vm.prank(alice);
        token.approve(controller, 100);

        vm.prank(controller);
        token.transferFrom(alice, bob, 100);
        assertEq(100, token.balanceOf(bob));
    }
}