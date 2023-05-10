// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {Utils} from "./utils/Utils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {VaultLib} from "../src/lib/VaultLib.sol";
import {IG} from "../src/IG.sol";
import {Registry} from "../src/Registry.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Vault} from "../src/Vault.sol";

contract VaultStateTest is Test {
    bytes4 constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));

    address tokenAdmin = address(0x1);
    address alice = address(0x2);
    TestnetToken baseToken;
    TestnetToken sideToken;
    Vault vault;

    function setUp() public {
        Registry registry = new Registry();
        address swapper = address(0x5);
        (address baseToken_, address sideToken_) = TokenUtils.initTokens(tokenAdmin, address(registry), swapper, vm);
        baseToken = TestnetToken(baseToken_);
        sideToken = TestnetToken(sideToken_);
        vm.warp(EpochFrequency.REF_TS);
        vault = VaultUtils.createRegisteredVault(baseToken_, sideToken_, EpochFrequency.DAILY, registry);
        vault.rollEpoch();
    }

    /**
        Test that vault accounting properties are correct after calling `moveAsset()`
     */
    function testMoveAssetPull() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);

        vm.prank(alice);
        vault.deposit(100);
        assertEq(100, baseToken.balanceOf(address(vault)));
        assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

        Utils.skipDay(true, vm);
        vault.rollEpoch();
        assertEq(100, baseToken.balanceOf(address(vault)));
        assertEq(100, VaultUtils.vaultState(vault).liquidity.locked);

        vault.moveAsset(-30);

        Utils.skipDay(false, vm);
        vault.rollEpoch();
        assertEq(70, baseToken.balanceOf(address(vault)));
        assertEq(70, VaultUtils.vaultState(vault).liquidity.locked);
    }

    function testMoveAssetPullFail() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);

        vm.prank(alice);
        vault.deposit(100);
        assertEq(100, baseToken.balanceOf(address(vault)));
        assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

        Utils.skipDay(true, vm);
        vault.rollEpoch();
        assertEq(100, baseToken.balanceOf(address(vault)));
        assertEq(100, VaultUtils.vaultState(vault).liquidity.locked);

        vm.expectRevert(ExceedsAvailable);
        vault.moveAsset(-101);
    }

    function testMoveAssetPush() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);

        vm.prank(alice);
        vault.deposit(100);
        assertEq(100, baseToken.balanceOf(address(vault)));
        assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

        Utils.skipDay(true, vm);
        vault.rollEpoch();
        assertEq(100, baseToken.balanceOf(address(vault)));
        assertEq(100, VaultUtils.vaultState(vault).liquidity.locked);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), tokenAdmin, address(vault), 100, vm);
        vm.prank(tokenAdmin);
        vault.moveAsset(100);

        Utils.skipDay(false, vm);
        vault.rollEpoch();
        assertEq(200, baseToken.balanceOf(address(vault)));
        assertEq(200, VaultUtils.vaultState(vault).liquidity.locked);
    }

    // /**
    //     Test that vault accounting properties are correct after calling `moveAsset()`
    //  */
    // function testMoveAsset() public {
    //     Vault vault = _createMarket();
    //     vault.rollEpoch();

    //     TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);

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
