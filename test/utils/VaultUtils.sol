// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultLib} from "../../src/lib/VaultLib.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {MarketOracle} from "../../src/MarketOracle.sol";
import {IG} from "../../src/IG.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
// import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {MockedRegistry} from "../mock/MockedRegistry.sol";
import {MockedVault} from "../mock/MockedVault.sol";
import {TokenUtils} from "./TokenUtils.sol";
import {FinanceParameters} from "../../src/lib/FinanceIG.sol";

library VaultUtils {
    function createVault(uint256 epochFrequency, AddressProvider ap, address admin, Vm vm) public returns (address) {
        // NOTE: the stable base token must be the first as it's used as reference for the price oracle if it doesn't exists in the AddressProvider.
        address baseToken = TokenUtils.createToken("Testnet USD", "stUSD", address(ap), admin, vm);
        return createVaultSideTokenSym(baseToken, "WETH", epochFrequency, ap, admin, vm);
    }

    function createVaultSideTokenSym(
        address baseToken,
        string memory sideTokenSym,
        uint256 epochFrequency,
        AddressProvider ap,
        address admin,
        Vm vm
    ) public returns (address) {
        address sideToken = TokenUtils.createToken(
            string.concat("Testnet ", sideTokenSym),
            string.concat("st", sideTokenSym),
            address(ap),
            admin,
            vm
        );
        // vm.prank(admin);
        // TestnetToken(sideToken).setDecimals(8);

        return createVaultFromTokens(baseToken, sideToken, epochFrequency, ap, admin, vm);
    }

    function createVaultFromTokens(
        address baseToken,
        address sideToken,
        uint256 epochFrequency,
        AddressProvider ap,
        address admin,
        Vm vm
    ) public returns (address) {
        vm.startPrank(admin);
        TestnetPriceOracle priceOracle = TestnetPriceOracle(ap.priceOracle());
        priceOracle.setTokenPrice(sideToken, 1 ether);

        MockedVault vault = new MockedVault(baseToken, sideToken, epochFrequency, address(ap));

        // TBD: registrer it outside...
        MockedRegistry registry = MockedRegistry(ap.registry());
        registry.registerVault(address(vault));

        MarketOracle marketOracle = MarketOracle(ap.marketOracle());
        uint256 lastUpdate = marketOracle.getImpliedVolatilityLastUpdate(baseToken, sideToken, epochFrequency);
        if (lastUpdate == 0) {
            marketOracle.setImpliedVolatility(baseToken, sideToken, epochFrequency, 0.5e18);
        }

        vm.stopPrank();
        return address(vault);
    }

    /// @dev Builds and returns a `VaultLib.VaultState` with info on current vault state
    function vaultState(MockedVault vault) internal view returns (VaultLib.VaultState memory) {
        (
            uint256 lockedInitially,
            uint256 pendingDepositAmount,
            uint256 totalWithdrawAmount,
            uint256 pendingPayoffs,
            uint256 totalDeposit,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead,
            bool killed
        ) = vault.vaultState();
        return
            VaultLib.VaultState(
                VaultLib.VaultLiquidity(
                    lockedInitially,
                    pendingDepositAmount,
                    totalWithdrawAmount,
                    pendingPayoffs,
                    0,
                    totalDeposit
                ),
                VaultLib.VaultWithdrawals(queuedWithdrawShares, currentQueuedWithdrawShares),
                dead,
                killed
            );
    }

    function debugState(MockedVault vault) public view {
        VaultLib.VaultState memory state = vaultState(vault);
        console.log("----------VAULT STATE----------");
        console.log("lockedInitially", state.liquidity.lockedInitially);
        console.log("pendingDeposits", state.liquidity.pendingDeposits);
        console.log("pendingWithdrawals", state.liquidity.pendingWithdrawals);
        console.log("pendingPayoffs", state.liquidity.pendingPayoffs);
        console.log("newPendingPayoffs", state.liquidity.newPendingPayoffs);
        console.log("totalDeposit", state.liquidity.totalDeposit);
        console.log("heldShares", state.withdrawals.heldShares);
        console.log("newHeldShares", state.withdrawals.newHeldShares);
        console.log("-------------------------------");
    }

    function debugStateIG(IG ig) public view {
        (
            uint256 maturity,
            uint256 currentStrike,
            ,
            /* Amount initialLiquidity */ uint256 kA,
            uint256 kB,
            uint256 theta,
            int256 limSup,
            int256 limInf,
            ,
            /* TimeLockedFinanceParameters timeLocked */ uint256 averageSigma,
            uint256 totalTradedNotional,
            uint256 sigmaZero
        ) = ig.financeParameters();
        console.log("----------IG STATE----------");
        console.log("maturity", maturity);
        console.log("currentStrike", currentStrike);
        // console.log("initialLiquidity", initialLiquidity);
        console.log("kA", kA);
        console.log("kB", kB);
        console.log("theta", theta);
        console.log("limSup");
        console.logInt(limSup);
        console.log("limInf");
        console.logInt(limInf);
        // console.log("timeLocked", timeLocked);
        console.log("averageSigma", averageSigma);
        console.log("totalTradedNotional", totalTradedNotional);
        console.log("sigmaZero", sigmaZero);
        console.log("----------------------------");
    }

    /**
        @notice Computes the amount of recoverable tokens when the vault die.
     */
    function getRecoverableAmounts(MockedVault vault) public view returns (uint256) {
        IERC20 baseToken = IERC20(vault.baseToken());
        uint256 balance = baseToken.balanceOf(address(vault));
        uint256 locked = vault.v0();
        uint256 pendingWithdrawals = vaultState(vault).liquidity.pendingWithdrawals;

        return balance - locked - pendingWithdrawals;
    }

    function addVaultDeposit(address user, uint256 amount, address tokenAdmin, address vaultAddress, Vm vm) internal {
        MockedVault vault = MockedVault(vaultAddress);
        TokenUtils.provideApprovedTokens(tokenAdmin, vault.baseToken(), user, vaultAddress, amount, vm);

        vm.prank(user);
        vault.deposit(amount, user, 0);
    }

    function logState(MockedVault vault) public view {
        VaultLib.VaultState memory state_ = VaultUtils.vaultState(vault);

        console.log("current epoch", vault.currentEpoch());
        uint256 baseBalance = IERC20(vault.baseToken()).balanceOf(address(vault));
        uint256 sideBalance = IERC20(vault.sideToken()).balanceOf(address(vault));
        console.log("baseToken balance", baseBalance);
        console.log("sideToken balance", sideBalance);
        console.log("dead", state_.dead);
        console.log("lockedInitially", state_.liquidity.lockedInitially);
        console.log("pendingDeposits", state_.liquidity.pendingDeposits);
        console.log("pendingWithdrawals", state_.liquidity.pendingWithdrawals);
        console.log("pendingPayoffs", state_.liquidity.pendingPayoffs);
        console.log("heldShares", state_.withdrawals.heldShares);
        console.log("newHeldShares", state_.withdrawals.newHeldShares);

        // console.log("notional");
        // console.log(vault.notional());

        (uint256 btAmount, uint256 stAmount) = vault.balances();
        console.log("base token notional", btAmount);
        console.log("side token notional", stAmount);
        console.log("----------------------------------------");
    }

    /// @dev Function used to skip coverage on this file
    function testCoverageSkip() public view {}
}
