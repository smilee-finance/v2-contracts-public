// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {IG} from "../src/IG.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Vault} from "../src/Vault.sol";
import {VaultLib} from "../src/lib/VaultLib.sol";

import {Registry} from "../src/Registry.sol";

contract VaultDeathTest is Test {
    bytes4 constant VaultDead = bytes4(keccak256("VaultDead()"));
    bytes4 constant VaultNotDead = bytes4(keccak256("VaultNotDead()"));

    address tokenAdmin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    Registry registry;
    VaultLib.VaultState vaultState;

    function setUp() public {
        registry = new Registry();
        address controller = address(registry);
        address swapper = address(0x5);
        vm.startPrank(tokenAdmin);

        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        baseToken = token;

        token = new TestnetToken("Testnet WETH", "stWETH");
        token.setController(controller);
        token.setSwapper(swapper);
        sideToken = token;

        vm.stopPrank();
        vm.warp(EpochFrequency.REF_TS);
    }

    /**
     * Describe two users, the first (Alice) deposits 100$ in epoch1 receiving 100 shares.
     * Bob deposits 100$ in epoch2. Bob receive also 100 shares. 
     * Bob and Alice starts the withdraw procedure in epoch3. Meanwhile, the lockedLiquidity goes to 0.
     * In epoch3, the Vault dies due to empty lockedLiquidity (so the sharePrice is 0). Nobody can deposit from epoch2 on.
     * Bob and Alice could complete the withdraw procedure receiving both 0$.
     */
    function testVaultMathLiquidityGoesToZero() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));
        _provideApprovedBaseTokens(bob, 100, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);
        vm.stopPrank();
        _skipDay(true);

        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        vm.startPrank(bob);
        vault.deposit(100);
        vm.stopPrank();
        _skipDay(false);

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

        vm.startPrank(address(vault));
        vault.testIncreaseDecreateLiquidityLocked(200, false);
        IERC20(baseToken).transfer(address(0x1000), 200);
        vm.stopPrank();

        assertEq(0, baseToken.balanceOf(address(vault)));

        _skipDay(false);
        vault.rollEpoch();

        _refreshVaultStateInformation(vault);

        assertEq(true, vaultState.dead);

        vm.startPrank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(100, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(0, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(0, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
        vm.stopPrank();
    }

     /**
     * Describe the case of deposit after Vault Death. In this case is expected an error.
     */
    function testVaultMathLiquidityGoesToZeroWithDepositAfterDieFail() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 200, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);
        vm.stopPrank();
        _skipDay(true);

        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        _skipDay(false);
        vault.rollEpoch();

        vm.startPrank(address(vault));
        vault.testIncreaseDecreateLiquidityLocked(100, false);
        IERC20(baseToken).transfer(address(0x1000), 100);
        vm.stopPrank();

        assertEq(0, baseToken.balanceOf(address(vault)));

        _skipDay(false);
        vault.rollEpoch();

        _refreshVaultStateInformation(vault);

        // Check if lockedLiquidity has gone to 0 and the Vault is dead.
        assertEq(0, vaultState.lockedLiquidity);
        assertEq(true, vaultState.dead);

        // Alice wants to deposit after Vault death. We expect a VaultDead error.
        vm.startPrank(alice);
        vm.expectRevert(VaultDead);
        vault.deposit(100);
        vm.stopPrank();
    }

    /**
     * 
     */
    function testVaultMathLiquidityGoesToZeroWithDepositBeforeDie() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 200, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);
        vm.stopPrank();
        _skipDay(true);

        vault.rollEpoch();

        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        _skipDay(false);
        vault.rollEpoch();

        vm.startPrank(address(vault));
        vault.testIncreaseDecreateLiquidityLocked(100, false);
        IERC20(baseToken).transfer(address(0x1000), 100);
        vm.stopPrank();

        assertEq(0, baseToken.balanceOf(address(vault)));

        vm.startPrank(alice);
        vault.deposit(100);
        vm.stopPrank();

        _skipDay(false);
        vault.rollEpoch();

        assertEq(100, vault.totalSupply());

        _refreshVaultStateInformation(vault);

        // Check if lockedLiquidity has gone to 0 and the Vault is dead.
        assertEq(0, vaultState.lockedLiquidity);
        assertEq(true, vaultState.dead);

        (heldByAccountAlice, heldByVaultAlice) = vault.shareBalances(alice);

        assertEq(0, heldByAccountAlice);
        assertEq(100, heldByVaultAlice);

        assertEq(100, baseToken.balanceOf(address(vault)));
        (, uint256 depositReceiptsAliceAmount, ) = vault.depositReceipts(alice);
        assertEq(100, depositReceiptsAliceAmount);

        // Alice rescues her baseToken
        vm.startPrank(alice);
        vault.rescueDeposit();
        vm.stopPrank();

        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(100, baseToken.balanceOf(alice));
        (, depositReceiptsAliceAmount, ) = vault.depositReceipts(alice);
        assertEq(0, depositReceiptsAliceAmount);
    }

    /**
     * 
     */
    function testVaultRescueDepositVaultNotDeath() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 200, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);
        vm.expectRevert(VaultNotDead);
        vault.rescueDeposit();
        vm.stopPrank();
        _skipDay(true);

        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(100, vault.totalSupply());
        assertEq(100, heldByVaultAlice);

        _skipDay(false);
        vault.rollEpoch();
    }

    function _createMarket() private returns (Vault vault) {
        vault = new Vault(address(baseToken), address(sideToken), EpochFrequency.DAILY);
        registry.register(address(vault));
    }

    function _provideApprovedBaseTokens(address wallet, uint256 amount, address approved) private {
        vm.prank(tokenAdmin);
        baseToken.mint(wallet, amount);
        vm.prank(wallet);
        baseToken.approve(approved, amount);
    }

    function _skipDay(bool additionalSecond) private {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        vm.warp(block.timestamp + 1 days + secondToAdd);
    }

    function _refreshVaultStateInformation(Vault vault) private {
        (
            uint256 lockedLiquidity,
            uint256 lastLockedLiquidity,
            bool lastLockedLiquidityZero,
            uint256 totalPendingLiquidity,
            uint256 totalWithdrawAmount,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead
        ) = vault.vaultState();
        vaultState.lockedLiquidity = lockedLiquidity;
        vaultState.lastLockedLiquidity = lastLockedLiquidity;
        vaultState.lastLockedLiquidityZero = lastLockedLiquidityZero;
        vaultState.totalPendingLiquidity = totalPendingLiquidity;
        vaultState.totalWithdrawAmount = totalWithdrawAmount;
        vaultState.queuedWithdrawShares = queuedWithdrawShares;
        vaultState.currentQueuedWithdrawShares = currentQueuedWithdrawShares;
        vaultState.dead = dead;
    }
}
