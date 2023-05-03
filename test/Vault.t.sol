// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {IG} from "../src/IG.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {TestnetDVPRegister} from "../src/testnet/TestnetDVPRegister.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Vault} from "../src/Vault.sol";

contract VaultTest is Test {
    bytes4 private constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));

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
        vm.warp(EpochFrequency.REF_TS);
    }

    function testDepositFail() public {
        IDVP ig = new IG(address(_baseToken), address(_sideToken), EpochFrequency.DAILY);
        Vault vault = new Vault(ig, address(_baseToken), address(_sideToken));
        _controller.register(address(vault));

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.prank(_alice);
        vm.expectRevert(NoActiveEpoch);
        vault.deposit(100);
    }

    function testDeposit() public {
        IDVP ig = new IG(address(_baseToken), address(_sideToken), EpochFrequency.DAILY);
        Vault vault = new Vault(ig, address(_baseToken), address(_sideToken));
        _controller.register(address(vault));
        vault.rollEpoch();

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.prank(_alice);
        vault.deposit(100);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        // initial share price is 1:1, so expect 100 shares to be minted
        assertEq(100, vault.totalSupply());
        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(_alice);
        assertEq(0, _baseToken.balanceOf(_alice));
        assertEq(0, shares);
        assertEq(100, unredeemedShares);
    }

    function _provideApprovedBaseTokens(address wallet, uint256 amount, address approved) private {
        vm.prank(_tokenAdmin);
        _baseToken.mint(wallet, amount);
        vm.prank(wallet);
        _baseToken.approve(approved, amount);
    }
}
