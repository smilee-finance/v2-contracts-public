// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/console.sol";
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
import {MockedVault} from "./mock/MockedVault.sol";

contract VaultStateTest is Test {
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));

    address admin = address(0x1);
    address alice = address(0x2);
    TestnetToken baseToken;
    TestnetToken sideToken;
    MockedVault vault;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vault = MockedVault(VaultUtils.createVaultFromNothing(EpochFrequency.DAILY, admin, vm));
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
        uint256 expectedSideTokens = (expectedBaseTokens * 10 ** priceOracle.priceDecimals()) / sideTokenPrice;
        (uint256 baseTokens, uint256 sideTokens) = vault.balances();

        assertApproxEqAbs(expectedBaseTokens, baseTokens, 1e3);
        assertApproxEqAbs(expectedSideTokens, sideTokens, 1e3);
    }

    /**
        Check state of the vault after `deltaHedge()` call
     */
    function testDeltaHedge(uint128 amountToDeposit, int128 amountToHedge) public {
        // An amount should be always deposited
        // TBD: what if depositAmount < 1 ether ?
        vm.assume(amountToDeposit > 1 ether);

        uint256 amountToHedgeAbs = amountToHedge > 0
            ? uint256(uint128(amountToHedge))
            : uint256(-int256(amountToHedge));

        AddressProvider ap = AddressProvider(vault.addressProvider());
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

        // TODO: Adjust test when price will be get from PriceOracle, since the price is 1:1
        (uint256 btAmount, uint256 stAmount) = vault.balances();
        if ((amountToHedge > 0 && amountToHedgeAbs > btAmount) || (amountToHedge < 0 && amountToHedgeAbs > stAmount)) {
            vm.expectRevert(ExceedsAvailable);
            vault.deltaHedge(amountToHedge);
            return;
        }

        vault.deltaHedge(amountToHedge);
        (uint256 btAmountAfter, uint256 stAmountAfter) = vault.balances();

        assertEq(int256(btAmount) + expectedBaseTokenDelta, int256(btAmountAfter));
        assertEq(int256(stAmount) + expectedSideTokenDelta, int256(stAmountAfter));
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
