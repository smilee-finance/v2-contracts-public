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
import {Factory} from "../src/Factory.sol";

contract VaultTest is Test {
    bytes4 private constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 private constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));

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
        Vault vault = _createMarket();

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.prank(_alice);
        vm.expectRevert(NoActiveEpoch);
        vault.deposit(100);
    }

    function testDeposit() public {
        Vault vault = _createMarket();
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

    function testRedeemFail() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.prank(_alice);
        vault.deposit(100);

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        vm.prank(_alice);
        vm.expectRevert(ExceedsAvailable);
        vault.redeem(150);
    }

    function testRedeem() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.prank(_alice);
        vault.deposit(100);

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        vm.prank(_alice);
        vault.redeem(50);

        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(_alice);
        assertEq(50, shares);
        assertEq(50, unredeemedShares);
        assertEq(50, vault.balanceOf(_alice));
    }

    function testInitWithdrawFail() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.startPrank(_alice);
        vault.deposit(100);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vault.initiateWithdraw(100);
    }

    function testInitWithdrawWithRedeem() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.startPrank(_alice);
        vault.deposit(100);

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        vault.redeem(100);
        vault.initiateWithdraw(100);
        (, uint256 withdrawalShares) = vault.withdrawals(_alice);

        assertEq(0, vault.balanceOf(_alice));
        assertEq(100, withdrawalShares);
    }

    function testInitWithdrawWithoutRedeem() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.startPrank(_alice);
        vault.deposit(100);

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        vault.initiateWithdraw(100);
        (, uint256 withdrawalShares) = vault.withdrawals(_alice);
        assertEq(0, vault.balanceOf(_alice));
        assertEq(100, withdrawalShares);
    }

    function testInitWithdrawWithoutRedeem____() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(_alice, 100, address(vault));

        vm.startPrank(_alice);
        vault.deposit(100);

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        vault.initiateWithdraw(50);
        (, uint256 withdrawalShares) = vault.withdrawals(_alice);
        assertEq(50, vault.balanceOf(_alice));
        assertEq(50, withdrawalShares);
    }

    function _createMarket() private returns (Vault vault) {
        vault = new Vault(address(_baseToken), address(_sideToken), EpochFrequency.DAILY);
        _controller.register(address(vault));
    }

    function _provideApprovedBaseTokens(address wallet, uint256 amount, address approved) private {
        vm.prank(_tokenAdmin);
        _baseToken.mint(wallet, amount);
        vm.prank(wallet);
        _baseToken.approve(approved, amount);
    }
}
