// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {Factory} from "../../src/Factory.sol";
import {TestnetRegistry} from "../../src/testnet/TestnetRegistry.sol";

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
        controller = address(new TestnetRegistry());
    }

    function testCantMintNotInit() public {
        vm.prank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        vm.expectRevert(NotInitialized);
        token.mint(admin, 100);
    }

    // NOTE: it doesn't make sense to test NotInitialized for burn and transfers as you can't mint.

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

        vm.prank(admin);
        token.mint(alice, 100);
        assertEq(100, token.balanceOf(alice));

        vm.prank(swapper);
        token.mint(alice, 100);
        assertEq(200, token.balanceOf(alice));
    }

    function testCantBurnUnauth() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        token.mint(alice, 100);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(Unauthorized);
        token.burn(alice, 100);
    }

    function testBurn() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        token.mint(alice, 100);
        vm.stopPrank();

        assertEq(100, token.balanceOf(alice));

        vm.prank(swapper);
        token.burn(alice, 100);
        assertEq(0, token.balanceOf(alice));
    }

    function testCantTransfer() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        token.mint(alice, 100);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(Unauthorized);
        token.transfer(bob, 100);

        vm.prank(bob);
        vm.expectRevert(Unauthorized);
        token.transferFrom(alice, bob, 100);

        vm.prank(admin);
        vm.expectRevert("ERC20: insufficient allowance");
        token.transferFrom(alice, bob, 100);
    }

    function testTransfer() public {
        vm.startPrank(admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        token.mint(alice, 100);
        vm.stopPrank();

        address vaultAddress = address(0x42);

        TestnetRegistry registry = TestnetRegistry(controller);
        registry.registerVault(vaultAddress);

        vm.prank(alice);
        token.approve(vaultAddress, 100);

        vm.prank(vaultAddress);
        token.transferFrom(alice, vaultAddress, 100);
        assertEq(100, token.balanceOf(vaultAddress));
    }
}
