// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
// import {Epoch} from "@project/lib/EpochController.sol";
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

contract VaultDVPTest is Test {
    address admin;
    address user;
    address dvp;
    TestnetToken baseToken;
    TestnetToken sideToken;
    AddressProvider addressProvider;
    TestnetPriceOracle priceOracle;

    Vault vault;

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
    bytes public ERR_INSUFFICIENT_LIQUIDITY_RESERVE_PAYOFF;

    constructor() {
        admin = address(777);
        user = address(644);
        dvp = address(764);

        ERR_INSUFFICIENT_LIQUIDITY_RESERVE_PAYOFF = abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("reservePayoff()")));

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

    // Test reserve payoff when there is not enough liquidity (revert)
    function testReservePayoffWhenExcessive(uint256 notional, uint256 payoff) public {
        notional = Utils.boundFuzzedValueToRange(notional, 1, vault.maxDeposit());
        payoff = Utils.boundFuzzedValueToRange(payoff, notional + 1, type(uint256).max);
        vm.assume(payoff > notional);

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
        vm.expectRevert(ERR_INSUFFICIENT_LIQUIDITY_RESERVE_PAYOFF);
        vault.reservePayoff(payoff);
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

    // - [TODOs]: test roll epoch (focus on payoff and portfolio balance)
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
