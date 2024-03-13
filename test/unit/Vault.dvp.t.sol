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
    TestnetSwapAdapter exchange;

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
    bytes4 public constant ERR_INSUFFICIENT_INPUT = bytes4(keccak256("InsufficientInput()"));
    bytes public ERR_INSUFFICIENT_LIQUIDITY_MINT_SHARES;
    bytes public ERR_INSUFFICIENT_LIQUIDITY_BUY_SIDE_TOKEN;
    bytes public ERR_INSUFFICIENT_LIQUIDITY_SELL_SIDE_TOKEN;
    bytes public ERR_INSUFFICIENT_LIQUIDITY_PENDING_PAYOFF;
    bytes public constant ERR_PAUSED = bytes("Pausable: paused");

    constructor() {
        admin = address(777);
        user = address(644);
        dvp = address(764);

        ERR_INSUFFICIENT_LIQUIDITY_MINT_SHARES = abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_beforeRollEpoch()::sharePrice == 0")));
        ERR_INSUFFICIENT_LIQUIDITY_BUY_SIDE_TOKEN = abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_buySideTokens()")));
        ERR_INSUFFICIENT_LIQUIDITY_SELL_SIDE_TOKEN = abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_sellSideTokens()")));
        ERR_INSUFFICIENT_LIQUIDITY_PENDING_PAYOFF = abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_beforeRollEpoch()::lockedLiquidity <= _state.liquidity.newPendingPayoffs")));

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

        exchange = new TestnetSwapAdapter(addressProvider.priceOracle());
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

        vault.setAllowedDVP(dvp);
        vm.stopPrank();
    }

    // Test reserve payoff
    // NOTE: this does not check whether it is actually reserved on roll-epoch
    function testReservePayoff(uint256 notional, uint256 payoff) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        notional = Utils.boundFuzzedValueToRange(notional, minAmount, vault.maxDeposit());
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
        uint256 minAmount = 10 ** baseToken.decimals();
        notional = Utils.boundFuzzedValueToRange(notional, minAmount, vault.maxDeposit());
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
        uint256 minAmount = 10 ** baseToken.decimals();
        notional = Utils.boundFuzzedValueToRange(notional, minAmount, vault.maxDeposit());
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
        uint256 minAmount = 10 ** baseToken.decimals();
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
        uint256 minAmount = 10 ** baseToken.decimals();
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

    /**
     * Simulate the behaviour of the roll-epoch on a non-empty vault with only a pending payoff
     *
     * The payoff needs to be less or equal to the notional.
     * The vault portfolio may be slightly unbalanced before the roll-epoch.
     * The vault must produce an equal weight portfolio of the right amounts and value.
     */
    function testRollEpochWithExistingUnbalancedPortfolioAndPayoff(uint256 amount, uint256 payoff, uint256 sideTokenPrice, bool unbalancingDirection) public {
        vm.assume(payoff <= amount);
        uint256 minAmount = 10 ** baseToken.decimals();
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
            uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
            uint256 sideTokens = AmountsMath.wrapDecimals(sideToken.balanceOf(address(vault)), sideToken.decimals());
            uint256 sideTokensValue = AmountsMath.unwrapDecimals(sideTokens.wmul(sideTokenPrice), baseToken.decimals());

            expectedNotional = baseTokenBalance + sideTokensValue;
        }
        assertApproxEqAbs(expectedNotional, vault.notional(), _toleranceBaseToken);

        // Reserve the payoff:
        vm.assume(expectedNotional >= minAmount);
        payoff = Utils.boundFuzzedValueToRange(payoff, minAmount, expectedNotional);
        vm.prank(dvp);
        vault.reservePayoff(payoff);

        expectedNotional -= payoff;

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // Check equal weight portfolio:
        uint256 expectedBaseTokens = AmountsMath.wrapDecimals(expectedNotional, baseToken.decimals());
        expectedBaseTokens = expectedBaseTokens / 2;
        expectedBaseTokens = AmountsMath.unwrapDecimals(expectedBaseTokens, baseToken.decimals());
        assertApproxEqAbs(expectedBaseTokens + payoff, baseToken.balanceOf(address(vault)), _toleranceBaseToken);

        uint256 expectedSideTokens = AmountsMath.wrapDecimals(expectedNotional, baseToken.decimals());
        expectedSideTokens = (expectedSideTokens / 2).wdiv(sideTokenPrice);
        expectedSideTokens = AmountsMath.unwrapDecimals(expectedSideTokens, sideToken.decimals());
        assertApproxEqAbs(expectedSideTokens, sideToken.balanceOf(address(vault)), _toleranceSideToken);

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertApproxEqAbs(expectedNotional, state.liquidity.lockedInitially, _toleranceBaseToken);
        assertEq(payoff, state.liquidity.pendingPayoffs);
    }

    // TBD: move to Vault.user.t.sol
    // Test roll-epoch when new pending payoff is equal to the notional and with a non-zero deposit (revert).
    function testRollEpochWhenNewDepositsAreWorthZero(uint256 amount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // Force portfolio value to zero by reserving everything:
        uint256 payoff = vault.notional();
        vm.prank(dvp);
        vault.reservePayoff(payoff);

        // Add a new pending deposit:
        vm.prank(admin);
        baseToken.mint(user, minAmount);
        vm.startPrank(user);
        baseToken.approve(address(vault), minAmount);
        vault.deposit(minAmount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vm.expectRevert(ERR_INSUFFICIENT_LIQUIDITY_MINT_SHARES);
        vault.rollEpoch();
    }

    // - [TODOs]: test roll epoch (focus on payoff and portfolio balance)
    /**
     * - [TBD]: test roll-epoch equal weight portfolio when non-empty and with pending payoff, deposits and withdrawals, but payoff less or equal to the notional.
     * - [TBD]: test roll-epoch when new pending payoff is greater than the notional [revert; seems impossible to happen from the DVP]
     * - [TBD]: test roll-epoch when the base tokens don't cover the pendings (revert; seems impossible to happen)
     * - [ToDo]: test roll-epoch portfolio when the vault has been killed
     * - [ToDo]: test roll-epoch when the vault is dead (revert)
     * - [ToDo]: test roll-epoch when the msg.sender is not allowed (revert)
     * - [ToDo]: test all the paths within _adjustBalances...
     */

    // ---------

    /**
     * Test delta hedge when side tokens needs to be bought and the available base tokens are enough for the swap
     */
    function testDeltaHedgeWhenBuySideTokensWithEnoughtBaseTokensToSwap(uint256 amount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // In order to buy side token for base token the price need to go down
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1e18);
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: ignoring pendings as we know that there are no ones
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
        uint256 sideTokenBalance = sideToken.balanceOf(address(vault));

        assertApproxEqAbs(amount / 2, baseTokenBalance, _toleranceBaseToken);
        assertApproxEqAbs(AmountsMath.unwrapDecimals(AmountsMath.wrapDecimals(amount / 2, baseToken.decimals()), sideToken.decimals()), sideTokenBalance, _toleranceSideToken);

        uint256 hedgingAmount = AmountsMath.wrapDecimals(amount / 10, baseToken.decimals());
        hedgingAmount = AmountsMath.unwrapDecimals(hedgingAmount, sideToken.decimals());
        vm.prank(dvp);
        vault.deltaHedge(int256(hedgingAmount));

        uint256 expectedBaseTokenBalance = baseTokenBalance - AmountsMath.unwrapDecimals((hedgingAmount.wmul(sideTokenPrice)), baseToken.decimals());
        assertApproxEqAbs(expectedBaseTokenBalance, baseToken.balanceOf(address(vault)), _toleranceBaseToken);

        uint256 expectedSideTokenBalance = sideTokenBalance + hedgingAmount;
        assertApproxEqAbs(expectedSideTokenBalance, sideToken.balanceOf(address(vault)), _toleranceSideToken);
    }

    /**
     * Test delta hedge when side tokens needs to be bought and the available base tokens are enough for the swap, but not for the slippage
     *
     * NOTE: Revert swap adapter
     */
    function testDeltaHedgeWhenBuySideTokensWithEnoughtBaseTokensToSwapButNotForSlippage(uint256 amount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // set slippage to 2%
        uint256 exactSlippagePerc = 0.02e18;
        vm.prank(admin);
        exchange.setSlippage(int256(exactSlippagePerc), 0, 0);

        // In order to buy side token for base token the price need to go down
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1e18);
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: ignoring pendings as we know that there are no ones
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
        uint256 sideTokenBalance = sideToken.balanceOf(address(vault));

        assertApproxEqAbs(amount / 2, baseTokenBalance, _toleranceBaseToken);
        assertApproxEqAbs(AmountsMath.unwrapDecimals(AmountsMath.wrapDecimals(amount / 2, baseToken.decimals()), sideToken.decimals()), sideTokenBalance, _toleranceSideToken);

        // Margin is calcuted in order to be greater than initial base token balance, but lower than base token balance plus the default hedge margin (2,5%)
        // The revert come from swap adapter because the base tokens are enough to cover the swap, but not if you consider the slippage
        uint256 baseTokenBalanceWad = AmountsMath.wrapDecimals(baseTokenBalance, baseToken.decimals());
        uint256 baseTokenSafeMargin = AmountsMath.unwrapDecimals(baseTokenBalanceWad.wmul(0.015e18).wdiv(1e18), baseToken.decimals());
        uint256 hedgingAmountWad = AmountsMath.wrapDecimals(baseTokenBalance - baseTokenSafeMargin, baseToken.decimals());
        uint256 hedgingAmount = AmountsMath.unwrapDecimals(hedgingAmountWad.wdiv(sideTokenPrice), sideToken.decimals());
        vm.prank(dvp);
        vm.expectRevert(ERR_INSUFFICIENT_INPUT);
        vault.deltaHedge(int256(hedgingAmount));
    }

    /**
     * Test delta hedge when side tokens needs to be bought and the available base tokens are not enough for the swap
     */
    function testDeltaHedgeWhenBuySideTokensWithNotEnoughtBaseTokensToSwap(uint256 amount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // In order to buy side token for base token the price need to go down
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1e18);
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: ignoring pendings as we know that there are no ones
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
        uint256 sideTokenBalance = AmountsMath.wrapDecimals(sideToken.balanceOf(address(vault)), sideToken.decimals());

        assertApproxEqAbs(amount / 2, baseTokenBalance, _toleranceBaseToken);
        assertApproxEqAbs(AmountsMath.unwrapDecimals(AmountsMath.wrapDecimals(amount / 2, baseToken.decimals()), sideToken.decimals()), sideTokenBalance, _toleranceSideToken);

        // Margin is calcuted in order to be greater than initial base token balance, but lower than base token balance plus the default hedge margin
        uint256 _hedgeMargin = 250; // 2,5% default
        uint256 hedgingAmount;
        {
            uint256 baseTokenBalanceWad = AmountsMath.wrapDecimals(baseTokenBalance, baseToken.decimals());
            uint256 baseTokenExceedMargin = AmountsMath.unwrapDecimals(baseTokenBalanceWad.wmul(0.015e18), baseToken.decimals());
            uint256 hedgingAmountWad = AmountsMath.wrapDecimals(baseTokenBalance + baseTokenExceedMargin, baseToken.decimals());

            hedgingAmount = AmountsMath.unwrapDecimals(hedgingAmountWad.wdiv(sideTokenPrice), sideToken.decimals());
        }

        vm.prank(dvp);
        vault.deltaHedge(int256(hedgingAmount));

        // Get real amount to swap calculated with default hedge margin
        uint256 effectiveHedgingAmount = AmountsMath.unwrapDecimals(hedgingAmount - ((hedgingAmount * _hedgeMargin) / 10000), sideToken.decimals());
        uint256 expectedBaseTokenBalance = AmountsMath.unwrapDecimals(effectiveHedgingAmount.wmul(sideTokenPrice), baseToken.decimals());
        assertApproxEqAbs(baseTokenBalance - expectedBaseTokenBalance, baseToken.balanceOf(address(vault)), _toleranceBaseToken);

        uint256 expectedSideTokenBalance = sideTokenBalance + effectiveHedgingAmount;
        assertApproxEqAbs(expectedSideTokenBalance, sideToken.balanceOf(address(vault)), _toleranceSideToken);
    }

    /**
     * Test delta hedge when side tokens needs to be bought but there are no available base tokens (revert)
     */
    function testDeltaHedgeWhenBuySideTokensWithNoAvailableBaseToken(uint256 amount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // NOTE: ignoring pendings as we know that there are no ones
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
        uint256 sideTokenBalance = AmountsMath.wrapDecimals(sideToken.balanceOf(address(vault)), sideToken.decimals());

        assertApproxEqAbs(amount / 2, baseTokenBalance, _toleranceBaseToken);
        assertApproxEqAbs(AmountsMath.unwrapDecimals(AmountsMath.wrapDecimals(amount / 2, baseToken.decimals()), sideToken.decimals()), sideTokenBalance, _toleranceSideToken);

        // NOTE: base token balance need to be exactly 0
        vm.prank(address(vault));
        baseToken.transfer(admin, baseTokenBalance);
        assertEq(0, baseToken.balanceOf(address(vault)));

        vm.prank(dvp);
        vm.expectRevert(ERR_INSUFFICIENT_LIQUIDITY_BUY_SIDE_TOKEN);
        vault.deltaHedge(int256(1));
    }

    /**
     * Test delta hedge when side tokens needs to be bought but there are no available base tokens (revert)
     * This test also verifies that the basic token amount affected by the delta hedge is the notional one, therefore net of any pendings
     */
    function testDeltaHedgeWhenBuySideTokensWithNoAvailableBaseTokenWithPendings(uint256 amount, uint256 withdrawAmount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount * 2, vault.maxDeposit());
        withdrawAmount = Utils.boundFuzzedValueToRange(withdrawAmount, minAmount, amount / 2); // leave some baseTokens

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(user);
        vault.initiateWithdraw(withdrawAmount);
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // NOTE: base token balance need to be exactly 0
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault)) - state.liquidity.pendingWithdrawals;

        vm.prank(address(vault));
        baseToken.transfer(admin, baseTokenBalance);
        baseTokenBalance = baseToken.balanceOf(address(vault)) - state.liquidity.pendingWithdrawals;
        assertEq(0, baseTokenBalance);

        vm.prank(dvp);
        vm.expectRevert(ERR_INSUFFICIENT_LIQUIDITY_BUY_SIDE_TOKEN);
        vault.deltaHedge(int256(1));
    }

    /**
     * Test delta hedge when side tokens needs to be sold and the available ones are enough
     */
    function testDeltaHedgeWhenSellSideTokensWithEnoughtSideTokens(uint256 amount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // In order to sell side token for base token the price need to go up
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 1e18, 1_000e18);
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: ignoring pendings as we know that there are no ones
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
        uint256 sideTokenBalance = sideToken.balanceOf(address(vault));

        assertApproxEqAbs(amount / 2, baseTokenBalance, _toleranceBaseToken);
        assertApproxEqAbs(AmountsMath.unwrapDecimals(AmountsMath.wrapDecimals(amount / 2, baseToken.decimals()), sideToken.decimals()), sideTokenBalance, _toleranceSideToken);

        uint256 hedgingAmount = AmountsMath.wrapDecimals(amount / 10, baseToken.decimals());
        hedgingAmount = AmountsMath.unwrapDecimals(hedgingAmount, sideToken.decimals());
        vm.prank(dvp);
        vault.deltaHedge(-int256(hedgingAmount));

        uint256 expectedBaseTokenBalance = baseTokenBalance + AmountsMath.unwrapDecimals((hedgingAmount.wmul(sideTokenPrice)), baseToken.decimals());
        assertApproxEqAbs(expectedBaseTokenBalance, baseToken.balanceOf(address(vault)), _toleranceBaseToken);

        uint256 expectedSideTokenBalance = sideTokenBalance - hedgingAmount;
        assertApproxEqAbs(expectedSideTokenBalance, sideToken.balanceOf(address(vault)), _toleranceSideToken);
    }

    /**
     * Test delta hedge when side tokens needs to be sold and the available ones are not enough (revert)
     */
    function testDeltaHedgeWhenSellSideTokensWithNotEnoughSideToken(uint256 amount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // In order to sell side token for base token the price need to go up
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 1e18, 1_000e18);
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: ignoring pendings as we know that there are no ones
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
        uint256 sideTokenBalance = AmountsMath.wrapDecimals(sideToken.balanceOf(address(vault)), sideToken.decimals());

        assertApproxEqAbs(amount / 2, baseTokenBalance, _toleranceBaseToken);
        assertApproxEqAbs(AmountsMath.unwrapDecimals(AmountsMath.wrapDecimals(amount / 2, baseToken.decimals()), sideToken.decimals()), sideTokenBalance, _toleranceSideToken);

        vm.prank(dvp);
        vm.expectRevert(ERR_INSUFFICIENT_LIQUIDITY_SELL_SIDE_TOKEN);
        vault.deltaHedge(-int256(sideTokenBalance + 1));
    }

    /**
     * Test delta hedge when the side tokens to move are zero
     */
    function testDeltaHedgeWhenSideTokensToMoveAreZero(uint256 amount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // In order to buy side token for base token the price need to go up
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 1e18, 1_000e18);
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: ignoring pendings as we know that there are no ones
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
        uint256 sideTokenBalance = AmountsMath.wrapDecimals(sideToken.balanceOf(address(vault)), sideToken.decimals());

        assertApproxEqAbs(amount / 2, baseTokenBalance, _toleranceBaseToken);
        assertApproxEqAbs(AmountsMath.unwrapDecimals(AmountsMath.wrapDecimals(amount / 2, baseToken.decimals()), sideToken.decimals()), sideTokenBalance, _toleranceSideToken);

        vm.prank(dvp);
        vault.deltaHedge(0);

        assertEq(baseTokenBalance, baseToken.balanceOf(address(vault)));
        assertEq(sideTokenBalance, AmountsMath.wrapDecimals(sideToken.balanceOf(address(vault)), sideToken.decimals()));
    }

    /**
     * Test delta hedge when the the vault is dead (revert)
     */
    function testDeltaHedgeWhenVaultIsDead(uint256 amount, int256 hedgingAmount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(admin);
        vault.killVault();
        vm.warp(vault.getEpoch().current + 1);

        vm.startPrank(dvp);
        vault.rollEpoch();
        vm.expectRevert(ERR_VAULT_DEAD);
        vault.deltaHedge(hedgingAmount);
        vm.stopPrank();
    }

    /**
     * Test delta hedge when the the vault is paused (revert)
     */
    function testDeltaHedgeWhenVaultIsPaused(uint256 amount, int256 hedgingAmount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(admin);
        vault.changePauseState();
        vm.prank(dvp);
        vm.expectRevert(ERR_PAUSED);
        vault.deltaHedge(hedgingAmount);
    }

    /**
     * Test delta hedge when the the caller is not the DVP (revert)
     */
    function testDeltaHedgeWhenCallerIsNotDVP(uint256 amount, int256 hedgingAmount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(admin);
        vm.expectRevert(ERR_ONLY_DVP_ALLOWED);
        vault.deltaHedge(hedgingAmount);
    }

    // - [TBD]: test delta hedge when side tokens needs to be bought and the external exchange adapter is not set (revert)
    // - [TBD]: test delta hedge when side tokens needs to be bought but the external exchange adapter reverts (revert) // done
    // - [TBD]: test delta hedge when side tokens needs to be sold and the external exchange adapter is not set (revert)
    // - [TBD]: test delta hedge when side tokens needs to be sold but the external exchange adapter reverts (revert)

    /**
     * Test transfer payoff accounted for a past epoch
     */
    function testTransferPayoffAccountedPastEpoch(uint256 amount, uint256 payoff) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, 0, amount);

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(dvp);
        vault.reservePayoff(payoff);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        VaultLib.VaultState memory state = VaultUtils.getState(vault);

        assertEq(0, baseToken.balanceOf(user));
        assertEq(payoff, state.liquidity.pendingPayoffs);

        vm.prank(dvp);
        vault.transferPayoff(user, payoff, true);

        state = VaultUtils.getState(vault);
        assertEq(payoff, baseToken.balanceOf(user));
        assertEq(0, state.liquidity.pendingPayoffs);
    }

    /**
     * Test transfer payoff accounted for a past epoch but the amount exceeds the accounted one (revert)
     */
    function testTransferPayoffMoreThenAccountedPastEpoch(uint256 amount, uint256 payoff) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, 0, amount);

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(dvp);
        vault.reservePayoff(payoff);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        VaultLib.VaultState memory state = VaultUtils.getState(vault);

        assertEq(0,  baseToken.balanceOf(user));
        assertEq(payoff, state.liquidity.pendingPayoffs);

        vm.prank(dvp);
        vm.expectRevert(ERR_EXCEEDS_AVAILABLE);
        vault.transferPayoff(user, payoff + 1, true);
    }

    /**
     * Test transfer payoff with the current notional
     */
    function testTransferPayoffAllNotionalPastEpoch(uint256 amount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        uint256 payoff = vault.notional();
        vm.prank(dvp);
        vault.reservePayoff(payoff);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        VaultLib.VaultState memory state = VaultUtils.getState(vault);

        assertEq(0, vault.notional());
        assertEq(0, baseToken.balanceOf(user));
        assertEq(0, state.liquidity.lockedInitially);
        assertEq(payoff, state.liquidity.pendingPayoffs);

        vm.prank(dvp);
        vault.transferPayoff(user, payoff, true);

        state = VaultUtils.getState(vault);
        assertEq(payoff, baseToken.balanceOf(user));
        assertEq(0, state.liquidity.pendingPayoffs);
    }

    /**
     * Test transfer payoff of zero amount
     */
    function testTransferZeroPayoffPastEpoch(uint256 amount, uint256 payoff) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, 0, amount);

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(dvp);
        vault.reservePayoff(payoff);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        uint256 notionalPreTransfer = vault.notional();
        uint256 baseTokenBalancePreTransfer = baseToken.balanceOf(address(vault));
        assertEq(0, baseToken.balanceOf(user));
        assertEq(payoff, state.liquidity.pendingPayoffs);
        assertGe(notionalPreTransfer, 0);

        vm.prank(dvp);
        vault.transferPayoff(user, 0, true);

        state = VaultUtils.getState(vault);
        assertEq(0, baseToken.balanceOf(user));
        assertEq(payoff, state.liquidity.pendingPayoffs);
        assertEq(notionalPreTransfer, vault.notional());
        assertEq(baseTokenBalancePreTransfer, baseToken.balanceOf(address(vault)));
    }

    /**
     * Test transfer payoff when the vault is paused (revert)
     */
    function testTransferPayoffPastEpochWhenVaultIsPaused(uint256 amount, uint256 payoff) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, 0, amount);

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(dvp);
        vault.reservePayoff(payoff);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(admin);
        vault.changePauseState();

        vm.prank(dvp);
        vm.expectRevert(ERR_PAUSED);
        vault.transferPayoff(user, payoff, true);
    }

    /**
     * Test transfer payoff when the caller is not the DVP (revert)
     */
    function testTransferPayoffWhenCallerIsNotDVP(uint256 amount, uint256 payoff) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, 0, amount);

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(dvp);
        vault.reservePayoff(payoff);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(admin);
        vm.expectRevert(ERR_ONLY_DVP_ALLOWED);
        vault.transferPayoff(user, payoff, true);
    }

    // - [TODO]: test transfer payoff when epoch is not past

    /**
     * Test v0 return locked initially (0 or != 0)
     */
    function testV0ReturnInitialLockedLiquidity(uint256 amount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        uint256 v0 = vault.v0();
        assertEq(state.liquidity.lockedInitially, v0); // 0

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        state = VaultUtils.getState(vault);
        v0 = vault.v0();
        assertEq(amount, state.liquidity.lockedInitially);
        assertEq(state.liquidity.lockedInitially, v0);
    }

    /**
     * Test that vault.notional() return base token balance + side token value
     */
    function testNotionalReturnExactBaseTokenAndSideTokenNotional(uint256 amount, uint256 withdrawAmount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit() / 2); // Half max deposit because i need to make 2 deposit
        withdrawAmount = Utils.boundFuzzedValueToRange(withdrawAmount, minAmount, amount); // leave some baseTokens
        vm.assume(amount - withdrawAmount > minAmount);

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        uint256 notional = vault.notional();
        uint256 tokensNotional;
        {
            VaultLib.VaultState memory state = VaultUtils.getState(vault);
            uint256 baseTokenNotionalBalance = baseToken.balanceOf(address(vault)) - state.liquidity.pendingWithdrawals - state.liquidity.pendingPayoffs - state.liquidity.pendingDeposits;
            uint256 sideTokenBalance = sideToken.balanceOf(address(vault));
            uint256 sideTokenValue = AmountsMath.wrapDecimals(sideTokenBalance, sideToken.decimals());
            sideTokenValue = AmountsMath.unwrapDecimals(sideTokenValue.wmul(sideTokenPrice), baseToken.decimals());

            tokensNotional = baseTokenNotionalBalance + sideTokenValue;
        }

        assertEq(tokensNotional, notional);

        // initiate withdraw
        vm.prank(user);
        vault.initiateWithdraw(withdrawAmount);
        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        {
            // pendingWithdrawals > 0
            // pendingDeposits > 0
            VaultLib.VaultState memory state = VaultUtils.getState(vault);
            uint256 baseTokenNotionalBalance = baseToken.balanceOf(address(vault)) - state.liquidity.pendingWithdrawals - state.liquidity.pendingPayoffs - state.liquidity.pendingDeposits;
            uint256 sideTokenBalance = sideToken.balanceOf(address(vault));
            uint256 sideTokenValue = AmountsMath.wrapDecimals(sideTokenBalance, sideToken.decimals());
            sideTokenValue = AmountsMath.unwrapDecimals(sideTokenValue.wmul(sideTokenPrice), baseToken.decimals());

            tokensNotional = baseTokenNotionalBalance + sideTokenValue;
        }
        notional = vault.notional();

        assertEq(tokensNotional, notional);
    }
}
