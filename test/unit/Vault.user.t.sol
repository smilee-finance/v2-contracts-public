// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {VaultLib} from "@project/lib/VaultLib.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {Vault} from "@project/Vault.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";

contract VaultUserTest is Test {
    address admin;
    address user;
    TestnetToken baseToken;
    TestnetToken sideToken;
    AddressProvider addressProvider;

    Vault vault;

    bytes4 public constant ERR_AMOUNT_ZERO = bytes4(keccak256("AmountZero()"));
    bytes4 public constant ERR_EXCEEDS_MAX_DEPOSIT = bytes4(keccak256("ExceedsMaxDeposit()"));
    bytes4 public constant ERR_EPOCH_FINISHED = bytes4(keccak256("EpochFinished()"));
    bytes4 public constant ERR_VAULT_DEAD = bytes4(keccak256("VaultDead()"));
    bytes4 public constant ERR_VAULT_NOT_DEAD = bytes4(keccak256("VaultNotDead()"));
    bytes4 public constant ERR_NOTHING_TO_RESCUE = bytes4(keccak256("NothingToRescue()"));
    bytes4 public constant ERR_MANUALLY_KILLED = bytes4(keccak256("ManuallyKilled()"));
    bytes4 public constant ERR_EXCEEDS_AVAILABLE = bytes4(keccak256("ExceedsAvailable()"));
    bytes public constant ERR_PAUSED = bytes("Pausable: paused");

    constructor() {
        admin = address(777);
        user = address(644);

        vm.startPrank(admin);
        addressProvider = new AddressProvider(0);
        addressProvider.grantRole(addressProvider.ROLE_ADMIN(), admin);
        vm.stopPrank();

        baseToken = TestnetToken(TokenUtils.create("USDC", 7, addressProvider, admin, vm));
        sideToken = TestnetToken(TokenUtils.create("WETH", 18, addressProvider, admin, vm));

        vm.startPrank(admin);

        baseToken.setTransferRestriction(false);
        sideToken.setTransferRestriction(false);

        // Needed by the exchange adapter:
        TestnetPriceOracle priceOracle = new TestnetPriceOracle(address(baseToken));
        priceOracle.setTokenPrice(address(sideToken), 1e18);
        addressProvider.setPriceOracle(address(priceOracle));

        TestnetSwapAdapter exchange = new TestnetSwapAdapter(addressProvider.priceOracle());
        addressProvider.setExchangeAdapter(address(exchange));

        // No fees by default:
        FeeManager feeManager = new FeeManager();
        feeManager.grantRole(feeManager.ROLE_ADMIN(), admin);
        addressProvider.setFeeManager(address(feeManager));

        vm.stopPrank();
    }

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);
        vm.startPrank(admin);
        vault = new Vault(
            address(baseToken),
            address(sideToken),
            EpochFrequency.DAILY,
            EpochFrequency.DAILY,
            address(addressProvider)
        );

        vault.grantRole(vault.ROLE_ADMIN(), admin);
        vault.grantRole(vault.ROLE_EPOCH_ROLLER(), admin);
        vm.stopPrank();
    }

    /**
     * Simulate the behaviour of a single deposit operation on a clean state.
     *
     * - The user balance must be transferred to the vault.
     * - The user must receive a deposit receipt for such amount.
     * - The vault must correctly account such deposit.
     *
     * When the amount exceeds the deposit limit, the transaction must revert.
     * Then the amount is zero, the transaction must revert.
     */
    function testDeposit(uint256 amount) public {
        // provide tokens to the user:
        vm.prank(admin);
        baseToken.mint(user, amount);

        // check user pre-conditions:
        assertEq(amount, baseToken.balanceOf(user));
        (
            uint256 epoch,
            uint256 receiptAmount,
            uint256 unredeemedShares,
            uint256 cumulativeAmount
        ) = vault.depositReceipts(user);
        assertEq(0, epoch);
        assertEq(0, receiptAmount);
        assertEq(0, unredeemedShares);
        assertEq(0, cumulativeAmount);

        // check vault pre-conditions:
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(0, sideToken.balanceOf(address(vault)));
        (, uint256 pendingDeposit, , , uint256 totalDeposit, , , , ) = vault.vaultState();
        assertEq(0, pendingDeposit);
        assertEq(0, totalDeposit);
        (uint256 baseTokenAmount, uint256 sideTokenAmount) = vault.balances();
        assertEq(0, baseTokenAmount);
        assertEq(0, sideTokenAmount);

        // retrieve info:
        Epoch memory vaultEpoch = vault.getEpoch();
        uint256 maxDeposit = vault.maxDeposit();

        // deposit:
        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        if (amount == 0) {
            vm.expectRevert(ERR_AMOUNT_ZERO);
        }
        if (amount > maxDeposit) {
            vm.expectRevert(ERR_EXCEEDS_MAX_DEPOSIT);
        }
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        if (amount == 0 || amount > maxDeposit) {
            // The transaction reverted, hence there's no need for further checks.
            return;
        }

        // check user post-conditions:
        assertEq(0, baseToken.balanceOf(user));
        (
            epoch,
            receiptAmount,
            unredeemedShares,
            cumulativeAmount
        ) = vault.depositReceipts(user);
        assertEq(vaultEpoch.current, epoch);
        assertEq(amount, receiptAmount);
        assertEq(0, unredeemedShares);
        assertEq(amount, cumulativeAmount);

        // check vault post-conditions:
        assertEq(amount, baseToken.balanceOf(address(vault)));
        assertEq(0, sideToken.balanceOf(address(vault)));
        (, pendingDeposit, , , totalDeposit, , , , ) = vault.vaultState();
        assertEq(amount, pendingDeposit);
        assertEq(amount, totalDeposit);
        (baseTokenAmount, sideTokenAmount) = vault.balances();
        assertEq(0, baseTokenAmount);
        assertEq(0, sideTokenAmount);
    }

    function testDepositWhenEpochFinished(uint256 amount) public {
        vm.prank(admin);
        baseToken.mint(user, amount);

        Epoch memory vaultEpoch = vault.getEpoch();
        vm.warp(vaultEpoch.current + 1);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);

        vm.expectRevert(ERR_EPOCH_FINISHED);
        vault.deposit(amount, user, 0);

        vm.stopPrank();
    }

    function testDepositWhenDead(uint256 amount) public {
        vm.prank(admin);
        vault.killVault();

        Epoch memory vaultEpoch = vault.getEpoch();
        vm.warp(vaultEpoch.current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);

        vm.expectRevert(ERR_VAULT_DEAD);
        vault.deposit(amount, user, 0);

        vm.stopPrank();
    }

    function testDepositWhenPaused(uint256 amount) public {
        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.prank(admin);
        vault.changePauseState();

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);

        vm.expectRevert(ERR_PAUSED);
        vault.deposit(amount, user, 0);

        vm.stopPrank();
    }

    /**
     * Verifies that the deposit operations are well isolated
     * from the point of view of the user wallet and the number of
     * such operations (within the same epoch).
     */
    function testDepositMultiOperation() public {
        address user_alice = address(123);
        address user_bob = address(456);

        // Alice first deposit:
        uint256 alice_amount_1 = 100 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_alice, alice_amount_1);
        vm.startPrank(user_alice);
        baseToken.approve(address(vault), alice_amount_1);
        vault.deposit(alice_amount_1, user_alice, 0);
        vm.stopPrank();

        // Bob deposit:
        uint256 bob_amount = 200 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_bob, bob_amount);
        vm.startPrank(user_bob);
        baseToken.approve(address(vault), bob_amount);
        vault.deposit(bob_amount, user_bob, 0);
        vm.stopPrank();

        // Alice second deposit:
        uint256 alice_amount_2 = 300 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_alice, alice_amount_2);
        vm.startPrank(user_alice);
        baseToken.approve(address(vault), alice_amount_2);
        vault.deposit(alice_amount_2, user_alice, 0);
        vm.stopPrank();

        // retrieve info:
        Epoch memory vaultEpoch = vault.getEpoch();

        // Bob deposit must be independent of the Alice ones:
        (
            uint256 epoch,
            uint256 receiptAmount,
            uint256 unredeemedShares,
            uint256 cumulativeAmount
        ) = vault.depositReceipts(user_alice);
        assertEq(vaultEpoch.current, epoch);
        assertEq(alice_amount_1 + alice_amount_2, receiptAmount);
        assertEq(0, unredeemedShares);
        assertEq(alice_amount_1 + alice_amount_2, cumulativeAmount);
        (
            epoch,
            receiptAmount,
            unredeemedShares,
            cumulativeAmount
        ) = vault.depositReceipts(user_bob);
        assertEq(vaultEpoch.current, epoch);
        assertEq(bob_amount, receiptAmount);
        assertEq(0, unredeemedShares);
        assertEq(bob_amount, cumulativeAmount);

        // check vault post-conditions:
        uint256 expected_total_amount = alice_amount_1 + alice_amount_2 + bob_amount;
        assertEq(expected_total_amount, baseToken.balanceOf(address(vault)));
        assertEq(0, sideToken.balanceOf(address(vault)));
        (, uint256 pendingDeposit, , , uint256 totalDeposit, , , , ) = vault.vaultState();
        assertEq(expected_total_amount, pendingDeposit);
        assertEq(expected_total_amount, totalDeposit);
        (uint256 baseTokenAmount, uint256 sideTokenAmount) = vault.balances();
        assertEq(0, baseTokenAmount);
        assertEq(0, sideTokenAmount);
    }

    function testDepositReceiptAcrossEpochs(uint256 firstAmount, uint256 secondAmount, uint256 thirdAmount) public {
        vm.assume(firstAmount > 0);
        vm.assume(secondAmount > 0);
        vm.assume(thirdAmount > 0);
        vm.assume(firstAmount <= vault.maxDeposit());
        vm.assume(secondAmount <= vault.maxDeposit() - firstAmount);
        vm.assume(thirdAmount <= vault.maxDeposit() - firstAmount - secondAmount);

        (
            uint256 epoch,
            uint256 receiptAmount,
            uint256 unredeemedShares,
            uint256 cumulativeAmount
        ) = vault.depositReceipts(user);
        assertEq(0, epoch);
        assertEq(0, receiptAmount);
        assertEq(0, unredeemedShares);
        assertEq(0, cumulativeAmount);

        // provide tokens to the user:
        vm.prank(admin);
        baseToken.mint(user, firstAmount + secondAmount + thirdAmount);

        // first deposit:
        vm.startPrank(user);
        baseToken.approve(address(vault), firstAmount);
        vault.deposit(firstAmount, user, 0);
        vm.stopPrank();

        (
            epoch,
            receiptAmount,
            unredeemedShares,
            cumulativeAmount
        ) = vault.depositReceipts(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(firstAmount, receiptAmount);
        assertEq(0, unredeemedShares);
        assertEq(firstAmount, cumulativeAmount);

        // second deposit:
        vm.startPrank(user);
        baseToken.approve(address(vault), secondAmount);
        vault.deposit(secondAmount, user, 0);
        vm.stopPrank();

        // NOTE: in the same epoch, the receipt is increased
        (
            epoch,
            receiptAmount,
            unredeemedShares,
            cumulativeAmount
        ) = vault.depositReceipts(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(firstAmount + secondAmount, receiptAmount);
        assertEq(0, unredeemedShares);
        assertEq(firstAmount + secondAmount, cumulativeAmount);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // third deposit:
        vm.startPrank(user);
        baseToken.approve(address(vault), thirdAmount);
        vault.deposit(thirdAmount, user, 0);
        vm.stopPrank();

        // NOTE: in another epoch, the receipt is updated with unredeemed shares
        (
            epoch,
            receiptAmount,
            unredeemedShares,
            cumulativeAmount
        ) = vault.depositReceipts(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(thirdAmount, receiptAmount);
        assertEq(firstAmount + secondAmount, unredeemedShares);
        assertEq(firstAmount + secondAmount + thirdAmount, cumulativeAmount);
    }

    function testRescueDeposit(uint256 amount) public {
        uint256 initialDeposit = 1000 * (10 ** baseToken.decimals());
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit() - initialDeposit);

        // Set the test pre-conditions:
        vm.prank(admin);
        baseToken.mint(user, initialDeposit);
        vm.startPrank(user);
        baseToken.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit, user, 0);
        vm.stopPrank();
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // By reserving all the initial liquidity as payoff, the share price will drop to zero
        vm.startPrank(admin);
        vault.setAllowedDVP(admin);
        vault.reservePayoff(initialDeposit);
        vm.stopPrank();

        // The user's deposit to rescue:
        vm.prank(admin);
        baseToken.mint(user, amount);
        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // Vault pre-conditions:
        assertEq(true, vault.dead());
        (, uint256 pendingDeposit, , , , , , , ) = vault.vaultState();
        assertEq(amount, pendingDeposit);

        // User pre-conditions:
        (, uint256 receiptAmount, , ) = vault.depositReceipts(user);
        assertEq(amount, receiptAmount);
        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vault.rescueDeposit();

        // Vault post-conditions:
        (, pendingDeposit, , , , , , , ) = vault.vaultState();
        assertEq(0, pendingDeposit);

        // User post-conditions:
        (, receiptAmount, , ) = vault.depositReceipts(user);
        assertEq(0, receiptAmount);
        assertEq(amount, baseToken.balanceOf(user));
    }

    function testRescueDepositWhenNotDead(uint256 amount) public {
        uint256 initialDeposit = 1000 * (10 ** baseToken.decimals());
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit() - initialDeposit);

        // Set the test pre-conditions:
        vm.prank(admin);
        baseToken.mint(user, initialDeposit);
        vm.startPrank(user);
        baseToken.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit, user, 0);
        vm.stopPrank();
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The user's deposit to rescue:
        vm.prank(admin);
        baseToken.mint(user, amount);
        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(false, vault.dead());

        vm.prank(user);
        vm.expectRevert(ERR_VAULT_NOT_DEAD);
        vault.rescueDeposit();
    }

    function testRescueDepositWhenPaused(uint256 amount) public {
        uint256 initialDeposit = 1000 * (10 ** baseToken.decimals());
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit() - initialDeposit);

        // Set the test pre-conditions:
        vm.prank(admin);
        baseToken.mint(user, initialDeposit);
        vm.startPrank(user);
        baseToken.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit, user, 0);
        vm.stopPrank();
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // By reserving all the initial liquidity as payoff, the share price will drop to zero
        vm.startPrank(admin);
        vault.setAllowedDVP(admin);
        vault.reservePayoff(initialDeposit);
        vm.stopPrank();

        // The user's deposit to rescue:
        vm.prank(admin);
        baseToken.mint(user, amount);
        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.prank(admin);
        vault.changePauseState();
        assertEq(true, vault.paused());

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(true, vault.dead());

        vm.prank(user);
        vm.expectRevert(ERR_PAUSED);
        vault.rescueDeposit();
    }

    function testRescueDepositWhenManuallyKilled(uint256 amount) public {
        uint256 initialDeposit = 1000 * (10 ** baseToken.decimals());
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit() - initialDeposit);

        // Set the test pre-conditions:
        vm.prank(admin);
        baseToken.mint(user, initialDeposit);
        vm.startPrank(user);
        baseToken.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit, user, 0);
        vm.stopPrank();
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // By reserving all the initial liquidity as payoff, the share price will drop to zero
        vm.startPrank(admin);
        vault.setAllowedDVP(admin);
        vault.reservePayoff(initialDeposit);
        vm.stopPrank();

        // The user's deposit to rescue:
        vm.prank(admin);
        baseToken.mint(user, amount);
        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.prank(admin);
        vault.killVault();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(true, vault.dead());

        vm.prank(user);
        vm.expectRevert(ERR_MANUALLY_KILLED);
        vault.rescueDeposit();
    }

    function testRescueDepositWhenDepositIsNotInTheLastEpoch(uint256 amount) public {
        uint256 initialDeposit = 1000 * (10 ** baseToken.decimals());
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit() - initialDeposit);

        // Set the test pre-conditions:
        vm.prank(admin);
        baseToken.mint(user, initialDeposit);
        vm.startPrank(user);
        baseToken.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit, user, 0);
        vm.stopPrank();
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.warp(vault.getEpoch().current + 1);
        vault.rollEpoch();

        // By reserving all the initial liquidity as payoff, the share price will drop to zero
        vm.startPrank(admin);
        vault.setAllowedDVP(admin);
        vault.reservePayoff(initialDeposit + amount);

        vm.warp(vault.getEpoch().current + 1);
        vault.rollEpoch();
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(ERR_NOTHING_TO_RESCUE);
        vault.rescueDeposit();
    }

    /**
     * Verifies that the rescue deposit operations are well isolated
     * from the point of view of the user wallet.
     */
    function testRescueDepositMultiOperation() public {
        uint256 initialDeposit = 1000 * (10 ** baseToken.decimals());

        // Set the test pre-conditions:
        vm.prank(admin);
        baseToken.mint(user, initialDeposit);
        vm.startPrank(user);
        baseToken.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit, user, 0);
        vm.stopPrank();
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // By reserving all the initial liquidity as payoff, the share price will drop to zero
        vm.startPrank(admin);
        vault.setAllowedDVP(admin);
        vault.reservePayoff(initialDeposit);
        vm.stopPrank();

        address user_alice = address(123);
        address user_bob = address(456);

        // Alice deposit:
        uint256 alice_amount = 100 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_alice, alice_amount);
        vm.startPrank(user_alice);
        baseToken.approve(address(vault), alice_amount);
        vault.deposit(alice_amount, user_alice, 0);
        vm.stopPrank();

        // Bob deposit:
        uint256 bob_amount = 200 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_bob, bob_amount);
        vm.startPrank(user_bob);
        baseToken.approve(address(vault), bob_amount);
        vault.deposit(bob_amount, user_bob, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

         // Vault pre-conditions:
        assertEq(true, vault.dead());
        (, uint256 pendingDeposit, , , , , , , ) = vault.vaultState();
        assertEq(alice_amount + bob_amount, pendingDeposit);

        // User pre-conditions:
        (, uint256 aliceReceiptAmount, , ) = vault.depositReceipts(user_alice);
        assertEq(alice_amount, aliceReceiptAmount);
        (, uint256 bobReceiptAmount, , ) = vault.depositReceipts(user_bob);
        assertEq(bob_amount, bobReceiptAmount);
        assertEq(0, baseToken.balanceOf(user_alice));
        assertEq(0, baseToken.balanceOf(user_bob));

        vm.prank(user_alice);
        vault.rescueDeposit();

         // Vault post-conditions:
        (, pendingDeposit, , , , , , , ) = vault.vaultState();
        assertEq(bob_amount, pendingDeposit);

        // User post-conditions:
        (, aliceReceiptAmount, , ) = vault.depositReceipts(user_alice);
        assertEq(0, aliceReceiptAmount);
        assertEq(alice_amount, baseToken.balanceOf(user_alice));

        (, bobReceiptAmount, , ) = vault.depositReceipts(user_bob);
        assertEq(bob_amount, bobReceiptAmount);
        assertEq(0, baseToken.balanceOf(user_bob));

        vm.prank(user_bob);
        vault.rescueDeposit();

        (, aliceReceiptAmount, , ) = vault.depositReceipts(user_alice);
        assertEq(0, aliceReceiptAmount);
        assertEq(alice_amount, baseToken.balanceOf(user_alice));

        (, bobReceiptAmount, , ) = vault.depositReceipts(user_bob);
        assertEq(0, bobReceiptAmount);
        assertEq(bob_amount, baseToken.balanceOf(user_bob));
    }

    /**
     * Verifies that the vault mints a number of shares in exchange for the
     * deposited amounts and that it does so just once.
     */
    function testRollEpochSharesMinting(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit());

        // provide tokens to the user:
        vm.prank(admin);
        baseToken.mint(user, amount);

        // deposit:
        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        // Check pre-conditions:
        assertEq(0, vault.totalSupply());
        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(0, userUnredeemedShares);
        (, , , , , uint256 heldShares, uint256 newHeldShares, , ) = vault.vaultState();
        assertEq(0, heldShares);
        assertEq(0, newHeldShares);

        // The shares are minted when the epoch is rolled
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // Check post-conditions:
        // NOTE: on the initial clean state, the shares are minted on a 1:1 ratio with the deposited amounts.
        uint256 sharePrice = vault.epochPricePerShare(vault.getEpoch().previous);
        assertEq(1 * (10 ** baseToken.decimals()), sharePrice);
        uint256 expectedShares = amount;
        assertEq(expectedShares, vault.totalSupply());
        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(expectedShares, userUnredeemedShares);
        (, , , , , heldShares, newHeldShares, , ) = vault.vaultState();
        assertEq(0, heldShares);
        assertEq(0, newHeldShares);

        // Roll another epoch
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // Check that the shares of the previous deposits weren't minted again:
        assertEq(expectedShares, vault.totalSupply());
        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(expectedShares, userUnredeemedShares);
        (, , , , , heldShares, newHeldShares, , ) = vault.vaultState();
        assertEq(0, heldShares);
        assertEq(0, newHeldShares);
    }

    /**
     * Verifies that the minted shares are well isolated
     * from the point of view of the user wallet.
     */
    function testRollEpochSharesMintingMultipleUsers() public {
        address user_alice = address(123);
        address user_bob = address(456);

        // Alice deposit:
        uint256 alice_amount = 100 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_alice, alice_amount);
        vm.startPrank(user_alice);
        baseToken.approve(address(vault), alice_amount);
        vault.deposit(alice_amount, user_alice, 0);
        vm.stopPrank();

        // Bob deposit:
        uint256 bob_amount = 200 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_bob, bob_amount);
        vm.startPrank(user_bob);
        baseToken.approve(address(vault), bob_amount);
        vault.deposit(bob_amount, user_bob, 0);
        vm.stopPrank();

        // The shares are minted when the epoch is rolled
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 expectedShares = alice_amount + bob_amount;
        assertEq(expectedShares, vault.totalSupply());

        (uint256 aliceShares, uint256 aliceUnredeemedShares) = vault.shareBalances(user_alice);
        assertEq(0, aliceShares);
        assertEq(alice_amount, aliceUnredeemedShares);
        (uint256 bobShares, uint256 bobUnredeemedShares) = vault.shareBalances(user_bob);
        assertEq(0, bobShares);
        assertEq(bob_amount, bobUnredeemedShares);
    }

    function testRollEpochSharesMintingWithVaryingSharePrice(uint256 initialShares, uint256 payoff, uint256 depositAmount) public {
        vm.assume(initialShares > 0);
        vm.assume(payoff > 0);
        vm.assume(depositAmount > 0);
        vm.assume(initialShares < vault.maxDeposit());
        vm.assume(depositAmount <= vault.maxDeposit() - initialShares);
        vm.assume(payoff < initialShares);

        address initialUser = address(123);

        vm.prank(admin);
        baseToken.mint(initialUser, initialShares);

        vm.startPrank(initialUser);
        baseToken.approve(address(vault), initialShares);
        vault.deposit(initialShares, initialUser, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(initialShares, vault.totalSupply());

        vm.startPrank(admin);
        vault.setAllowedDVP(admin);
        vault.reservePayoff(payoff);
        vm.stopPrank();

        vm.prank(admin);
        baseToken.mint(user, depositAmount);
        vm.startPrank(user);
        baseToken.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 sharePrice = vault.epochPricePerShare(vault.getEpoch().previous);
        uint256 expectedSharePrice = (initialShares - payoff) * (10 ** baseToken.decimals()) / initialShares;
        assertEq(expectedSharePrice, sharePrice);
        assertGe(sharePrice, 0);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        uint256 expectedShares = depositAmount * (10 ** baseToken.decimals()) / sharePrice;
        assertEq(expectedShares, userUnredeemedShares);
    }

    function testRescueShares(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        assertEq(0, baseToken.balanceOf(user));
        assertEq(amount, baseToken.balanceOf(address(vault)));

        vm.prank(admin);
        vault.killVault();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(true, vault.dead());

        assertEq(amount, vault.totalSupply());
        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(amount, userUnredeemedShares);

        vm.prank(user);
        vault.rescueShares();

        assertEq(0, vault.totalSupply());
        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(0, userUnredeemedShares);

        assertEq(amount, baseToken.balanceOf(user));
        assertEq(0, baseToken.balanceOf(address(vault)));
    }

    function testRescueSharesWhenNotDead(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        assertEq(false, vault.dead());

        vm.prank(user);
        vm.expectRevert(ERR_VAULT_NOT_DEAD);
        vault.rescueShares();
    }

    function testRescueSharesWhenPaused(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.prank(admin);
        vault.changePauseState();
        assertEq(true, vault.paused());

        // NOTE: the rescue share operation is enabled only if the vault is dead
        vm.prank(admin);
        vault.killVault();
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();
        assertEq(true, vault.dead());

        vm.prank(user);
        vm.expectRevert(ERR_PAUSED);
        vault.rescueShares();
    }

    /**
     * Verifies that the rescue shares operations are well isolated
     * from the point of view of the user wallet.
     */
    function testRescueSharesMultiOperation() public {
        address user_alice = address(123);
        address user_bob = address(456);

        // Alice deposit:
        uint256 alice_amount = 100 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_alice, alice_amount);
        vm.startPrank(user_alice);
        baseToken.approve(address(vault), alice_amount);
        vault.deposit(alice_amount, user_alice, 0);
        vm.stopPrank();

        // Bob deposit:
        uint256 bob_amount = 200 * (10 ** baseToken.decimals());
        vm.prank(admin);
        baseToken.mint(user_bob, bob_amount);
        vm.startPrank(user_bob);
        baseToken.approve(address(vault), bob_amount);
        vault.deposit(bob_amount, user_bob, 0);
        vm.stopPrank();

        vm.prank(admin);
        vault.killVault();

        assertEq(alice_amount + bob_amount, baseToken.balanceOf(address(vault)));

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(alice_amount + bob_amount, vault.totalSupply());

        (uint256 aliceShares, uint256 aliceUnredeemedShares) = vault.shareBalances(user_alice);
        assertEq(0, aliceShares);
        assertEq(alice_amount, aliceUnredeemedShares);

        vm.prank(user_alice);
        vault.rescueShares();

        assertEq(bob_amount, vault.totalSupply());

        (aliceShares, aliceUnredeemedShares) = vault.shareBalances(user_alice);
        assertEq(0, aliceShares);
        assertEq(0, aliceUnredeemedShares);
        assertEq(alice_amount, baseToken.balanceOf(user_alice));

        (uint256 bobShares, uint256 bobUnredeemedShares) = vault.shareBalances(user_bob);
        assertEq(0, bobShares);
        assertEq(bob_amount, bobUnredeemedShares);

        vm.prank(user_bob);
        vault.rescueShares();

        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));

        (bobShares, bobUnredeemedShares) = vault.shareBalances(user_bob);
        assertEq(0, bobShares);
        assertEq(0, bobUnredeemedShares);
        assertEq(bob_amount, baseToken.balanceOf(user_bob));
    }

    function testRescueSharesWhenWithdrawWasRequested(uint256 firstAmount, uint256 secondAmount) public {
        vm.assume(firstAmount > 0);
        vm.assume(secondAmount > 0);
        vm.assume(firstAmount <= type(uint128).max);
        vm.assume(secondAmount <= type(uint128).max);
        vm.assume(firstAmount + secondAmount <= vault.maxDeposit());

        // let the user have x+y shares
        vm.prank(admin);
        baseToken.mint(user, firstAmount + secondAmount);

        vm.startPrank(user);
        baseToken.approve(address(vault), firstAmount + secondAmount);
        vault.deposit(firstAmount + secondAmount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(firstAmount + secondAmount, vault.totalSupply());
        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(firstAmount + secondAmount, userUnredeemedShares);

        // request withdrawal of y shares
        vm.prank(user);
        vault.initiateWithdraw(secondAmount);

        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(firstAmount, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(secondAmount, vault.balanceOf(address(vault)));

        // kill vault
        vm.prank(admin);
        vault.killVault();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(true, vault.dead());

        // rescue shares
        assertEq(firstAmount + secondAmount, vault.totalSupply());
        assertEq(secondAmount, vault.balanceOf(address(vault)));
        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(firstAmount, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vault.rescueShares();

        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));

        assertEq(firstAmount + secondAmount, baseToken.balanceOf(user));
    }

    function testRescueDepositWhenThereAreNoSharesToRescue() public {
        vm.prank(admin);
        vault.killVault();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(user);
        vm.expectRevert(ERR_AMOUNT_ZERO);
        vault.rescueShares();
    }

    function testRedeem(uint256 amount, uint256 shares) public {
        vm.assume(amount > 0);
        vm.assume(amount <= vault.maxDeposit());
        vm.assume(shares <= amount);

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(amount, vault.totalSupply());
        assertEq(0, vault.balanceOf(user));
        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(amount, userUnredeemedShares);
        (, uint256 receiptAmount, uint256 unredeemedShares, ) = vault.depositReceipts(user);
        assertEq(0, unredeemedShares);

        vm.prank(user);
        if (shares == 0) {
            vm.expectRevert(ERR_AMOUNT_ZERO);
        }
        vault.redeem(shares);

        if (shares == 0) {
            return;
        }

        assertEq(amount, vault.totalSupply());
        assertEq(shares, vault.balanceOf(user));
        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(shares, userShares);
        assertEq(amount - shares, userUnredeemedShares);

        // NOTE: when the redeem is an epoch different from the one of the deposit, the receipt is updated
        (, receiptAmount, unredeemedShares, ) = vault.depositReceipts(user);
        assertEq(0, receiptAmount);
        assertEq(amount - shares, unredeemedShares);
    }

    function testRedeemWithSameEpochOfDeposit(uint256 firstAmount, uint256 secondAmount, uint256 shares) public {
        vm.assume(firstAmount > 0);
        vm.assume(secondAmount > 0);
        vm.assume(firstAmount <= type(uint128).max);
        vm.assume(secondAmount <= type(uint128).max);
        vm.assume(firstAmount + secondAmount <= vault.maxDeposit());
        vm.assume(shares > 0);
        vm.assume(shares <= firstAmount);

        vm.prank(admin);
        baseToken.mint(user, firstAmount + secondAmount);

        vm.startPrank(user);
        baseToken.approve(address(vault), firstAmount);
        vault.deposit(firstAmount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(firstAmount, vault.totalSupply());
        assertEq(0, vault.balanceOf(user));
        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(firstAmount, userUnredeemedShares);
        (
            uint256 epoch,
            uint256 receiptAmount,
            uint256 unredeemedShares,
            uint256 cumulativeAmount
        ) = vault.depositReceipts(user);
        assertEq(vault.getEpoch().previous, epoch);
        assertEq(firstAmount, receiptAmount);
        assertEq(0, unredeemedShares); // NOTE: the receipt has not been updated yet; we can see the shares from the balances
        assertEq(firstAmount, cumulativeAmount);

        // Second deposit; in a different epoch
        vm.startPrank(user);
        baseToken.approve(address(vault), secondAmount);
        vault.deposit(secondAmount, user, 0);
        vm.stopPrank();

        // Now the deposit receipt has been updated
        (
            epoch,
            receiptAmount,
            unredeemedShares,
            cumulativeAmount
        ) = vault.depositReceipts(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(secondAmount, receiptAmount);
        assertEq(firstAmount, unredeemedShares);
        assertEq(firstAmount + secondAmount, cumulativeAmount);

        vm.prank(user);
        vault.redeem(shares);

        assertEq(firstAmount, vault.totalSupply());
        assertEq(shares, vault.balanceOf(user));
        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(shares, userShares);
        assertEq(firstAmount - shares, userUnredeemedShares);

        (, receiptAmount, unredeemedShares, ) = vault.depositReceipts(user);
        assertEq(secondAmount, receiptAmount);
        assertEq(firstAmount - shares, unredeemedShares);
    }

    function testRedeemWhenSharesExceedsAvailableOnes(uint256 shares, uint256 sharesToRedeem) public {
        vm.assume(shares > 0);
        vm.assume(shares <= vault.maxDeposit());
        vm.assume(sharesToRedeem > shares);

        vm.prank(admin);
        baseToken.mint(user, shares);

        vm.startPrank(user);
        baseToken.approve(address(vault), shares);
        vault.deposit(shares, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(shares, userShares + userUnredeemedShares);

        vm.prank(user);
        vm.expectRevert(ERR_EXCEEDS_AVAILABLE);
        vault.redeem(sharesToRedeem);
    }

    function testRedeemWhenPaused(uint256 shares) public {
        vm.assume(shares > 0);
        vm.assume(shares <= vault.maxDeposit());

         vm.prank(admin);
        baseToken.mint(user, shares);

        vm.startPrank(user);
        baseToken.approve(address(vault), shares);
        vault.deposit(shares, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        vault.changePauseState();

        vm.prank(user);
        vm.expectRevert(ERR_PAUSED);
        vault.redeem(shares);
    }

    function testInitiateWithdraw(uint256 shares) public {
        vm.assume(shares > 0);
        vm.assume(shares <= vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, shares);

        vm.startPrank(user);
        baseToken.approve(address(vault), shares);
        vault.deposit(shares, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(user);
        vault.redeem(shares);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(shares, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(shares, vault.balanceOf(user));
        assertEq(0, vault.balanceOf(address(vault)));

        (, , , , uint256 totalDeposit, , uint256 newHeldShares , , ) = vault.vaultState();
        assertEq(shares, totalDeposit);
        assertEq(0, newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(0, epoch);
        assertEq(0, withdrawalShares);

        (, , , uint256 cumulativeAmount) = vault.depositReceipts(user);
        assertEq(shares, cumulativeAmount);

        vm.prank(user);
        vault.initiateWithdraw(shares);

        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(0, vault.balanceOf(user));
        assertEq(shares, vault.balanceOf(address(vault)));
        (, , , cumulativeAmount) = vault.depositReceipts(user);
        assertEq(0, cumulativeAmount);

        (, , , , totalDeposit, , newHeldShares , , ) = vault.vaultState();
        assertEq(0, totalDeposit);
        assertEq(shares, newHeldShares);

        (epoch, withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(shares, withdrawalShares);
    }

    function testInitiateWithdrawWhenPaused(uint256 shares) public {
        vm.prank(admin);
        vault.changePauseState();

        vm.prank(user);
        vm.expectRevert(ERR_PAUSED);
        vault.initiateWithdraw(shares);
    }

    function testInitiateWithdrawWhenEpochFinished(uint256 shares) public {
        vm.assume(shares > 0);
        vm.assume(shares <= vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, shares);

        vm.startPrank(user);
        baseToken.approve(address(vault), shares);
        vault.deposit(shares, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(user);
        vault.redeem(shares);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(user);
        vm.expectRevert(ERR_EPOCH_FINISHED);
        vault.initiateWithdraw(shares);
    }

}