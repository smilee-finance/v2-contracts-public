// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {IExchange} from "../src/interfaces/IExchange.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {TestnetPriceOracle} from "../src/testnet/TestnetPriceOracle.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Utils} from "./utils/Utils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "../src/AddressProvider.sol";

contract VaultStateTest is Test {
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 constant DepositThresholdTVLReached = bytes4(keccak256("DepositThresholdTVLReached()"));
    bytes constant VaultPaused = bytes("Pausable: paused");
    bytes constant OwnerError = bytes("Ownable: caller is not the owner");

    address admin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    MockedVault vault;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.prank(admin);
        AddressProvider ap = new AddressProvider();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vault.rollEpoch();
    }

    function testCheckPendingDepositAmount() public {
        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);

        uint256 stateDepositAmount = VaultUtils.vaultState(vault).liquidity.pendingDeposits;
        assertEq(100, stateDepositAmount);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);
        stateDepositAmount = VaultUtils.vaultState(vault).liquidity.pendingDeposits;
        assertEq(200, stateDepositAmount);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        stateDepositAmount = VaultUtils.vaultState(vault).liquidity.pendingDeposits;
        assertEq(0, stateDepositAmount);
    }

    function testHeldShares() public {
        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50);

        uint256 newHeldShares = VaultUtils.vaultState(vault).withdrawals.newHeldShares;
        assertEq(50, newHeldShares);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        uint256 heldShares = VaultUtils.vaultState(vault).withdrawals.heldShares;
        newHeldShares = VaultUtils.vaultState(vault).withdrawals.newHeldShares;
        assertEq(50, heldShares);
        assertEq(0, newHeldShares);

        vm.prank(alice);
        vault.completeWithdraw();

        heldShares = VaultUtils.vaultState(vault).withdrawals.heldShares;
        assertEq(0, heldShares);
    }

    // ToDo: Add comments
    function testEqualWeightRebalance(uint256 sideTokenPrice) public {
        uint256 amountToDeposit = 100 ether;
        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), amountToDeposit, vm);
        vm.prank(alice);
        vault.deposit(amountToDeposit);

        vm.assume(sideTokenPrice > 0 && sideTokenPrice < type(uint64).max);
        TestnetPriceOracle priceOracle = TestnetPriceOracle(AddressProvider(vault.addressProvider()).priceOracle());
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        uint256 expectedBaseTokens = amountToDeposit / 2;
        uint256 expectedSideTokens = (expectedBaseTokens * 1e18) / sideTokenPrice;
        (uint256 baseTokens, uint256 sideTokens) = vault.balances();

        assertApproxEqAbs(expectedBaseTokens, baseTokens, 1e3);
        assertApproxEqAbs(expectedSideTokens, sideTokens, 1e3);
    }

    /**
        Check state of the vault after `deltaHedge()` call
     */
    function testDeltaHedge(uint128 amountToDeposit, int128 amountToHedge, uint32 sideTokenPrice) public {
        // An amount should be always deposited
        // TBD: what if depositAmount < 1 ether ?

        vm.prank(admin);
        vault.setMaxDeposit(type(uint256).max);

        vm.assume(amountToDeposit > 1 ether);
        vm.assume(sideTokenPrice > 0);

        uint256 amountToHedgeAbs = amountToHedge > 0
            ? uint256(uint128(amountToHedge))
            : uint256(-int256(amountToHedge));

        AddressProvider ap = AddressProvider(vault.addressProvider());
        TestnetPriceOracle priceOracle = TestnetPriceOracle(ap.priceOracle());

        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        IExchange exchange = IExchange(ap.exchangeAdapter());
        uint256 baseTokenSwapAmount = exchange.getOutputAmount(
            address(sideToken),
            address(baseToken),
            amountToHedgeAbs
        );

        int256 expectedSideTokenDelta = int256(amountToHedge);
        int256 expectedBaseTokenDelta = amountToHedge > 0 ? -int256(baseTokenSwapAmount) : int256(baseTokenSwapAmount);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), amountToDeposit, vm);
        vm.prank(alice);
        vault.deposit(amountToDeposit);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        (uint256 btAmount, uint256 stAmount) = vault.balances();
        if (
            (amountToHedge > 0 && baseTokenSwapAmount > btAmount) || (amountToHedge < 0 && amountToHedgeAbs > stAmount)
        ) {
            vm.expectRevert(ExceedsAvailable);
            vault.deltaHedgeMock(amountToHedge);
            return;
        }

        vault.deltaHedgeMock(amountToHedge);
        (uint256 btAmountAfter, uint256 stAmountAfter) = vault.balances();

        assertEq(int256(btAmount) + expectedBaseTokenDelta, int256(btAmountAfter));
        assertEq(int256(stAmount) + expectedSideTokenDelta, int256(stAmountAfter));
    }

    /**
        Check how initialLiquidity change after roll epoch due to operation done.
     */
    function testInitialLiquidity() public {
        uint256 initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(0, initialLiquidity);

        VaultUtils.addVaultDeposit(alice, 1 ether, admin, address(vault), vm);
        // initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        // assertEq(0, initialLiquidity);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(1 ether, initialLiquidity);

        VaultUtils.addVaultDeposit(address(0x3), 0.5 ether, admin, address(vault), vm);

        vm.prank(alice);
        // Alice want to withdraw half of her shares.
        vault.initiateWithdraw(0.5 ether);

        Utils.skipDay(true, vm);
        vault.rollEpoch();
        // Alice 0.5 ether + bob 0.5 ether
        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(1 ether, initialLiquidity);

        vm.prank(alice);
        vault.completeWithdraw();

        Utils.skipDay(true, vm);
        vault.rollEpoch();
        // Complete withdraw without any operation cannot update the initialLiquidity state
        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(1 ether, initialLiquidity);
    }

    function testMaxDeposit() public {
        vm.prank(admin);
        vault.setMaxDeposit(1000e18);

        VaultUtils.addVaultDeposit(alice, 100e18, admin, address(vault), vm);
        (, , , uint256 cumulativeAmount) = vault.depositReceipts(alice);

        assertEq(vault.totalDeposit(), 100e18);
        assertEq(cumulativeAmount, 100e18);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(9999e16);

        (, , , cumulativeAmount) = vault.depositReceipts(alice);
        assertEq(vault.totalDeposit(), 100e18);
        assertEq(cumulativeAmount, 100e18);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 20e18, admin, address(vault), vm);

        vm.prank(alice);
        vault.completeWithdraw();

        (, , , cumulativeAmount) = vault.depositReceipts(alice);
        assertEq(vault.totalDeposit(), 2001e16);
        assertEq(cumulativeAmount, 2001e16);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(5e18);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        (, , , cumulativeAmount) = vault.depositReceipts(alice);
        assertApproxEqAbs(vault.totalDeposit(), 1501e16, 1e2);
        assertApproxEqAbs(cumulativeAmount, 1501e16, 1e2);

        VaultUtils.addVaultDeposit(bob, 10e18, admin, address(vault), vm);

        assertApproxEqAbs(vault.totalDeposit(), 2501e16, 1e2);

        (, , , cumulativeAmount) = vault.depositReceipts(bob);
        assertApproxEqAbs(vault.totalDeposit(), 2501e16, 1e2);
        assertEq(cumulativeAmount, 10e18);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(bob, 10e18, admin, address(vault), vm);
        (, , , cumulativeAmount) = vault.depositReceipts(bob);
        assertApproxEqAbs(vault.totalDeposit(), 3501e16, 1e2);
        assertEq(cumulativeAmount, 20e18);

        TokenUtils.provideApprovedTokens(admin, vault.baseToken(), alice, address(vault), 1000 ether, vm);

        vm.expectRevert(DepositThresholdTVLReached);
        vault.deposit(1000 ether);
    }

    /**
     * Check all the User Vault's features are disabled when Vault is paused.
     */
    function testVaultPaused() public {
        VaultUtils.addVaultDeposit(alice, 1 ether, admin, address(vault), vm);
        TokenUtils.provideApprovedTokens(admin, vault.baseToken(), alice, address(vault), 1 ether, vm);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        assertEq(vault.isPaused(), false);

        vm.expectRevert(OwnerError);
        vault.changePauseState();

        vm.prank(admin);
        vault.changePauseState();
        assertEq(vault.isPaused(), true);

        vm.startPrank(alice);
        vm.expectRevert(VaultPaused);
        vault.deposit(1e16);

        vm.expectRevert(VaultPaused);
        vault.initiateWithdraw(1e17);

        vm.expectRevert(VaultPaused);
        vault.completeWithdraw();
        vm.stopPrank();

        Utils.skipDay(true, vm);

        vm.expectRevert(VaultPaused);
        vault.rollEpoch();

        // From here on, all the vault functions should working properly
        vm.prank(admin);
        vault.changePauseState();
        assertEq(vault.isPaused(), false);

        vault.rollEpoch();

        vm.startPrank(alice);
        vault.deposit(1e17);

        vault.initiateWithdraw(1e17);

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        vault.completeWithdraw();
    }

    // /**
    //     Test that vault accounting properties are correct after calling `moveAsset()`
    //  */
    // function testMoveAssetPull() public {
    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);

    //     vm.prank(alice);
    //     vault.deposit(100);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     // assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(true, vm);
    //     vault.rollEpoch();

    //     assertEq(50, baseToken.balanceOf(address(vault)));
    //     // assertEq(50, VaultUtils.vaultState(vault).liquidity.locked);

    //     vault.moveAsset(-30);

    //     Utils.skipDay(false, vm);
    //     vault.rollEpoch();

    //     assertEq(35, baseToken.balanceOf(address(vault)));
    //     // assertEq(35, VaultUtils.vaultState(vault).liquidity.locked);
    // }

    // function testMoveAssetPullFail() public {
    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);

    //     vm.prank(alice);
    //     vault.deposit(100);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     // assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(true, vm);
    //     vault.rollEpoch();

    //     assertEq(50, baseToken.balanceOf(address(vault)));
    //     // assertEq(50, VaultUtils.vaultState(vault).liquidity.locked);

    //     vm.expectRevert(ExceedsAvailable);
    //     vault.moveAsset(-101);
    // }

    // function testMoveAssetPush() public {
    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);

    //     vm.prank(alice);
    //     vault.deposit(100);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     // assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(true, vm);
    //     vault.rollEpoch();

    //     assertEq(50, baseToken.balanceOf(address(vault)));
    //     // assertEq(50, VaultUtils.vaultState(vault).liquidity.locked);

    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), admin, address(vault), 100, vm);
    //     vm.prank(admin);
    //     vault.moveAsset(100);

    //     Utils.skipDay(false, vm);
    //     vault.rollEpoch();

    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     // assertEq(100, VaultUtils.vaultState(vault).liquidity.locked);
    // }

    // /**
    //     Test that vault accounting properties are correct after calling `moveAsset()`
    //  */
    // function testMoveAsset() public {
    //     Vault vault = _createMarket();
    //     vault.rollEpoch();

    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);

    //     vm.prank(alice);
    //     vault.deposit(100);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(true, vm);
    //     vault.rollEpoch();

    //     vm.prank(alice);
    //     vault.initiateWithdraw(40);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     assertEq(100, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(false, vm);
    //     vault.rollEpoch();
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     assertEq(60, VaultUtils.vaultState(vault).liquidity.locked);

    //     vault.moveAsset(-30);
    //     assertEq(70, baseToken.balanceOf(address(vault)));
    //     assertEq(30, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(false, vm);
    //     vault.rollEpoch();

    //     vm.prank(alice);
    //     vault.completeWithdraw();
    //     (, uint256 withdrawalShares) = vault.withdrawals(alice);

    //     // assertEq(60, vault.totalSupply());
    //     // assertEq(60, baseToken.balanceOf(address(vault)));
    //     // assertEq(40, baseToken.balanceOf(address(alice)));
    //     // assertEq(0, withdrawalShares);
    // }
}
