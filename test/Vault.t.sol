// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {IG} from "../src/IG.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Vault} from "../src/Vault.sol";
import {VaultLib} from "../src/lib/VaultLib.sol";

import {Registry} from "../src/Registry.sol";

contract VaultTest is Test {
    bytes4 constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));

    address tokenAdmin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    Registry registry;

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

    function testDepositFail() public {
        Vault vault = _createMarket();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.prank(alice);
        vm.expectRevert(NoActiveEpoch);
        vault.deposit(100);
    }

    function testDeposit() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.prank(alice);
        vault.deposit(100);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        // initial share price is 1:1, so expect 100 shares to be minted
        assertEq(100, vault.totalSupply());
        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(alice);
        assertEq(0, baseToken.balanceOf(alice));
        assertEq(0, shares);
        assertEq(100, unredeemedShares);
    }

    function testRedeemFail() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.prank(alice);
        vault.deposit(100);

        vm.warp(block.timestamp + 1 days + 1);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(ExceedsAvailable);
        vault.redeem(150);
    }

    function testRedeem() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.prank(alice);
        vault.deposit(100);

        _skipDay(true);
        vault.rollEpoch();

        vm.prank(alice);
        vault.redeem(50);

        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(alice);
        assertEq(50, shares);
        assertEq(50, unredeemedShares);
        assertEq(50, vault.balanceOf(alice));
    }

    function testInitWithdrawFail() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vault.initiateWithdraw(100);
    }

    function testInitWithdrawWithRedeem() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);

        _skipDay(true);
        vault.rollEpoch();

        vault.redeem(100);
        vault.initiateWithdraw(100);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);

        assertEq(0, vault.balanceOf(alice));
        assertEq(100, withdrawalShares);
    }

    function testInitWithdrawWithoutRedeem() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);

        _skipDay(true);
        vault.rollEpoch();

        vault.initiateWithdraw(100);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(0, vault.balanceOf(alice));
        assertEq(100, withdrawalShares);
    }

    function testInitWithdrawPartWithoutRedeem() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);

        _skipDay(true);
        vault.rollEpoch();

        vault.initiateWithdraw(50);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(50, vault.balanceOf(alice));
        assertEq(50, vault.balanceOf(address(vault)));
        assertEq(50, withdrawalShares);
    }

    function testWithdraw() public {
        Vault vault = _createMarket();
        vault.rollEpoch();

        _provideApprovedBaseTokens(alice, 100, address(vault));

        vm.startPrank(alice);
        vault.deposit(100);

        _skipDay(true);
        vault.rollEpoch();

        vault.initiateWithdraw(40);
        // a max redeem is done within initiateWithdraw so unwithdrawn shares remain to alice
        assertEq(40, vault.balanceOf(address(vault)));
        assertEq(60, vault.balanceOf(alice));

        _skipDay(false);
        vault.rollEpoch();

        vault.completeWithdraw();

        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(60, vault.totalSupply());
        assertEq(60, baseToken.balanceOf(address(vault)));
        assertEq(40, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalShares);
    }

    /**
     * Describe two users, the first (Alice) deposits 100$ in epoch1 receiving 100 shares. 
     * Meanwhile the price of the lockedLiquidity has been multiplied by 2 (always in epoch1).
     * Bob deposits 100$ in epoch1, but, since his shares will be delivered in epoch2 and the price in epoch1 is changed, Bob receive 50 shares.
     * In epoch2, the price has been multiplied by 2 again. Meanwhile Bob and Alice start a the withdraw procedure for all their shares. 
     * Alice should receive 400$ and Bob 200$ from their shares.
     */
    function testVaultMathDoubleLiquidity() public {
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
        assertEq(vault.totalSupply(), 100);
        assertEq(heldByVaultAlice, 100);

        vm.startPrank(bob);
        vault.deposit(100);
        vm.stopPrank();
        _skipDay(false);

        vault.testIncreaseDecreateLiquidityLocked(100, true);
        _provideApprovedBaseTokens(address(vault), 100, address(vault));

        assertEq(baseToken.balanceOf(address(vault)), 300);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(vault.totalSupply(), 150);
        assertEq(heldByVaultBob, 50);

        vm.startPrank(alice);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(50);
        vm.stopPrank();
        
        vault.testIncreaseDecreateLiquidityLocked(300, true);
        _provideApprovedBaseTokens(address(vault), 300, address(vault));
        assertEq(baseToken.balanceOf(address(vault)), 600);


         _skipDay(false);

        vault.rollEpoch();

        vm.startPrank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(50, vault.totalSupply());
        assertEq(200, baseToken.balanceOf(address(vault)));
        assertEq(400, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(200, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
        vm.stopPrank();

    }

    /**
     * Describe two users, the first (Alice) deposits 100$ in epoch1 receiving 100 shares. 
     * Meanwhile the price of the lockedLiquidity has been divided by 2 (always in epoch1).
     * Bob deposits 100$ in epoch1, but, since his shares will be delivered in epoch2 and the price in epoch1 is changed, Bob receive 200 shares.
     * In epoch2, the price has been divided by 2 again. Meanwhile Bob and Alice start a the withdraw procedure for all their shares. 
     * Alice should receive 25$ and Bob 50$ from their shares.
     */
    function testVaultMathHalfLiquidity() public {
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
        assertEq(vault.totalSupply(), 100);
        assertEq(heldByVaultAlice, 100);

        vm.startPrank(bob);
        vault.deposit(100);
        vm.stopPrank();
        _skipDay(false);

        vault.testIncreaseDecreateLiquidityLocked(50, false);
        vm.startPrank(address(vault));
        // Burn baseToken from Vault
        IERC20(baseToken).transfer(address(0x1000), 50);
        vm.stopPrank();

        assertEq(baseToken.balanceOf(address(vault)), 150);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(vault.totalSupply(), 300);
        assertEq(heldByVaultBob, 200);

        vm.startPrank(alice);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(200);
        vm.stopPrank();
        
        vm.startPrank(address(vault));
        vault.testIncreaseDecreateLiquidityLocked(75, false);
        IERC20(baseToken).transfer(address(0x1000), 75);
        vm.stopPrank();

        assertEq(baseToken.balanceOf(address(vault)), 75);


         _skipDay(false);

        vault.rollEpoch();

        vm.startPrank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(200, vault.totalSupply());
        assertEq(50, baseToken.balanceOf(address(vault)));
        assertEq(25, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(50, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
        vm.stopPrank();

    }


    /**
     * Describe two users, the first (Alice) deposits 100$ in epoch1 receiving 100 shares. 
     * Meanwhile the price of the lockedLiquidity has been divided by 2 (always in epoch1).
     * Bob deposits 100$ in epoch1, but, since his shares will be delivered in epoch2 and the price in epoch1 is changed, Bob receive 200 shares.
     * In epoch2, the price has been divided by 2 again. Meanwhile Bob and Alice start a the withdraw procedure for all their shares. 
     * Alice should receive 25$ and Bob 50$ from their shares.
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
        assertEq(vault.totalSupply(), 100);
        assertEq(heldByVaultAlice, 100);

        vm.startPrank(bob);
        vault.deposit(100);
        vm.stopPrank();
        _skipDay(false);

        // Increasing liquidityLocked by 100
        vault.testIncreaseDecreateLiquidityLocked(100, true);
        _provideApprovedBaseTokens(address(vault), 100, address(vault));
        

        assertEq(baseToken.balanceOf(address(vault)), 300);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(vault.totalSupply(), 150);
        assertEq(heldByVaultBob, 50);

        vm.startPrank(alice);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(50);
        vm.stopPrank();
        
        vm.startPrank(address(vault));
        vault.testIncreaseDecreateLiquidityLocked(300, false);
        IERC20(baseToken).transfer(address(0x1000), 300);
        vm.stopPrank();

        assertEq(baseToken.balanceOf(address(vault)), 0);

         _skipDay(false);
        uint256 withdrawalEpoch = vault.currentEpoch();
        vault.rollEpoch();

        (uint256 lockedLiquidity, ,) = vault.vaultState();
        console.log("lockedLiquidity");
        console.logUint(lockedLiquidity);
        
        console.log("vault.epochPricePerShare(withdrawalEpoch)");
        console.logUint(vault.epochPricePerShare(withdrawalEpoch));
        vm.startPrank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(50, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(0, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(50, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
        vm.stopPrank();

    }

    /**
     * Describe two users, the first (Alice) deposits 100$ in epoch1 receiving 100 shares. 
     * Meanwhile the price of the lockedLiquidity has been divided by 2 (always in epoch1).
     * Bob deposits 100$ in epoch1, but, since his shares will be delivered in epoch2 and the price in epoch1 is changed, Bob receive 200 shares.
     * In epoch2, the price has been divided by 2 again. Meanwhile Bob and Alice start a the withdraw procedure for all their shares. 
     * Alice should receive 25$ and Bob 50$ from their shares.
     */
    function testVaultMathLiquidityGoesToZeroWithDeposit() public {
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
        assertEq(vault.totalSupply(), 100);
        assertEq(heldByVaultAlice, 100);

        vm.startPrank(bob);
        vault.deposit(100);
        vm.stopPrank();
        _skipDay(false);

        // Increasing liquidityLocked by 100
        vault.testIncreaseDecreateLiquidityLocked(100, true);
        _provideApprovedBaseTokens(address(vault), 100, address(vault));
        

        assertEq(baseToken.balanceOf(address(vault)), 300);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(vault.totalSupply(), 150);
        assertEq(heldByVaultBob, 50);

        vm.startPrank(alice);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(50);
        vm.stopPrank();
        
        vm.startPrank(address(vault));
        vault.testIncreaseDecreateLiquidityLocked(300, false);
        IERC20(baseToken).transfer(address(0x1000), 300);
        vm.stopPrank();

        assertEq(baseToken.balanceOf(address(vault)), 0);

         _skipDay(false);
        uint256 withdrawalEpoch = vault.currentEpoch();
        vault.rollEpoch();

        (uint256 lockedLiquidity, ,) = vault.vaultState();
        console.log("lockedLiquidity");
        console.logUint(lockedLiquidity);
        
        console.log("vault.epochPricePerShare(withdrawalEpoch)");
        console.logUint(vault.epochPricePerShare(withdrawalEpoch));
        vm.startPrank(alice);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(50, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(0, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.completeWithdraw();

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(0, baseToken.balanceOf(address(vault)));
        assertEq(50, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
        vm.stopPrank();

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
}
