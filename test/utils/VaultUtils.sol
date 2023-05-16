// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {TokenUtils} from "./TokenUtils.sol";
import {Vault} from "../../src/Vault.sol";
import {EpochFrequency} from "../../src/lib/EpochFrequency.sol";
import {VaultLib} from "../../src/lib/VaultLib.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {Registry} from "../../src/Registry.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";

library VaultUtils {

    function createVaultFromNothing(uint256 epochFrequency, address admin, Vm vm) internal returns (Vault) {
        vm.startPrank(admin);

        Registry registry = new Registry();

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

        Vault vault = new Vault(baseToken, sideToken, epochFrequency, address(_ap));
        registry.register(address(vault));

        vm.stopPrank();

        return vault;
    }

    /// @dev Builds and returns a `VaultLib.VaultState` with info on current vault state
    function vaultState(IVault vault) internal view returns (VaultLib.VaultState memory) {
        (
            uint256 lockedLiquidity,
            uint256 totalWithdrawAmount,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead
        ) = vault.vaultState();
        return
            VaultLib.VaultState(
                VaultLib.VaultLiquidity(
                    lockedLiquidity,
                    0,
                    totalWithdrawAmount
                ),
                VaultLib.VaultWithdrawals(queuedWithdrawShares, currentQueuedWithdrawShares),
                dead
            );
    }

    /**
        @notice Computes the amount of recoverable tokens when the vault die.
     */
    function getRecoverableAmounts(Vault vault) public view returns (uint256) {
        TestnetToken baseToken = TestnetToken(vault.baseToken());
        uint256 balance = baseToken.balanceOf(address(vault));
        uint256 locked = vaultState(vault).liquidity.locked;
        uint256 pendingWithdrawals = vaultState(vault).liquidity.pendingWithdrawals;

        return balance - locked - pendingWithdrawals;
    }

    /**
     * Function used to skip coverage on this file
     */
    function testCoverageSkip() private view {}
}
