// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {VaultLib} from "../../src/lib/VaultLib.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {Registry} from "../../src/Registry.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {MockedVault} from "../mock/MockedVault.sol";
import {TokenUtils} from "./TokenUtils.sol";

library VaultUtils {
    function createVaultFromNothing(uint256 epochFrequency, address admin, Vm vm) internal returns (address) {
        vm.prank(admin);
        Registry registry = new Registry();
        return createVaultWithRegistry(epochFrequency, admin, vm, registry);
    }

    function createVaultWithRegistry(
        uint256 epochFrequency,
        address admin,
        Vm vm,
        IRegistry registry
    ) internal returns (address) {
        vm.startPrank(admin);

        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        address baseToken = address(token);
        token.setController(address(registry));

        AddressProvider _ap = new AddressProvider();

        TestnetPriceOracle priceOracle = new TestnetPriceOracle(baseToken);
        _ap.setPriceOracle(address(priceOracle));

        TestnetSwapAdapter exchange = new TestnetSwapAdapter(address(priceOracle));
        _ap.setExchangeAdapter(address(exchange));
        token.setSwapper(address(exchange));

        token = new TestnetToken("Testnet WETH", "stWETH");
        token.setController(address(registry));
        token.setSwapper(address(exchange));
        address sideToken = address(token);
        priceOracle.setTokenPrice(sideToken, 1 ether);

        MockedVault vault = new MockedVault(baseToken, sideToken, epochFrequency, address(_ap));
        registry.register(address(vault));

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
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead
        ) = vault.vaultState();
        return
            VaultLib.VaultState(
                VaultLib.VaultLiquidity(lockedInitially, pendingDepositAmount, totalWithdrawAmount, pendingPayoffs, 0),
                VaultLib.VaultWithdrawals(queuedWithdrawShares, currentQueuedWithdrawShares),
                dead
            );
    }

    /**
        @notice Computes the amount of recoverable tokens when the vault die.
     */
    function getRecoverableAmounts(MockedVault vault) public view returns (uint256) {
        TestnetToken baseToken = TestnetToken(vault.baseToken());
        uint256 balance = baseToken.balanceOf(address(vault));
        uint256 locked = vault.v0();
        uint256 pendingWithdrawals = vaultState(vault).liquidity.pendingWithdrawals;

        return balance - locked - pendingWithdrawals;
    }

    function addVaultDeposit(address user, uint256 amount, address tokenAdmin, address vaultAddress, Vm vm) internal {
        MockedVault vault = MockedVault(vaultAddress);
        TokenUtils.provideApprovedTokens(tokenAdmin, vault.baseToken(), user, vaultAddress, amount, vm);

        vm.prank(user);
        vault.deposit(amount);
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
