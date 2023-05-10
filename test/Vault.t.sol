// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {VaultLib} from "../src/lib/VaultLib.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {IG} from "../src/IG.sol";
import {Registry} from "../src/Registry.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Vault} from "../src/Vault.sol";

contract VaultTest is Test {
    bytes4 constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 constant VaultDead = bytes4(keccak256("VaultDead()"));
    bytes4 constant VaultNotDead = bytes4(keccak256("VaultNotDead()"));

    address tokenAdmin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    Vault vault;
    Registry registry;

    function setUp() public {
        registry = new Registry();
        address swapper = address(0x5);
        (address baseToken_, address sideToken_) = TokenUtils.initTokens(tokenAdmin, address(registry), swapper, vm);
        baseToken = TestnetToken(baseToken_);
        sideToken = TestnetToken(sideToken_);
        vm.warp(EpochFrequency.REF_TS);
        vault = VaultUtils.createRegisteredVault(baseToken_, sideToken_, EpochFrequency.DAILY, registry);
        vault.rollEpoch();
    }

    function testDepositFail() public {
        Vault notActiveVault = VaultUtils.createRegisteredVault(
            address(baseToken),
            address(sideToken),
            EpochFrequency.DAILY,
            registry
        );
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(notActiveVault), 100, vm);
        vm.prank(alice);
        vm.expectRevert(NoActiveEpoch);
        notActiveVault.deposit(100);
    }

    function testDeposit() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        // initial share price is 1:1, so expect 100 shares to be minted
        assertEq(100, vault.totalSupply());
        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(alice);
        assertEq(0, baseToken.balanceOf(alice));
        assertEq(0, shares);
        assertEq(100, unredeemedShares);
        // check lockedLiquidity
        uint256 lockedLiquidity = VaultUtils.vaultState(vault).liquidity.locked;
        assertEq(100, lockedLiquidity);
    }

    function testRedeemFail() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(ExceedsAvailable);
        vault.redeem(150);
    }

    function testRedeem() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.redeem(50);

        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(alice);
        assertEq(50, shares);
        assertEq(50, unredeemedShares);
        assertEq(50, vault.balanceOf(alice));

        // check lockedLiquidity. It still remains the same
        uint256 lockedLiquidity = VaultUtils.vaultState(vault).liquidity.locked;
        assertEq(100, lockedLiquidity);
    }

    function testInitWithdrawFail() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.startPrank(alice);
        vault.deposit(100);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vault.initiateWithdraw(100);
    }

    function testInitWithdrawWithRedeem() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.startPrank(alice);
        vault.deposit(100);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vault.redeem(100);
        vault.initiateWithdraw(100);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);

        assertEq(0, vault.balanceOf(alice));
        assertEq(100, withdrawalShares);
    }

    function testInitWithdrawWithoutRedeem() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.startPrank(alice);
        vault.deposit(100);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vault.initiateWithdraw(100);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(0, vault.balanceOf(alice));
        assertEq(100, withdrawalShares);
    }

    function testInitWithdrawPartWithoutRedeem() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(50, vault.balanceOf(alice));
        assertEq(50, vault.balanceOf(address(vault)));
        assertEq(50, withdrawalShares);
    }

    function testWithdraw() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(40);
        // a max redeem is done within initiateWithdraw so unwithdrawn shares remain to alice
        assertEq(40, vault.balanceOf(address(vault)));
        assertEq(60, vault.balanceOf(alice));
        // check lockedLiquidity
        uint256 lockedLiquidity = VaultUtils.vaultState(vault).liquidity.locked;
        assertEq(100, lockedLiquidity);

        Utils.skipDay(false, vm);
        vault.rollEpoch();

        // check lockedLiquidity
        lockedLiquidity = VaultUtils.vaultState(vault).liquidity.locked;
        assertEq(60, lockedLiquidity);

        vm.prank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(60, vault.totalSupply());
        assertEq(60, baseToken.balanceOf(address(vault)));
        assertEq(40, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalShares);
    }

    /**
     * Describe two users, the first (Alice) deposits 100$ in epoch1 receiving 100 shares.
     * Meanwhile the price of the lockedLiquidity has been multiplied by 2 (always in epoch1).
     * Bob deposits 100$ in epoch1, but, since his shares will be delivered in epoch2 and the price in epoch1 is changed, Bob receive 50 shares.
     * In epoch2, the price has been multiplied by 2 again. Meanwhile Bob and Alice start a the withdraw procedure for all their shares.
     * Alice should receive 400$ and Bob 200$ from their shares.
     */
    function testVaultMathDoubleLiquidity() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(vault.totalSupply(), 100);
        assertEq(heldByVaultAlice, 100);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), bob, address(vault), 100, vm);
        vm.prank(bob);
        vault.deposit(100);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), tokenAdmin, address(vault), 100, vm);
        vm.prank(tokenAdmin);
        vault.moveAsset(100);
        assertEq(baseToken.balanceOf(address(vault)), 300);

        Utils.skipDay(false, vm);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(vault.totalSupply(), 150);
        assertEq(heldByVaultBob, 50);

        vm.prank(alice);
        vault.initiateWithdraw(100);

        vm.prank(bob);
        vault.initiateWithdraw(50);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), tokenAdmin, address(vault), 300, vm);
        vm.prank(tokenAdmin);
        vault.moveAsset(300);
        assertEq(baseToken.balanceOf(address(vault)), 600);

        Utils.skipDay(false, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(50, vault.totalSupply());
        assertEq(200, baseToken.balanceOf(address(vault)));
        assertEq(400, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);

        vm.prank(bob);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(200, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
    }

    /**
     * Describe two users, the first (Alice) deposits 100$ in epoch1 receiving 100 shares.
     * Meanwhile the price of the lockedLiquidity has been divided by 2 (always in epoch1).
     * Bob deposits 100$ in epoch1, but, since his shares will be delivered in epoch2 and the price in epoch1 is changed, Bob receive 200 shares.
     * In epoch2, the price has been divided by 2 again. Meanwhile Bob and Alice start a the withdraw procedure for all their shares.
     * Alice should receive 25$ and Bob 50$ from their shares.
     */
    function testVaultMathHalfLiquidity() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(vault.totalSupply(), 100);
        assertEq(heldByVaultAlice, 100);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), bob, address(vault), 100, vm);
        vm.prank(bob);
        vault.deposit(100);

        // Remove asset from Vault
        vault.moveAsset(-50);
        assertEq(baseToken.balanceOf(address(vault)), 150);

        Utils.skipDay(false, vm);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(vault.totalSupply(), 300);
        assertEq(heldByVaultBob, 200);

        vm.prank(alice);
        vault.initiateWithdraw(100);

        vm.prank(bob);
        vault.initiateWithdraw(200);

        vault.moveAsset(-75);
        assertEq(baseToken.balanceOf(address(vault)), 75);

        Utils.skipDay(false, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(200, vault.totalSupply());
        assertEq(50, baseToken.balanceOf(address(vault)));
        assertEq(25, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);

        vm.prank(bob);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(50, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
    }
}
