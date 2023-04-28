// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestnetDVPRegister} from "../src/testnet/TestnetDVPRegister.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Vault} from "../src/Vault.sol";

contract VaultTest is Test {

    address _tokenAdmin = address(0x1);
    address _alice = address(0x2);
    TestnetToken _baseToken;
    TestnetToken _sideToken;
    TestnetDVPRegister _controller;

    function setUp() public {
        _controller = new TestnetDVPRegister();
        address controller = address(_controller);
        address swapper = address(0x5);
        vm.startPrank(_tokenAdmin);

        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        _baseToken = token;

        token = new TestnetToken("Testnet WETH", "stWETH");
        token.setController(controller);
        token.setSwapper(swapper);
        _sideToken = token;

        vm.stopPrank();
    }

    function testDeposit() public {
        vm.prank(_tokenAdmin);
        _baseToken.mint(_alice, 100);
        assertEq(100, _baseToken.balanceOf(_alice));
        
        Vault vault = new Vault(address(_baseToken), address(_sideToken));
        _controller.record(address(vault));

        vm.startPrank(_alice);
        _baseToken.approve(address(vault), 100);
        vault.deposit(100);
        vm.stopPrank();

        assertEq(0, _baseToken.balanceOf(_alice));
    }
}
