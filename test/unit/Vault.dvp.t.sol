// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {AmountsMath} from "@project/lib/AmountsMath.sol";
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

contract VaultDVPTest is Test {
    using AmountsMath for uint256;

    address admin;
    address user;
    address dvp;
    TestnetToken baseToken;
    TestnetToken sideToken;
    AddressProvider addressProvider;
    TestnetPriceOracle priceOracle;

    Vault vault;

    uint256 internal _toleranceBaseToken;
    uint256 internal _toleranceSideToken;

    bytes4 public constant ERR_AMOUNT_ZERO = bytes4(keccak256("AmountZero()"));
    bytes4 public constant ERR_EXCEEDS_MAX_DEPOSIT = bytes4(keccak256("ExceedsMaxDeposit()"));
    bytes4 public constant ERR_EPOCH_FINISHED = bytes4(keccak256("EpochFinished()"));
    bytes4 public constant ERR_VAULT_DEAD = bytes4(keccak256("VaultDead()"));
    bytes4 public constant ERR_VAULT_NOT_DEAD = bytes4(keccak256("VaultNotDead()"));
    bytes4 public constant ERR_MANUALLY_KILLED = bytes4(keccak256("ManuallyKilled()"));
    bytes4 public constant ERR_EXCEEDS_AVAILABLE = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 public constant ERR_DVP_NOT_SET = bytes4(keccak256("DVPNotSet()"));
    bytes4 public constant ERR_ONLY_DVP_ALLOWED = bytes4(keccak256("OnlyDVPAllowed()"));
    bytes public constant ERR_PAUSED = bytes("Pausable: paused");

    constructor() {
        admin = address(777);
        user = address(644);
        dvp = address(764);

        vm.startPrank(admin);
        addressProvider = new AddressProvider(0);
        addressProvider.grantRole(addressProvider.ROLE_ADMIN(), admin);
        vm.stopPrank();

        baseToken = TestnetToken(TokenUtils.create("USDC", 6, addressProvider, admin, vm));
        sideToken = TestnetToken(TokenUtils.create("WETH", 18, addressProvider, admin, vm));

        _toleranceBaseToken = 10 ** baseToken.decimals() / 1000;
        _toleranceSideToken = 10 ** sideToken.decimals() / 1000;

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
        FeeManager feeManager = new FeeManager(0);
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

        vault.setAllowedDVP(dvp);
        vm.stopPrank();
    }

    // Test reserve payoff
    // NOTE: this does not check whether it is actually reserved on roll-epoch
    function testReservePayoff(uint256 notional, uint256 payoff) public {
        notional = Utils.boundFuzzedValueToRange(notional, 1, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, 0, notional);
        vm.assume(payoff <= notional);

        // provide tokens to the user:
        vm.prank(admin);
        baseToken.mint(user, notional);
        // deposit:
        vm.startPrank(user);
        baseToken.approve(address(vault), notional);
        vault.deposit(notional, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        assertEq(notional, vault.notional());
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.newPendingPayoffs);

        vm.prank(dvp);
        vault.reservePayoff(payoff);

        state = VaultUtils.getState(vault);
        assertEq(payoff, state.liquidity.newPendingPayoffs);
    }

    // Test reserve payoff when the DVP is not set (revert)
    function testReservePayoffWhenDVPIsNotSet(uint256 notional, uint256 payoff) public {
        notional = Utils.boundFuzzedValueToRange(notional, 1, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, 0, notional);
        vm.assume(payoff <= notional);

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

        // provide tokens to the user:
        vm.prank(admin);
        baseToken.mint(user, notional);
        // deposit:
        vm.startPrank(user);
        baseToken.approve(address(vault), notional);
        vault.deposit(notional, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(notional, vault.notional());
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.newPendingPayoffs);

        vm.prank(user);
        vm.expectRevert(ERR_DVP_NOT_SET);
        vault.reservePayoff(payoff);
    }

    // Test reserve payoff when caller is not the DVP (revert)
    function testReservePayoffWhenCallerIsNotDVP(uint256 notional, uint256 payoff) public {
        notional = Utils.boundFuzzedValueToRange(notional, 1, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, 0, notional);
        vm.assume(payoff <= notional);

        // provide tokens to the user:
        vm.prank(admin);
        baseToken.mint(user, notional);
        // deposit:
        vm.startPrank(user);
        baseToken.approve(address(vault), notional);
        vault.deposit(notional, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        assertEq(notional, vault.notional());
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.newPendingPayoffs);

        vm.prank(user);
        vm.expectRevert(ERR_ONLY_DVP_ALLOWED);
        vault.reservePayoff(payoff);
    }

    // Test roll epoch with an empty portfolio when already empty and without pending liquidity (either in or out)
    function testRollEpochWithEmptyPortfolioAndNoActions() public {
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(0, sideToken.balanceOf(address(vault)));

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.lockedInitially);
        assertEq(0, state.liquidity.pendingDeposits);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(0, state.liquidity.pendingPayoffs);
        assertEq(0, state.liquidity.newPendingPayoffs);
        assertEq(0, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);
        assertEq(false, state.dead);
        assertEq(false, state.killed);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(0, sideToken.balanceOf(address(vault)));

        assertEq(0, vault.v0());

        state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.lockedInitially);
        assertEq(0, state.liquidity.pendingDeposits);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(0, state.liquidity.pendingPayoffs);
        assertEq(0, state.liquidity.newPendingPayoffs);
        assertEq(0, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);
        assertEq(false, state.dead);
        assertEq(false, state.killed);
    }

    /**
     * Simulate the behaviour of the roll-epoch on an empty vault with only pending deposits.
     *
     * The vault must be on a clean state before the roll-epoch, with just the pending deposits.
     * The vault must produce an equal weight portfolio of the right amounts and value.
     */
    function testRollEpochWithEmptyPortfolioAndDeposits(uint256 amount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals() / 1000;
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);

        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(0, sideToken.balanceOf(address(vault)));

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        assertEq(amount, baseToken.balanceOf(address(vault)));
        assertEq(0, sideToken.balanceOf(address(vault)));

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(0, state.liquidity.lockedInitially);
        assertEq(amount, state.liquidity.pendingDeposits);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(0, state.liquidity.pendingPayoffs);
        assertEq(0, state.liquidity.newPendingPayoffs);
        assertEq(amount, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);
        assertEq(false, state.dead);
        assertEq(false, state.killed);

        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        uint256 expectedBaseTokens = AmountsMath.wrapDecimals(amount, baseToken.decimals());
        expectedBaseTokens = expectedBaseTokens / 2;
        expectedBaseTokens = AmountsMath.unwrapDecimals(expectedBaseTokens, baseToken.decimals());
        assertApproxEqAbs(expectedBaseTokens, baseToken.balanceOf(address(vault)), _toleranceBaseToken);

        uint256 expectedSideTokens = AmountsMath.wrapDecimals(amount, baseToken.decimals());
        expectedSideTokens = (expectedSideTokens / 2).wdiv(sideTokenPrice);
        expectedSideTokens = AmountsMath.unwrapDecimals(expectedSideTokens, sideToken.decimals());
        assertApproxEqAbs(expectedSideTokens, sideToken.balanceOf(address(vault)), _toleranceSideToken);

        assertEq(amount, vault.v0());

        state = VaultUtils.getState(vault);
        assertEq(amount, state.liquidity.lockedInitially);
        assertEq(0, state.liquidity.pendingDeposits);
        assertEq(0, state.liquidity.pendingWithdrawals);
        assertEq(0, state.liquidity.pendingPayoffs);
        assertEq(0, state.liquidity.newPendingPayoffs);
        assertEq(amount, state.liquidity.totalDeposit);
        assertEq(0, state.withdrawals.heldShares);
        assertEq(0, state.withdrawals.newHeldShares);
        assertEq(false, state.dead);
        assertEq(false, state.killed);
    }

    /**
     * Simulate the behaviour of the roll-epoch on a non-empty vault without pending liquidity (either in or out)
     *
     * The vault portfolio may be slightly unbalanced before the roll-epoch.
     * The vault must produce an equal weight portfolio of the right amounts and value.
     */
    function testRollEpochWithExistingUnbalancedPortfolioAndNoActions(uint256 amount, uint256 sideTokenPrice, bool unbalancingDirection) public {
        uint256 minAmount = 10 ** baseToken.decimals() / 1000;
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);

        // First epoch with deposit:
        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // Make the portfolio unbalanced:
        uint256 unbalancingAmountAbs = AmountsMath.wrapDecimals(amount / 10, baseToken.decimals());
        unbalancingAmountAbs = AmountsMath.unwrapDecimals(unbalancingAmountAbs, sideToken.decimals());
        int256 unbalancingAmount = int256(unbalancingAmountAbs);
        unbalancingAmount = (unbalancingDirection) ? unbalancingAmount : unbalancingAmount * -1;
        vm.prank(dvp);
        vault.deltaHedge(unbalancingAmount);

        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        uint256 expectedNotional;
        {
            // NOTE: ignoring pendings as we know that there are no ones
            uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
            uint256 sideTokens = AmountsMath.wrapDecimals(sideToken.balanceOf(address(vault)), sideToken.decimals());
            uint256 sideTokensValue = AmountsMath.unwrapDecimals(sideTokens.wmul(sideTokenPrice), baseToken.decimals());

            expectedNotional = baseTokenBalance + sideTokensValue;
        }
        assertApproxEqAbs(expectedNotional, vault.notional(), _toleranceBaseToken);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // Check equal weight portfolio:
        uint256 expectedBaseTokens = AmountsMath.wrapDecimals(expectedNotional, baseToken.decimals());
        expectedBaseTokens = expectedBaseTokens / 2;
        expectedBaseTokens = AmountsMath.unwrapDecimals(expectedBaseTokens, baseToken.decimals());
        assertApproxEqAbs(expectedBaseTokens, baseToken.balanceOf(address(vault)), _toleranceBaseToken);

        uint256 expectedSideTokens = AmountsMath.wrapDecimals(expectedNotional, baseToken.decimals());
        expectedSideTokens = (expectedSideTokens / 2).wdiv(sideTokenPrice);
        expectedSideTokens = AmountsMath.unwrapDecimals(expectedSideTokens, sideToken.decimals());
        assertApproxEqAbs(expectedSideTokens, sideToken.balanceOf(address(vault)), _toleranceSideToken);

        assertApproxEqAbs(expectedNotional, vault.v0(), _toleranceBaseToken);

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertApproxEqAbs(expectedNotional, state.liquidity.lockedInitially, _toleranceBaseToken);
    }

    // - [TODOs]: test roll epoch (focus on payoff and portfolio balance)
    /**
     * - Test roll epoch equal weight portfolio when not empty and with new pending payoff (less or equal to the notional)
     * - [TBD]: test roll epoch equal weight portfolio when not empty and with new pending payoff (greater than the notional) [revert; seems impossible to happen from the DVP]
     */

    // ---------

    // - [TODO]: test delta hedge when side tokens needs to be bought and the available base tokens are enough for the swap
    // - [TODO]: test delta hedge when side tokens needs to be bought and the available base tokens are enough for the swap, but not for the slippage
    // - [TODO]: test delta hedge when side tokens needs to be bought and the available base tokens are not enough for the swap
    // - [TODO]: test delta hedge when side tokens needs to be bought but there are no available base tokens (revert)
    // - [TBD]: test delta hedge when side tokens needs to be bought and the external exchange adapter is not set (revert)
    // - [TBD]: test delta hedge when side tokens needs to be bought but the external exchange adapter reverts (revert)
    // - [TODO]: test delta hedge when side tokens needs to be sold and the available ones are enough
    // - [TODO]: test delta hedge when side tokens needs to be sold and the available ones are not enough (revert)
    // - [TBD]: test delta hedge when side tokens needs to be sold and the external exchange adapter is not set (revert)
    // - [TBD]: test delta hedge when side tokens needs to be sold but the external exchange adapter reverts (revert)
    // - [TODO]: test delta hedge when the side tokens to move are zero
    // - [TODO]: test delta hedge when the the vault is dead (revert)
    // - [TODO]: test delta hedge when the the vault is paused (revert)
    // - [TODO]: test delta hedge when the the caller is not the DVP (revert)
    // - [TODO]: test transfer payoff accounted for a past epoch
    // - [TODO]: test transfer payoff accounted for a past epoch but the amount exceeds the accounted one (revert)
    // - [TODO]: test transfer payoff with the current notional
    // - [TODO]: test transfer payoff when the current notional is not enough (revert)
    // - [TODO]: test transfer payoff of zero amount
    // - [TODO]: test transfer payoff when the vault is paused (revert)
    // - [TODO]: test transfer payoff when the caller is not the DVP (revert)
}
