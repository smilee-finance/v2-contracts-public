// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Vault} from "../src/Vault.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "../src/AddressProvider.sol";

/**
    @title Test case for underlying asset going to zero
    @dev This should never happen, still we need to test shares value goes to zero, users deposits can be rescued and
         new deposits are not allowed
 */
contract VaultDeathTest is Test {
    bytes4 constant NothingToRescue = bytes4(keccak256("NothingToRescue()"));
    bytes4 constant VaultDead = bytes4(keccak256("VaultDead()"));
    bytes4 constant EpochFinished = bytes4(keccak256("EpochFinished()"));
    bytes4 constant VaultNotDead = bytes4(keccak256("VaultNotDead()"));
    bytes4 constant DeadManualKillReason = bytes4(keccak256("ManualKill"));

    address tokenAdmin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    MockedVault vault;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.prank(tokenAdmin);
        AddressProvider ap = new AddressProvider();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, tokenAdmin, vm));
        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vm.prank(tokenAdmin);
        vault.rollEpoch();
    }

    /**
     * Describe two users, the first (Alice) deposits 100$ in epoch1 receiving 100 shares.
     * Bob deposits 100$ in epoch2. Bob receive also 100 shares.
     * Bob and Alice starts the withdraw procedure in epoch3. Meanwhile, the lockedLiquidity goes to 0.
     * In epoch3, the Vault dies due to empty lockedLiquidity (so the sharePrice is 0). Nobody can deposit from epoch2 on.
     * Bob and Alice could complete the withdraw procedure receiving both 0$.
     */
    function testVaultMathLiquidityGoesToZero() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(200, vault.totalSupply());
        assertEq(100, heldByVaultBob);

        vm.startPrank(alice);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        // remove brutally liquidity from Vault.
        vault.moveValue(-10000);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(true, VaultUtils.vaultState(vault).dead);

        vm.startPrank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(100, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
        vm.stopPrank();
    }

    /**
     * Describe the case of deposit after Vault Death. In this case is expected an error.
     */
    function testVaultMathLiquidityGoesToZeroWithDepositAfterDieFail() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);

        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vault.moveValue(-10000);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(true, VaultUtils.vaultState(vault).dead);

        // Alice wants to deposit after Vault death. We expect a VaultDead error.
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.startPrank(alice);
        vm.expectRevert(VaultDead);
        vault.deposit(100, alice, 0);
        vm.stopPrank();
    }

    /**
     *
     */
    function testVaultMathLiquidityGoesToZeroWithDepositBeforeDie() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        // NOTE: cause the locked liquidity to go to zero; this, in turn, cause the vault death
        vault.moveValue(-10000);

        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(true, VaultUtils.vaultState(vault).dead);
        // No new shares has been minted:
        assertEq(100, vault.totalSupply());

        (heldByAccountAlice, heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(0, heldByAccountAlice);
        assertEq(100, heldByVaultAlice);

        assertEq(100, VaultUtils.vaultState(vault).liquidity.pendingDeposits);

        (, uint256 depositReceiptsAliceAmount, , ) = vault.depositReceipts(alice);
        assertEq(100, depositReceiptsAliceAmount);

        // Alice rescues her baseToken
        vm.prank(alice);
        vault.rescueDeposit();

        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingDeposits);
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(100, baseToken.balanceOf(alice));
        (, depositReceiptsAliceAmount, , ) = vault.depositReceipts(alice);
        assertEq(0, depositReceiptsAliceAmount);
    }

    function testVaultRescueDepositVaultNotDeath() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        vm.startPrank(alice);
        vm.expectRevert(VaultNotDead);
        vault.rescueDeposit();
        vm.stopPrank();
        Utils.skipDay(true, vm);

        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
    }

    /**
     * An user tries to call rescueDeposit function when a vault is dead, but without nothing to rescue. A NothingToRescue error is expected.
     */
    function testVaultRescueDepositNothingToRescue() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        Utils.skipDay(true, vm);

        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        vault.moveValue(-10000);

        // assertEq(0, vault.v0());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(100, vault.totalSupply());

        // Check if lockedLiquidity has gone to 0 and the Vault is dead.
        // assertEq(0, vault.v0());
        assertEq(true, VaultUtils.vaultState(vault).dead);

        // Alice starts the rescue procedure. An error is expected
        vm.prank(alice);
        vm.expectRevert(NothingToRescue);
        vault.rescueDeposit();
    }

    function testVaultManualDead() public {
        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        assertEq(true, vault.manuallyKilled());

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(true, VaultUtils.vaultState(vault).dead);
        assertEq(DeadManualKillReason, VaultUtils.vaultState(vault).deadReason);
    }

    function testVaultManualDeadRescueShares() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.rescueShares();

        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(0, vault.totalSupply());
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(100e18, baseToken.balanceOf(alice));
    }

    function testVaultManualDeadMultipleRescueShares() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 200e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.rescueShares();

        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(200e18, vault.totalSupply());
        (, , , uint256 cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(200e18, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(0, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(100e18, baseToken.balanceOf(alice));

        vm.prank(bob);
        vault.rescueShares();

        (uint256 heldByAccountBob, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(0, vault.totalSupply());
        (, , , uint256 cumulativeAmountBob) = vault.depositReceipts(bob);
        assertEq(0, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(0, cumulativeAmountBob);
        assertEq(0, heldByVaultBob);
        assertEq(0, heldByAccountBob);
        assertEq(200e18, baseToken.balanceOf(bob));
    }

    function testVaultManualDeadInitiateBeforeEpochOfDeathEpochFinished() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50e18);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        // Skip another day to simulate the epochFrozen scenarios.
        // In this case, the "traditional" completeWithdraw shouldn't work due to epochFrozen error.
        Utils.skipDay(true, vm);

        vm.prank(alice);
        vm.expectRevert(EpochFinished);
        vault.completeWithdraw();

        vm.prank(alice);
        vault.rescueShares();

        // Check if alice has rescued all her shares
        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(0, vault.totalSupply());
        (, , , uint256 cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(0, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(0, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(100e18, baseToken.balanceOf(alice));
    }

    function testVaultManualDeadInitiateBeforeEpochOfDeath() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50e18);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        // Check if alice has rescued all her shares
        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(50e18, vault.totalSupply());
        (, , , uint256 cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(50e18, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(50e18, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(50e18, heldByAccountAlice);
        assertEq(50e18, baseToken.balanceOf(alice));

        vm.prank(alice);
        vault.rescueShares();

        // Check if alice has rescued all her shares
        (heldByAccountAlice, heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(0, vault.totalSupply());
        (, , , cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(0, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(0, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(100e18, baseToken.balanceOf(alice));
    }

    function testVaultManualDeadDepositBeforeEpochOfDeath() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.rescueShares();

        assertEq(0, vault.totalSupply());
        assertEq(0, VaultUtils.vaultState(vault).liquidity.totalDeposit);

        // Check if alice has rescued all her shares
        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        (, , , uint256 cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(0, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(200e18, baseToken.balanceOf(alice));
    }
}
