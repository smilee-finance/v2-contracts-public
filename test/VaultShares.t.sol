// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {Vault} from "@project/Vault.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "@project/AddressProvider.sol";

contract VaultSharesTest is Test {
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 constant ExistingIncompleteWithdraw = bytes4(keccak256("ExistingIncompleteWithdraw()"));
    bytes4 constant VaultDead = bytes4(keccak256("VaultDead()"));
    bytes4 constant VaultNotDead = bytes4(keccak256("VaultNotDead()"));
    bytes4 constant EpochFinished = bytes4(keccak256("EpochFinished()"));
    bytes4 constant WithdrawNotInitiated = bytes4(keccak256("WithdrawNotInitiated()"));
    bytes4 constant WithdrawTooEarly = bytes4(keccak256("WithdrawTooEarly()"));

    address tokenAdmin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    MockedVault vault;

    /**
     * Setup function for each test.
     */
    function setUp() public {
        vm.warp(EpochFrequency.REF_TS + 1);

        vm.startPrank(tokenAdmin);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), tokenAdmin);
        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, tokenAdmin, vm));
        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vm.startPrank(tokenAdmin);
        vault.grantRole(vault.ROLE_ADMIN(), tokenAdmin);
        vault.grantRole(vault.ROLE_EPOCH_ROLLER(), tokenAdmin);
        vm.stopPrank();
    }

    function testDeposit() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        // initial share price is 1:1, so expect 100e18 shares to be minted
        assertEq(100e18, vault.totalSupply());
        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(alice);
        assertEq(0, baseToken.balanceOf(alice));
        assertEq(0, shares);
        assertEq(100e18, unredeemedShares);
        // check lockedLiquidity
        uint256 lockedLiquidity = vault.v0();
        assertEq(100e18, lockedLiquidity);
    }

    function testRedeemFail() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(ExceedsAvailable);
        vault.redeem(150e18);
    }

    function testDepositAmountZeroFail() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(AmountZero);
        vault.deposit(0, alice, 0);
    }

    function testDepositEpochFinishedFail() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        Utils.skipDay(false, vm);
        vm.expectRevert(EpochFinished);
        vault.deposit(100e18, alice, 0);
    }

    function testInitWithdrawEpochFinishedFail() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        Utils.skipDay(false, vm);
        vm.expectRevert(EpochFinished);
        vault.initiateWithdraw(100e18);
    }

    function testCompleteWithdrawEpochFinishedSuccess() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(100e18);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        Utils.skipDay(true, vm);
        vm.prank(alice);
        vault.completeWithdraw();

        assertEq(0, vault.totalSupply());
    }

    /**
        Wallet deposits twice (or more) in the same epoch. The amount of the shares minted for the user is the sum of all deposits.
     */
    function testDoubleDepositSameEpoch() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100e18, vm);
        vm.startPrank(alice);
        vault.deposit(50e18, alice, 0);
        vault.deposit(50e18, alice, 0);
        vm.stopPrank();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        (uint256 vaultBaseTokenBalance, ) = vault.balances();
        assertEq(100e18, vault.totalSupply());
        assertEq(50e18, vaultBaseTokenBalance);
        assertEq(100e18, heldByVaultAlice);
    }

    function testRedeemZeroFail() public {
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(AmountZero);
        vault.redeem(0);
    }

    function testRedeem() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.redeem(50e18);

        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(alice);
        assertEq(50e18, shares);
        assertEq(50e18, unredeemedShares);
        assertEq(50e18, vault.balanceOf(alice));

        // check lockedLiquidity. It still remains the same
        uint256 lockedLiquidity = vault.v0();
        assertEq(100e18, lockedLiquidity);
    }

    function testInitWithdrawWithoutSharesFail() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        vm.expectRevert(ExceedsAvailable);
        vault.initiateWithdraw(100e18);
    }

    function testInitWithdrawZeroFail() public {
        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(ExceedsAvailable);
        vault.initiateWithdraw(100e18);

        vm.prank(alice);
        vm.expectRevert(AmountZero);
        vault.initiateWithdraw(0);
    }

    /**
        Wallet redeems its shares and start a withdraw. Everithing goes ok.
     */
    function testInitWithdrawWithRedeem() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.startPrank(alice);
        vault.redeem(100e18);
        vault.initiateWithdraw(100e18);
        vm.stopPrank();
        (, uint256 withdrawalShares) = vault.withdrawals(alice);

        assertEq(0, vault.balanceOf(alice));
        assertEq(100e18, withdrawalShares);
    }

    /**
        Wallet withdraws without redeeming its shares before. An automatic redeem is executed by the protocol.
     */
    function testInitWithdrawNoRedeem() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(100e18);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(0, vault.balanceOf(alice));
        assertEq(100e18, withdrawalShares);
    }

    /**
        Wallet withdraws twice (or more) in the same epoch. The amount of the shares to withdraw has to be the sum of each.
     */
    function testInitWithdrawTwiceSameEpoch() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.startPrank(alice);
        vault.initiateWithdraw(50e18);
        vault.initiateWithdraw(50e18);
        vm.stopPrank();

        (, uint256 aliceWithdrawalShares) = vault.withdrawals(alice);
        assertEq(100e18, aliceWithdrawalShares);
    }

    /**
        Wallet withdraws twice (or more) in subsequent epochs. A ExistingIncompleteWithdraw error is expected.
     */
    function testInitWithdrawTwiceDifferentEpochs() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50e18);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(ExistingIncompleteWithdraw);
        vault.initiateWithdraw(50e18);
    }

    /**
        Wallet completes withdraw without init. A WithdrawNotInitiated error is expected.
     */
    function testCompleteWithdrawWithoutInitFail() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(WithdrawNotInitiated);
        vault.completeWithdraw();
    }

    /**
        Wallet inits and completes a withdrawal procedure in the same epoch. An WithdrawTooEarly error is expected.
     */
    function testInitAndCompleteWithdrawSameEpoch() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.startPrank(alice);
        vault.initiateWithdraw(100e18);
        vm.expectRevert(WithdrawTooEarly);
        vault.completeWithdraw();
        vm.stopPrank();
    }

    /**
        Wallet makes a partial withdraw without redeeming its shares. All shares are automatically redeemed and some of them held by the vault for withdrawal.
     */
    function testInitWithdrawPartWithoutRedeem() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50e18);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(50e18, vault.balanceOf(alice));
        assertEq(50e18, vault.balanceOf(address(vault)));
        assertEq(50e18, withdrawalShares);
    }

    function testWithdraw(uint256 depositAmount, uint256 initiateWithdrawAmount) public {
        vm.assume(depositAmount >= initiateWithdrawAmount);
        uint256 minAmount = 10 ** baseToken.decimals();
        depositAmount = Utils.boundFuzzedValueToRange(depositAmount, minAmount, vault.maxDeposit());
        initiateWithdrawAmount = Utils.boundFuzzedValueToRange(initiateWithdrawAmount, minAmount, depositAmount);
        vm.assume(depositAmount - initiateWithdrawAmount >= minAmount);

        VaultUtils.addVaultDeposit(alice, depositAmount, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(initiateWithdrawAmount);
        // a max redeem is done within initiateWithdraw so unwithdrawn shares remain to alice
        assertEq(initiateWithdrawAmount, vault.balanceOf(address(vault)));
        assertEq(depositAmount - initiateWithdrawAmount, vault.balanceOf(alice));
        // check lockedLiquidity
        uint256 lockedLiquidity = vault.v0();
        assertEq(depositAmount, lockedLiquidity);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        assertEq(initiateWithdrawAmount, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        // check lockedLiquidity
        lockedLiquidity = vault.v0();
        assertEq(depositAmount - initiateWithdrawAmount, lockedLiquidity);

        vm.prank(alice);
        vault.completeWithdraw();
        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(depositAmount - initiateWithdrawAmount, vault.totalSupply());
        assertEq(initiateWithdrawAmount, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalShares);
    }

    /**
        - Alice deposits 100 in epoch 1 (100 shares)
        - vault notional value doubles in epoch 1
        - Bob deposit 100 in epoch 1 for epoch 2 (50 shares)
        - vault notional value doubles in epoch 2
        - Bob and Alice start a the withdraw procedure for all their shares
        - Alice should receive 400 (100*4) and Bob 200 (100*2).
     */
    function testVaultMathDoubleLiquidity() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(vault.totalSupply(), 100e18);
        assertEq(heldByVaultAlice, 100e18);

        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), tokenAdmin, address(vault), 100e18, vm);
        vm.prank(tokenAdmin);
        vault.moveValue(10000); // +100% Alice
        assertEq(200e18, vault.notional());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(150e18, vault.totalSupply());
        assertEq(heldByVaultBob, 50e18);

        vm.prank(alice);
        vault.initiateWithdraw(100e18);

        vm.prank(bob);
        vault.initiateWithdraw(50e18);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), tokenAdmin, address(vault), 300e18, vm);
        vm.prank(tokenAdmin);
        vault.moveValue(10000); // +200% Alice, +100% Bob
        assertEq(600e18, vault.notional());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        assertEq(600e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        assertEq(0, vault.notional()); // everyone withdraws, notional is 0

        vm.prank(alice);
        vault.completeWithdraw();
        assertEq(200e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(50e18, vault.totalSupply());
        assertEq(400e18, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);

        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(200e18, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
    }

    /**
        - Alice deposits 100 base tokens for epoch 1 (100 shares)
        - vault notional value halves in epoch 1
        - Bob deposits 100 during epoch 1 for epoch 2 (200 shares)
        - vault notional value halves in epoch 2
        - Bob and Alice start the withdraw procedure for all their shares
        - Alice should receive 25 (100/4) and Bob 50 (100/2)
     */
    function testVaultMathHalveLiquidity() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(vault.totalSupply(), 100e18);
        assertEq(heldByVaultAlice, 100e18);

        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        vault.moveValue(-5000); // -50% Alice
        assertEq(50e18, vault.notional());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(vault.totalSupply(), 300e18);
        assertEq(heldByVaultBob, 200e18);

        vm.prank(alice);
        vault.initiateWithdraw(100e18);

        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.initiateWithdraw(200e18);

        vault.moveValue(-5000); // -75% Alice, -50% Bob
        assertEq(75e18, vault.notional());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(75e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        assertEq(0, vault.notional()); // everyone withdraws, notional is 0

        vm.prank(alice);
        vault.completeWithdraw();
        assertEq(50e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(200e18, vault.totalSupply());
        assertEq(25e18, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);

        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(50e18, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
    }

    /**
     * This test intends to check the behaviour of the Vault when someone start a withdraw and, in the next epoch
     * someone else deposits into the Vault. The expected behaviour is basicaly the withdrawal (redeemed) shares have to reduce the
     * locked liquidity balance. Who deposits after the request of withdraw must receive a number of shares calculated by subtracting the withdrawal shares amount
     * to the totalSupply(). In this case, the price must be of 1$.
     */
    function testRollEpochMathSingleInitWithdrawWithDepositWithoutCompletingWithdraw() public {
        // Roll first epoch
        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(heldByVaultAlice, 100e18);
        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100e18);
        assertEq(200e18, vault.totalSupply());

        // Alice starts withdraw
        vm.prank(alice);
        vault.initiateWithdraw(100e18);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        assertEq(100e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        // ToDo: check Alice's shares

        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(200e18, heldByVaultBob);
        assertEq(300e18, vault.totalSupply());

        // Alice not compliting withdraw in this test. Check the following test
        // vm.prank(alice);
        // vault.completeWithdraw();

        vm.prank(bob);
        vault.initiateWithdraw(200e18);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        assertEq(300e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(100e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        assertEq(0, baseToken.balanceOf(alice));
        assertEq(200e18, baseToken.balanceOf(bob));
        assertEq(100e18, vault.totalSupply());
    }

    /**
     * This test intends to check the behaviour of the Vault when someone start a withdraw and, in the next epoch
     * someone else deposits into the Vault. The expected behaviour is basicaly the withdrawal (redeemed) shares have to reduce the
     * locked liquidity balance. Who deposits after the request of withdraw must receive a number of shares calculated by subtracting the withdrawal shares amount
     * to the totalSupply(). In this case, the price must be of 1$.
     * Completing or not the withdraw cannot change the behaviour.
     */
    function testRollEpochMathSingleInitAndCompletingWithdrawWithDeposit() public {
        // Roll first epoch
        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(heldByVaultAlice, 100e18);

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100e18);
        assertEq(vault.totalSupply(), 200e18);

        // Alice starts withdraw
        vm.prank(alice);
        vault.initiateWithdraw(100e18);

        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        Utils.skipDay(true, vm);

        uint256 currentEpoch = vault.currentEpoch();
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(100e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);

        currentEpoch = vault.currentEpoch();

        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(100e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(200e18, heldByVaultBob);
        assertEq(300e18, vault.totalSupply());

        vm.prank(alice);
        vault.completeWithdraw();

        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.initiateWithdraw(200e18);

        Utils.skipDay(true, vm);

        currentEpoch = vault.currentEpoch();
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(200e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.completeWithdraw();

        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        assertEq(100e18, baseToken.balanceOf(alice));
        assertEq(200e18, baseToken.balanceOf(bob));
        assertEq(0, vault.v0());
        assertEq(0, vault.totalSupply());
    }

    /**
     * This test intends to check the behaviour of the Vault when all the holder complete the withdrawal procedure.
     * The price of a single share of the first deposit after all withdraws has to be 1$ (UNIT_PRICE).
     */
    function testRollEpochMathEveryoneWithdraw() public {
        Utils.skipDay(true, vm);
        // Roll first epoch
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(heldByVaultAlice, 100e18);

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100e18);
        assertEq(vault.totalSupply(), 200e18);

        vm.startPrank(alice);
        vault.initiateWithdraw(100e18);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(100e18);
        vm.stopPrank();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(200e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        vm.prank(alice);
        vault.completeWithdraw();

        assertEq(100e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.completeWithdraw();

        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100e18);
        assertEq(vault.totalSupply(), 100e18);
    }

    /**
     * This test intends to check the behaviour of the Vault when all the holder start the withdrawal procedure.
     * Meanwhile someone else deposits into the Vault. The price of a single share of the first deposit after all withdraws has to stay fixed to 1$ (UNIT_PRICE).
     */
    function testRollEpochMathEveryoneWithdrawWithDeposit() public {
        vm.warp(block.timestamp + 1 days + 1);
        // Roll first epoch
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(heldByVaultAlice, 100e18);

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100e18);
        assertEq(vault.totalSupply(), 200e18);

        vm.startPrank(alice);
        vault.initiateWithdraw(100e18);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(100e18);

        // pendingWithdrawals state have to keep its value after roll epoch

        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        vm.stopPrank();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(200e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        VaultUtils.addVaultDeposit(bob, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        assertEq(100e18, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(0, VaultUtils.getState(vault).liquidity.pendingWithdrawals);

        assertEq(100e18, baseToken.balanceOf(alice));
        assertEq(100e18, baseToken.balanceOf(bob));
        assertEq(100e18, vault.v0());
        assertEq(100e18, vault.totalSupply());
        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100e18);

        vm.prank(bob);
        vault.initiateWithdraw(100e18);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(bob);
        vault.completeWithdraw();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(0, heldByVaultBob);
        assertEq(0, vault.totalSupply());
        assertEq(0, vault.v0());
        assertEq(200e18, baseToken.balanceOf(bob));
    }

    /**
     * Test used to retrieve shares of an account before first epoch roll
     */
    function testVaultShareBalanceZeroEpochNotStarted() public {
        (uint256 heldByVaultAlice, uint256 heldByAlice) = vault.shareBalances(alice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAlice);

        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        //Check Share Balance of Alice epoch not rolled yet
        (heldByVaultAlice, heldByAlice) = vault.shareBalances(alice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAlice);
    }

    function testUserTrasferShares(uint256 amount, uint256 shares) public {
        address user = address(644);
        address admin = tokenAdmin;
        amount = Utils.boundFuzzedValueToRange(amount, 10 ** baseToken.decimals(), vault.maxDeposit());
        shares = Utils.boundFuzzedValueToRange(amount, 0, amount);

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();


        (, , , uint256 comulativeAmountPreRedeem) = vault.depositReceipts(user);
        assertEq(amount, comulativeAmountPreRedeem);

        vm.prank(user);
        vault.redeem(shares);


        (, uint256 receiptAmount, uint256 unredeemedShares, uint256 comulativeAmountAfterRedeem) = vault.depositReceipts(user);
        assertEq(0, receiptAmount);
        assertEq(amount - shares, unredeemedShares);
        assertEq(amount, comulativeAmountAfterRedeem);

        (uint256 userShares, uint256 userUnredeemedShares) = vault.shareBalances(user);
        uint256 amountEquivalent = (amount * shares) / (userShares + userUnredeemedShares);

        address shareRecevier = address(645);
        vm.prank(user);
        vault.transfer(shareRecevier, shares);

        (, , , uint256 comulativeAmount) = vault.depositReceipts(user);
        assertEq(amount - amountEquivalent, comulativeAmount);

        (, , , comulativeAmount) = vault.depositReceipts(shareRecevier);
        assertEq(amountEquivalent, comulativeAmount);
    }
}
