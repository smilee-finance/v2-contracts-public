// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {VaultLib} from "@project/lib/VaultLib.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {Utils} from "../utils/Utils.sol";
import {VaultUtils} from "../utils/VaultUtils.sol";
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
    TestnetPriceOracle priceOracle;

    Vault vault;

    bytes4 public constant ERR_AMOUNT_ZERO = bytes4(keccak256("AmountZero()"));
    bytes4 public constant ERR_AMOUNT_NOT_ALLOWED = bytes4(keccak256("AmountNotAllowed()"));
    bytes4 public constant ERR_EXCEEDS_MAX_DEPOSIT = bytes4(keccak256("ExceedsMaxDeposit()"));
    bytes4 public constant ERR_EPOCH_FINISHED = bytes4(keccak256("EpochFinished()"));
    bytes4 public constant ERR_VAULT_DEAD = bytes4(keccak256("VaultDead()"));
    bytes4 public constant ERR_VAULT_NOT_DEAD = bytes4(keccak256("VaultNotDead()"));
    bytes4 public constant ERR_NOTHING_TO_RESCUE = bytes4(keccak256("NothingToRescue()"));
    bytes4 public constant ERR_MANUALLY_KILLED = bytes4(keccak256("ManuallyKilled()"));
    bytes4 public constant ERR_EXCEEDS_AVAILABLE = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 public constant ERR_EXISTING_INCOMPLETE_WITHDRAW = bytes4(keccak256("ExistingIncompleteWithdraw()"));
    bytes4 public constant ERR_WITHDRAW_NOT_INITIATED = bytes4(keccak256("WithdrawNotInitiated()"));
    bytes4 public constant ERR_WITHDRAW_TOO_EARLY = bytes4(keccak256("WithdrawTooEarly()"));
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
        priceOracle = new TestnetPriceOracle(address(baseToken));
        priceOracle.setTokenPrice(address(sideToken), 1e18);
        addressProvider.setPriceOracle(address(priceOracle));

        TestnetSwapAdapter exchange = new TestnetSwapAdapter(addressProvider.priceOracle());
        addressProvider.setExchangeAdapter(address(exchange));

        // No fees by default:
        FeeManager feeManager = new FeeManager(address(addressProvider), 0);
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
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.pendingDeposits);
        assertEq(0, state.liquidity.totalDeposit);
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
        if (amount > 0 && amount < 10 ** baseToken.decimals()) {
            vm.expectRevert(ERR_AMOUNT_NOT_ALLOWED);
        }
        if (amount > maxDeposit) {
            vm.expectRevert(ERR_EXCEEDS_MAX_DEPOSIT);
        }
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        if (amount < 10 ** baseToken.decimals() || amount > maxDeposit) {
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
        state = VaultUtils.getState(vault);
        assertEq(amount, state.liquidity.pendingDeposits);
        assertEq(amount, state.liquidity.totalDeposit);
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
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(expected_total_amount, state.liquidity.pendingDeposits);
        assertEq(expected_total_amount, state.liquidity.totalDeposit);
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
        firstAmount = Utils.boundFuzzedValueToRange(firstAmount, 10**baseToken.decimals(), vault.maxDeposit());

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

    /**
     * Verifies that the vault mints a number of shares in exchange for the
     * deposited amounts and that it does so just once.
     */
    function testRollEpochSharesMinting(uint256 amount) public {
        amount = Utils.boundFuzzedValueToRange(amount, 10**baseToken.decimals(), vault.maxDeposit());

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
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

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
        state = VaultUtils.getState(vault);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        // Roll another epoch
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // Check that the shares of the previous deposits weren't minted again:
        assertEq(expectedShares, vault.totalSupply());
        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(expectedShares, userUnredeemedShares);
        state = VaultUtils.getState(vault);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);
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

    // TODO: review as it reverts with InsufficientLiquidity() when [569600064474895, 569600064467820, 2265]
    // TODO: review as it reverts with InsufficientLiquidity(0x033fb0b000000000000000000000000000000000000000000000000000000000) when [281852532946200, 281852531394638, 19583]
    function testRollEpochSharesMintingWithVaryingSharePrice(uint256 initialShares, uint256 payoff, uint256 depositAmount) public {
        vm.assume(initialShares > 0);
        vm.assume(payoff > 0);
        vm.assume(depositAmount > 0);
        vm.assume(initialShares < vault.maxDeposit());
        vm.assume(depositAmount <= vault.maxDeposit() - initialShares);
        vm.assume(payoff < initialShares);
        initialShares = Utils.boundFuzzedValueToRange(initialShares, 10**baseToken.decimals(), vault.maxDeposit());

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
        amount = Utils.boundFuzzedValueToRange(amount, 10**baseToken.decimals(), vault.maxDeposit());

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

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(true, state.dead);

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
        amount = Utils.boundFuzzedValueToRange(amount, 10**baseToken.decimals(), vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(false, state.dead);

        vm.prank(user);
        vm.expectRevert(ERR_VAULT_NOT_DEAD);
        vault.rescueShares();
    }

    function testRescueSharesWhenPaused(uint256 amount) public {
        amount = Utils.boundFuzzedValueToRange(amount, 10**baseToken.decimals(), vault.maxDeposit());

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
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(true, state.dead);

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
        firstAmount = Utils.boundFuzzedValueToRange(firstAmount, 10**baseToken.decimals(), vault.maxDeposit());
        vm.assume(secondAmount > 0);
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

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(true, state.dead);

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

    function testRescueSharesWhenThereAreNoSharesToRescue() public {
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
        amount = Utils.boundFuzzedValueToRange(amount, 10**baseToken.decimals(), vault.maxDeposit());
        shares = Utils.boundFuzzedValueToRange(shares, 10**baseToken.decimals(), amount);

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
        firstAmount = Utils.boundFuzzedValueToRange(firstAmount, 10**baseToken.decimals(), vault.maxDeposit());
        secondAmount = Utils.boundFuzzedValueToRange(secondAmount, 10**baseToken.decimals(), vault.maxDeposit());
        shares = Utils.boundFuzzedValueToRange(shares, 10**baseToken.decimals(), firstAmount);
        vm.assume(firstAmount + secondAmount <= vault.maxDeposit());

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
        shares = Utils.boundFuzzedValueToRange(shares, 10**baseToken.decimals(), vault.maxDeposit());
        sharesToRedeem = Utils.boundFuzzedValueToRange(sharesToRedeem, shares + 1, vault.maxDeposit());

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
        vm.assume(shares > 10 ** baseToken.decimals());
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

    /**
     *
     */
    function testInitiateWithdraw(uint256 shares) public {
        shares = Utils.boundFuzzedValueToRange(shares, 10**baseToken.decimals(), vault.maxDeposit());

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

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(shares, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.newHeldShares);

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

        state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.totalDeposit);
        assertEq(shares, state.withdrawals.newHeldShares);

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
        shares = Utils.boundFuzzedValueToRange(shares, 10**baseToken.decimals(), vault.maxDeposit());
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

    function testInitiateWithdrawWithZeroShares(uint256 amount) public {
        vm.assume(amount > 10 ** baseToken.decimals());
        vm.assume(amount <= vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(user);
        vault.redeem(amount);

        vm.prank(user);
        vm.expectRevert(ERR_AMOUNT_ZERO);
        vault.initiateWithdraw(0);
    }

    function testInitiateWithdrawWithTooMuchShares(uint256 shares) public {
        shares = Utils.boundFuzzedValueToRange(shares, 10**baseToken.decimals(), vault.maxDeposit());

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

        vm.prank(user);
        vm.expectRevert(ERR_EXCEEDS_AVAILABLE);
        vault.initiateWithdraw(shares + 1);
    }

    function testInitiateWithdrawWhenThereAreUnredeemedShares(uint256 totalShares, uint256 shares) public {
        totalShares = Utils.boundFuzzedValueToRange(totalShares, 10**baseToken.decimals(), vault.maxDeposit());
        shares = Utils.boundFuzzedValueToRange(shares, 1, totalShares);
        vm.assume(shares < totalShares);
        vm.assume(totalShares - 10 ** baseToken.decimals() > shares);

        vm.prank(admin);
        baseToken.mint(user, totalShares);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalShares);
        vault.deposit(totalShares, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(user);
        vault.redeem(shares);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(shares, userShares);
        assertEq(totalShares - shares, userUnredeemedShares);
        assertEq(shares, vault.balanceOf(user));
        assertEq(totalShares - shares, vault.balanceOf(address(vault)));

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(totalShares, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(0, epoch);
        assertEq(0, withdrawalShares);

        (, , , uint256 cumulativeAmount) = vault.depositReceipts(user);
        assertEq(totalShares, cumulativeAmount);

        vm.prank(user);
        vault.initiateWithdraw(shares);

        // Side effect: any unredeemed share has been transferred to the user
        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalShares - shares, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalShares - shares, vault.balanceOf(user));
        assertEq(shares, vault.balanceOf(address(vault)));
        (, , , cumulativeAmount) = vault.depositReceipts(user);
        assertEq(totalShares - shares, cumulativeAmount);

        state = VaultUtils.getState(vault);
        assertEq(totalShares - shares, state.liquidity.totalDeposit);
        assertEq(shares, state.withdrawals.newHeldShares);

        (epoch, withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(shares, withdrawalShares);
    }

    // Test initiate withdraw when there is another one not completed in the current epoch
    function testInitiateWithdrawMultipleSameEpoch(uint256 totalShares, uint256 firstWithdraw, uint256 secondWithdraw) public {
        totalShares = Utils.boundFuzzedValueToRange(totalShares, 2 * 10**baseToken.decimals(), vault.maxDeposit());
        firstWithdraw = Utils.boundFuzzedValueToRange(firstWithdraw, 10**baseToken.decimals(), totalShares / 2);
        secondWithdraw = totalShares - firstWithdraw;
        vm.assume(firstWithdraw + secondWithdraw <= totalShares);

        vm.prank(admin);
        baseToken.mint(user, totalShares);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalShares);
        vault.deposit(totalShares, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(user);
        vault.redeem(totalShares);

        VaultUtils.logState(vault);

        vm.prank(user);
        vault.initiateWithdraw(firstWithdraw);

        VaultUtils.logState(vault);
        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalShares - firstWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalShares - firstWithdraw, vault.balanceOf(user));
        assertEq(firstWithdraw, vault.balanceOf(address(vault)));
        (, , , uint256 cumulativeAmount) = vault.depositReceipts(user);
        assertEq(totalShares - firstWithdraw, cumulativeAmount); // Assert error!

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(totalShares - firstWithdraw, state.liquidity.totalDeposit);
        assertEq(firstWithdraw, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(firstWithdraw, withdrawalShares);

        vm.prank(user);
        vault.initiateWithdraw(secondWithdraw);

        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalShares - firstWithdraw - secondWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalShares - firstWithdraw - secondWithdraw, vault.balanceOf(user));
        assertEq(firstWithdraw + secondWithdraw, vault.balanceOf(address(vault)));
        (, , , cumulativeAmount) = vault.depositReceipts(user);
        assertEq(totalShares - firstWithdraw - secondWithdraw, cumulativeAmount);

        state = VaultUtils.getState(vault);
        assertEq(totalShares - firstWithdraw - secondWithdraw, state.liquidity.totalDeposit);
        assertEq(firstWithdraw + secondWithdraw, state.withdrawals.newHeldShares);

        (epoch, withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(firstWithdraw + secondWithdraw, withdrawalShares);
    }

    // Test initiate withdraw when there is another one not completed in another epoch (revert)
    function testInitiateWithdrawMultipleDifferentEpoch(uint256 totalShares, uint256 firstWithdraw, uint256 secondWithdraw) public {
        totalShares = Utils.boundFuzzedValueToRange(totalShares, 10**baseToken.decimals(), vault.maxDeposit());
        vm.assume(firstWithdraw > 0);
        vm.assume(firstWithdraw <= type(uint128).max);
        vm.assume(secondWithdraw > 0);
        vm.assume(secondWithdraw <= type(uint128).max);
        vm.assume(firstWithdraw + secondWithdraw <= totalShares -  10**baseToken.decimals());


        vm.prank(admin);
        baseToken.mint(user, totalShares);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalShares);
        vault.deposit(totalShares, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(user);
        vault.redeem(totalShares);

        vm.prank(user);
        vault.initiateWithdraw(firstWithdraw);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(user);
        vm.expectRevert(ERR_EXISTING_INCOMPLETE_WITHDRAW);
        vault.initiateWithdraw(secondWithdraw);
    }

    // Test initiate withdraw when there is a deposit in the current epoch (vault capacity and deposit receipt checks)
    function testInitiateWithdrawWhenDepositedInCurrentEpoch() public {
        uint256 firstDeposit = 100 * (10 ** baseToken.decimals());
        uint256 secondDeposit = 50 * (10 ** baseToken.decimals());

        vm.prank(admin);
        baseToken.mint(user, firstDeposit + secondDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), firstDeposit);
        vault.deposit(firstDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.startPrank(user);
        vault.redeem(firstDeposit);

        baseToken.approve(address(vault), secondDeposit);
        vault.deposit(secondDeposit, user, 0);
        vm.stopPrank();

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(firstDeposit, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(firstDeposit, vault.balanceOf(user));
        assertEq(0, vault.balanceOf(address(vault)));

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(firstDeposit + secondDeposit, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(0, epoch);
        assertEq(0, withdrawalShares);

        (, , , uint256 cumulativeAmount) = vault.depositReceipts(user);
        assertEq(firstDeposit + secondDeposit, cumulativeAmount);

        vm.prank(user);
        vault.initiateWithdraw(firstDeposit);

        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(0, vault.balanceOf(user));
        assertEq(firstDeposit, vault.balanceOf(address(vault)));

        state = VaultUtils.getState(vault);
        assertEq(secondDeposit, state.liquidity.totalDeposit);
        assertEq(firstDeposit, state.withdrawals.newHeldShares);

        (epoch, withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(firstDeposit, withdrawalShares);

        (, , , cumulativeAmount) = vault.depositReceipts(user);
        assertEq(secondDeposit, cumulativeAmount);
    }

    function testInitiateWithdrawWhenDead(uint256 shares) public {
        vm.assume(shares > 10 ** baseToken.decimals());
        vm.assume(shares <= vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, shares);

        vm.startPrank(user);
        baseToken.approve(address(vault), shares);
        vault.deposit(shares, user, 0);
        vm.stopPrank();

        vm.prank(admin);
        vault.killVault();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(true, state.dead);

        vm.prank(user);
        vault.redeem(shares);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(shares, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(shares, vault.balanceOf(user));
        assertEq(0, vault.balanceOf(address(vault)));

        state = VaultUtils.getState(vault);
        assertEq(shares, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(0, epoch);
        assertEq(0, withdrawalShares);

        (, , , uint256 cumulativeAmount) = vault.depositReceipts(user);
        assertEq(shares, cumulativeAmount);

        vm.prank(user);
        vm.expectRevert(ERR_VAULT_DEAD);
        vault.initiateWithdraw(shares);
    }

    // Test complete withdraw (requested in the previous epoch) without removing all the liquidity
    function testCompleteWithdraw(uint256 totalDeposit, uint256 sharesToWithdraw, uint256 sideTokenPrice) public {
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 10 ** baseToken.decimals(), vault.maxDeposit() - 1);
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10**baseToken.decimals(), vault.maxDeposit());
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);
        vm.assume(sharesToWithdraw < totalDeposit);
        vm.assume(totalDeposit - sharesToWithdraw > 10**baseToken.decimals());


        // User deposit (and later withdraw) a given amount
        vm.prank(admin);
        baseToken.mint(user, sharesToWithdraw);

        vm.startPrank(user);
        baseToken.approve(address(vault), sharesToWithdraw);
        vault.deposit(sharesToWithdraw, user, 0);
        vm.stopPrank();

        // Another user deposit another amount so that the main one doesn't withdraw everything
        address other_user = address(2);
        uint256 other_user_deposit = totalDeposit - sharesToWithdraw;
        vm.prank(admin);
        baseToken.mint(other_user, other_user_deposit);
        vm.startPrank(other_user);
        baseToken.approve(address(vault), other_user_deposit);
        vault.deposit(other_user_deposit, other_user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The test user initiate a withdraw of all of its shares

        vm.prank(user);
        vault.redeem(sharesToWithdraw);

        vm.prank(user);
        vault.initiateWithdraw(sharesToWithdraw);

        // The side token price is moved in order to also move the price per share

        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: pre-computed for the current epoch
        uint256 expectedSharePrice = vault.notional() * 10**baseToken.decimals() / vault.totalSupply();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 sharePrice = vault.epochPricePerShare(vault.getEpoch().previous);
        assertEq(sharePrice, expectedSharePrice);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(0, vault.balanceOf(user));

        assertEq(totalDeposit, vault.balanceOf(address(vault)));
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        uint256 expectedAmount = (sharesToWithdraw * sharePrice) / (10 ** baseToken.decimals());
        assertEq(expectedAmount, state.liquidity.pendingWithdrawals);
        assertEq(other_user_deposit, state.liquidity.totalDeposit);
        assertEq(sharesToWithdraw, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().previous, epoch);
        assertEq(sharesToWithdraw, withdrawalShares);

        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vault.completeWithdraw();

        state = VaultUtils.getState(vault);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(other_user_deposit, vault.balanceOf(address(vault)));

        (, withdrawalShares) = vault.withdrawals(user);
        assertEq(0, withdrawalShares);

        assertEq(0, state.liquidity.pendingWithdrawals);

        assertEq(expectedAmount, baseToken.balanceOf(user));
    }

    // Test complete withdraw where the user do not withdraw all of its shares
    function testCompleteWithdrawPartialBalance(uint256 totalDeposit, uint256 sharesToWithdraw, uint256 sideTokenPrice) public {
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10**baseToken.decimals(), vault.maxDeposit());
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 1, totalDeposit);
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);
        vm.assume(sharesToWithdraw < totalDeposit);
        vm.assume(totalDeposit - sharesToWithdraw > 10**baseToken.decimals());

        // User deposit (and later withdraw) a given amount
        vm.prank(admin);
        baseToken.mint(user, totalDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalDeposit);
        vault.deposit(totalDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The user initiate a withdraw
        vm.prank(user);
        vault.redeem(sharesToWithdraw);

        vm.prank(user);
        vault.initiateWithdraw(sharesToWithdraw);

        // The side token price is moved in order to also move the price per share
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: pre-computed for the current epoch
        uint256 expectedSharePrice = vault.notional() * 10**baseToken.decimals() / vault.totalSupply();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 sharePrice = vault.epochPricePerShare(vault.getEpoch().previous);
        assertEq(sharePrice, expectedSharePrice);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalDeposit - sharesToWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));

        assertEq(sharesToWithdraw, vault.balanceOf(address(vault)));
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        uint256 expectedAmount = (sharesToWithdraw * sharePrice) / (10 ** baseToken.decimals());
        assertEq(state.liquidity.pendingWithdrawals, expectedAmount);
        assertEq(totalDeposit - sharesToWithdraw, state.liquidity.totalDeposit);
        assertEq(sharesToWithdraw, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().previous, epoch);
        assertEq(sharesToWithdraw, withdrawalShares);

        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vault.completeWithdraw();

        state = VaultUtils.getState(vault);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, vault.balanceOf(address(vault)));

        (, withdrawalShares) = vault.withdrawals(user);
        assertEq(0, withdrawalShares);

        assertEq(0, state.liquidity.pendingWithdrawals);

        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalDeposit - sharesToWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));

        assertEq(expectedAmount, baseToken.balanceOf(user));
    }

    // Test complete withdraw (requested more than one epoch ago) without removing all the liquidity
    function testCompleteWithdrawAfterMoreThanOneEpoch(uint256 totalDeposit, uint256 sharesToWithdraw, uint256 sideTokenPrice) public {
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10**baseToken.decimals(), vault.maxDeposit());
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 1, totalDeposit);
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);
        vm.assume(sharesToWithdraw < totalDeposit);
        vm.assume(totalDeposit - sharesToWithdraw > 10**baseToken.decimals());

        // User deposit (and later withdraw) a given amount
        vm.prank(admin);
        baseToken.mint(user, totalDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalDeposit);
        vault.deposit(totalDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The user initiate a withdraw
        vm.prank(user);
        vault.redeem(sharesToWithdraw);

        vm.prank(user);
        vault.initiateWithdraw(sharesToWithdraw);

        // The side token price is moved in order to also move the price per share
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: pre-computed for the current epoch
        uint256 expectedSharePrice = vault.notional() * 10**baseToken.decimals() / vault.totalSupply();

        uint256 maturityAtWithdraw = vault.getEpoch().current;

        vm.warp(maturityAtWithdraw + 1);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 sharePrice = vault.epochPricePerShare(maturityAtWithdraw);
        assertEq(sharePrice, expectedSharePrice);

        // NOTE: nothing needs to happens in between

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // NOTE: avoid stack too deep
        {
            (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
            assertEq(totalDeposit - sharesToWithdraw, userShares);
            assertEq(0, userUnredeemedShares);
            assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));
        }

        uint256 expectedAmount = (sharesToWithdraw * sharePrice) / (10 ** baseToken.decimals());
        // NOTE: avoid stack too deep
        assertEq(sharesToWithdraw, vault.balanceOf(address(vault)));
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(expectedAmount, state.liquidity.pendingWithdrawals);
        assertEq(totalDeposit - sharesToWithdraw, state.liquidity.totalDeposit);
        assertEq(sharesToWithdraw, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(maturityAtWithdraw, epoch);
        assertEq(sharesToWithdraw, withdrawalShares);

        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vault.completeWithdraw();

        state = VaultUtils.getState(vault);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, vault.balanceOf(address(vault)));

        (, withdrawalShares) = vault.withdrawals(user);
        assertEq(0, withdrawalShares);

        assertEq(0, state.liquidity.pendingWithdrawals);

        // NOTE: avoid stack too deep
        {
            (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
            assertEq(totalDeposit - sharesToWithdraw, userShares);
            assertEq(0, userUnredeemedShares);
            assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));
        }

        assertEq(expectedAmount, baseToken.balanceOf(user));
    }

    // Test complete withdraw with all the liquidity withdrawed
    function testCompleteWithdrawNoLiquidityLeft(uint256 totalDeposit, uint256 sideTokenPrice) public {
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10**baseToken.decimals(), vault.maxDeposit());
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);

        // User deposit (and later withdraw) a given amount
        vm.prank(admin);
        baseToken.mint(user, totalDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalDeposit);
        vault.deposit(totalDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The user initiate a withdraw
        vm.prank(user);
        vault.redeem(totalDeposit);

        vm.prank(user);
        vault.initiateWithdraw(totalDeposit);

        // The side token price is moved in order to also move the price per share
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: pre-computed for the current epoch
        uint256 expectedSharePrice = vault.notional() * 10**baseToken.decimals() / vault.totalSupply();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 sharePrice = vault.epochPricePerShare(vault.getEpoch().previous);
        assertEq(sharePrice, expectedSharePrice);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(0, vault.balanceOf(user));

        assertEq(totalDeposit, vault.balanceOf(address(vault)));
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        uint256 expectedAmount = (totalDeposit * sharePrice) / (10 ** baseToken.decimals());
        assertGt(expectedAmount, 0);
        assertEq(expectedAmount, state.liquidity.pendingWithdrawals);
        assertEq(0, state.liquidity.totalDeposit);
        assertEq(totalDeposit, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().previous, epoch);
        assertEq(totalDeposit, withdrawalShares);

        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vault.completeWithdraw();

        state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, vault.balanceOf(address(vault)));

        (, withdrawalShares) = vault.withdrawals(user);
        assertEq(0, withdrawalShares);

        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(0, vault.balanceOf(user));

        assertEq(expectedAmount, baseToken.balanceOf(user));
    }

    // Test complete withdraw when the vault dies (after the request)
    function testCompleteWithdrawWhenDead(uint256 totalDeposit, uint256 sharesToWithdraw, uint256 sideTokenPrice) public {
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10**baseToken.decimals(), vault.maxDeposit());
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 1, totalDeposit);
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);
        vm.assume(sharesToWithdraw < totalDeposit);
        vm.assume(totalDeposit - sharesToWithdraw > 10**baseToken.decimals());



        // User deposit (and later withdraw) a given amount
        vm.prank(admin);
        baseToken.mint(user, totalDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalDeposit);
        vault.deposit(totalDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The user initiate a withdraw
        vm.prank(user);
        vault.redeem(sharesToWithdraw);

        vm.prank(user);
        vault.initiateWithdraw(sharesToWithdraw);

        // The side token price is moved in order to also move the price per share
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: pre-computed for the current epoch
        uint256 expectedSharePrice = vault.notional() * 10**baseToken.decimals() / vault.totalSupply();

        vm.prank(admin);
        vault.killVault();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        VaultLib.VaultState memory state = VaultUtils.getState(vault);

        assertEq(true, state.dead);

        uint256 sharePrice = vault.epochPricePerShare(vault.getEpoch().previous);
        assertEq(sharePrice, expectedSharePrice);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalDeposit - sharesToWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));

        assertEq(sharesToWithdraw, vault.balanceOf(address(vault)));
        uint256 expectedAmount = (sharesToWithdraw * sharePrice) / (10 ** baseToken.decimals());
        assertEq(state.liquidity.pendingWithdrawals, expectedAmount);
        assertEq(totalDeposit - sharesToWithdraw, state.liquidity.totalDeposit);
        assertEq(sharesToWithdraw, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().previous, epoch);
        assertEq(sharesToWithdraw, withdrawalShares);

        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vault.completeWithdraw();

        state = VaultUtils.getState(vault);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, vault.balanceOf(address(vault)));

        (, withdrawalShares) = vault.withdrawals(user);
        assertEq(0, withdrawalShares);

        assertEq(0, state.liquidity.pendingWithdrawals);

        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalDeposit - sharesToWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));

        assertEq(expectedAmount, baseToken.balanceOf(user));
    }

    // Test complete withdraw when the vault is paused (revert)
    function testCompleteWithdrawWhenPaused(uint256 totalDeposit, uint256 sharesToWithdraw, uint256 sideTokenPrice) public {
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10**baseToken.decimals(), vault.maxDeposit());
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 1, totalDeposit);
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);
        vm.assume(sharesToWithdraw < totalDeposit);
        vm.assume(totalDeposit - sharesToWithdraw > 10**baseToken.decimals());

        // User deposit (and later withdraw) a given amount
        vm.prank(admin);
        baseToken.mint(user, totalDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalDeposit);
        vault.deposit(totalDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The user initiate a withdraw
        vm.prank(user);
        vault.redeem(sharesToWithdraw);

        vm.prank(user);
        vault.initiateWithdraw(sharesToWithdraw);

        // The side token price is moved in order to also move the price per share
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: pre-computed for the current epoch
        uint256 expectedSharePrice = vault.notional() * 10**baseToken.decimals() / vault.totalSupply();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        vault.changePauseState();

        VaultLib.VaultState memory state = VaultUtils.getState(vault);

        assertEq(true, vault.paused());

        uint256 sharePrice = vault.epochPricePerShare(vault.getEpoch().previous);
        assertEq(sharePrice, expectedSharePrice);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalDeposit - sharesToWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));

        assertEq(sharesToWithdraw, vault.balanceOf(address(vault)));
        uint256 expectedAmount = (sharesToWithdraw * sharePrice) / (10 ** baseToken.decimals());
        assertEq(state.liquidity.pendingWithdrawals, expectedAmount);
        assertEq(totalDeposit - sharesToWithdraw, state.liquidity.totalDeposit);
        assertEq(sharesToWithdraw, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().previous, epoch);
        assertEq(sharesToWithdraw, withdrawalShares);

        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vm.expectRevert(ERR_PAUSED);
        vault.completeWithdraw();
    }

    // Test complete withdraw when not initiated (revert)
    function testCompleteWithdrawWhenNotInitiated(uint256 totalDeposit) public {
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10 ** baseToken.decimals(), vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, totalDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalDeposit);
        vault.deposit(totalDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(0, userShares);
        assertEq(totalDeposit, userUnredeemedShares);
        assertEq(0, vault.balanceOf(user));
        assertEq(totalDeposit, vault.balanceOf(address(vault)));

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(totalDeposit, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(0, epoch);
        assertEq(0, withdrawalShares);

        vm.prank(user);
        vm.expectRevert(ERR_WITHDRAW_NOT_INITIATED);
        vault.completeWithdraw();
    }

    // Test complete withdraw when its epoch is not passed (revert)
    function testCompleteWithdrawWhenWithdrawWasRequested(uint256 totalDeposit, uint256 sharesToWithdraw) public {
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10**baseToken.decimals(), vault.maxDeposit());
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 1, totalDeposit);
        vm.assume(sharesToWithdraw < totalDeposit);
        vm.assume(totalDeposit - sharesToWithdraw > 10**baseToken.decimals());

        // User deposit (and later withdraw) a given amount
        vm.prank(admin);
        baseToken.mint(user, totalDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalDeposit);
        vault.deposit(totalDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The user initiate a withdraw
        vm.prank(user);
        vault.redeem(sharesToWithdraw);

        vm.prank(user);
        vault.initiateWithdraw(sharesToWithdraw);

        VaultLib.VaultState memory state = VaultUtils.getState(vault);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalDeposit - sharesToWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));
        assertEq(sharesToWithdraw, vault.balanceOf(address(vault)));
        assertEq(0, state.withdrawals.heldShares);
        assertEq(sharesToWithdraw, state.withdrawals.newHeldShares);

        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(totalDeposit - sharesToWithdraw, state.liquidity.totalDeposit);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(sharesToWithdraw, withdrawalShares);

        vm.prank(user);
        vm.expectRevert(ERR_WITHDRAW_TOO_EARLY);
        vault.completeWithdraw();
    }

    // Test complete withdraw when already completed (revert)
    function testCompleteWithdrawRepeated(uint256 totalDeposit, uint256 sharesToWithdraw, uint256 sideTokenPrice) public {
        totalDeposit = Utils.boundFuzzedValueToRange(totalDeposit, 10**baseToken.decimals(), vault.maxDeposit());
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 1, totalDeposit);
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);
        vm.assume(sharesToWithdraw < totalDeposit);
        vm.assume(totalDeposit - sharesToWithdraw > 10**baseToken.decimals());

        // User deposit (and later withdraw) a given amount
        vm.prank(admin);
        baseToken.mint(user, totalDeposit);

        vm.startPrank(user);
        baseToken.approve(address(vault), totalDeposit);
        vault.deposit(totalDeposit, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        // The user initiate a withdraw
        vm.prank(user);
        vault.redeem(sharesToWithdraw);

        vm.prank(user);
        vault.initiateWithdraw(sharesToWithdraw);

        // The side token price is moved in order to also move the price per share
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: pre-computed for the current epoch
        uint256 expectedSharePrice = vault.notional() * 10**baseToken.decimals() / vault.totalSupply();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 sharePrice = vault.epochPricePerShare(vault.getEpoch().previous);
        assertEq(sharePrice, expectedSharePrice);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalDeposit - sharesToWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));

        assertEq(sharesToWithdraw, vault.balanceOf(address(vault)));
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        uint256 expectedAmount = (sharesToWithdraw * sharePrice) / (10 ** baseToken.decimals());
        assertEq(state.liquidity.pendingWithdrawals, expectedAmount);
        assertEq(totalDeposit - sharesToWithdraw, state.liquidity.totalDeposit);
        assertEq(sharesToWithdraw, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(user);
        assertEq(vault.getEpoch().previous, epoch);
        assertEq(sharesToWithdraw, withdrawalShares);

        assertEq(0, baseToken.balanceOf(user));

        vm.prank(user);
        vault.completeWithdraw();

        state = VaultUtils.getState(vault);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, vault.balanceOf(address(vault)));

        (, withdrawalShares) = vault.withdrawals(user);
        assertEq(0, withdrawalShares);

        assertEq(0, state.liquidity.pendingWithdrawals);

        (userShares, userUnredeemedShares) = vault.shareBalances(user);
        assertEq(totalDeposit - sharesToWithdraw, userShares);
        assertEq(0, userUnredeemedShares);
        assertEq(totalDeposit - sharesToWithdraw, vault.balanceOf(user));

        assertEq(expectedAmount, baseToken.balanceOf(user));

        vm.prank(user);
        vm.expectRevert(ERR_WITHDRAW_NOT_INITIATED);
        vault.completeWithdraw();
    }

    // [TBD] test complete withdraw when the liquidity is set aside for payoffs


    // Test exchanging shares does not damage the vault totalDeposit counter when receiver withdraws
    function testSharesExchange(uint256 deposit, uint256 sharesToWithdraw) public {
        uint256 baseAmount = _firstDeposit();

        deposit = Utils.boundFuzzedValueToRange(deposit, 1, vault.maxDeposit() - baseAmount);
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 1, deposit);

        address depositor = address(0x10000);
        address secondWallet = address(0x20000);

        _deposit(depositor, deposit);
        _roll();
        _transferShares(depositor, secondWallet);

        vm.prank(secondWallet);
        vault.initiateWithdraw(sharesToWithdraw);

        VaultLib.VaultState memory state = VaultUtils.getState(vault);

        (uint256 depositorShares, uint256 depositorUnredeemedShares) = vault.shareBalances(depositor);
        (uint256 secondWalletShares, uint256 secondWalletUnredeemedShares) = vault.shareBalances(secondWallet);
        assertEq(0, depositorShares);
        assertEq(0, depositorUnredeemedShares);
        assertEq(deposit - sharesToWithdraw, secondWalletShares);
        assertEq(0, secondWalletUnredeemedShares);
        assertEq(deposit - sharesToWithdraw, vault.balanceOf(secondWallet));
        assertEq(sharesToWithdraw, vault.balanceOf(address(vault)) - baseAmount);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(sharesToWithdraw, state.withdrawals.newHeldShares);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(deposit - sharesToWithdraw, state.liquidity.totalDeposit - baseAmount);

        (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(secondWallet);
        assertEq(vault.getEpoch().current, epoch);
        assertEq(sharesToWithdraw, withdrawalShares);
    }

    // Test exchanging shares does not damage the vault totalDeposit counter when receiver withdraws after share price changes
    function testSharesExchangePriceChange(uint256 deposit, uint256 sharesToWithdraw, uint256 tokenPrice) public {
        uint256 baseAmount = _firstDeposit();

        deposit = Utils.boundFuzzedValueToRange(deposit, 2, vault.maxDeposit() - baseAmount);
        sharesToWithdraw = Utils.boundFuzzedValueToRange(sharesToWithdraw, 1, deposit / 2);
        tokenPrice = Utils.boundFuzzedValueToRange(sharesToWithdraw, 0.0001e18, 1000e18);

        address depositor = address(0x10000);
        address secondWallet = address(0x20000);

        _deposit(depositor, deposit);
        _roll();
        _transferShares(depositor, secondWallet);

        vm.prank(secondWallet);
        vault.initiateWithdraw(sharesToWithdraw);

        VaultLib.VaultState memory state = VaultUtils.getState(vault);

        (uint256 depositorShares, uint256 depositorUnredeemedShares) = vault.shareBalances(depositor);
        (uint256 secondWalletShares, uint256 secondWalletUnredeemedShares) = vault.shareBalances(secondWallet);
        assertEq(0, depositorShares);
        assertEq(0, depositorUnredeemedShares);
        assertEq(deposit - sharesToWithdraw, secondWalletShares);
        assertEq(0, secondWalletUnredeemedShares);
        assertEq(deposit - sharesToWithdraw, vault.balanceOf(secondWallet));
        assertEq(sharesToWithdraw, vault.balanceOf(address(vault)) - baseAmount);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(sharesToWithdraw, state.withdrawals.newHeldShares);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(deposit - sharesToWithdraw, state.liquidity.totalDeposit - baseAmount);

        {
            (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(secondWallet);
            assertEq(vault.getEpoch().current, epoch);
            assertEq(sharesToWithdraw, withdrawalShares);
        }

        _changeTokenPrice(tokenPrice);
        _roll();

        vm.prank(secondWallet);
        vault.completeWithdraw();

        uint256 secondWithdraw = sharesToWithdraw;
        if (secondWithdraw > 0) {
            vm.prank(secondWallet);
            vault.initiateWithdraw(secondWithdraw);
        }

        state = VaultUtils.getState(vault);
        (secondWalletShares, secondWalletUnredeemedShares) = vault.shareBalances(secondWallet);
        assertEq(deposit - 2 * sharesToWithdraw, secondWalletShares);
        assertEq(0, secondWalletUnredeemedShares);
        assertEq(deposit - 2 * sharesToWithdraw, vault.balanceOf(secondWallet));
        assertEq(secondWithdraw, vault.balanceOf(address(vault)) - baseAmount);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(secondWithdraw, state.withdrawals.newHeldShares);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(deposit - 2 * sharesToWithdraw, state.liquidity.totalDeposit - baseAmount);

        {
            if (secondWithdraw > 0) {
                (uint256 epoch, uint256 withdrawalShares) = vault.withdrawals(secondWallet);
                assertEq(vault.getEpoch().current, epoch);
                assertEq(secondWithdraw, withdrawalShares);
            }
        }

    }

    function _changeTokenPrice(uint256 price) private {
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), price);
    }

    function _transferShares(address from, address to) private {
        vm.startPrank(from);
        (, uint256 toRedeem) = vault.shareBalances(from);
        vault.redeem(toRedeem);
        vault.transfer(to, vault.balanceOf(from));
        vm.stopPrank();
    }

    function _deposit(address depositor, uint256 amount) private {
        vm.prank(admin);
        baseToken.mint(depositor, amount);

        vm.startPrank(depositor);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, depositor, 0);
        vm.stopPrank();
    }

    function _firstDeposit() private returns (uint256) {
        uint256 btUnit = 10 ** baseToken.decimals();
        address firstDepositor = address(0x123456789);

        vm.prank(admin);
        baseToken.mint(firstDepositor, btUnit);

        vm.startPrank(firstDepositor);
        baseToken.approve(address(vault), btUnit);
        vault.deposit(btUnit, firstDepositor, 0);
        vm.stopPrank();
        return btUnit;
    }

    function _roll() private {
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();
    }
}
