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

library VaultUtils {

    /// @dev Test function to create a Vault with baseToken and sideToken
    function createMarket(address baseToken, address sideToken, uint256 epochFrequency, IRegistry registry) internal returns (Vault vault) {
        vault = new Vault(address(baseToken), address(sideToken), epochFrequency);
        registry.register(address(vault));
    }


    /// @dev Test function to give a certain amount of base tokens to a Vault
    function vaultState(IVault vault) internal view returns (VaultLib.VaultState memory) {
        (
            uint256 lockedLiquidity,
            ,
            bool lastLockedLiquidityZero,
            uint256 totalPendingLiquidity,
            uint256 totalWithdrawAmount,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead
        ) = vault.vaultState();
        return
            VaultLib.VaultState(
                VaultLib.VaultLiquidity(
                    lockedLiquidity,
                    lastLockedLiquidityZero,
                    totalPendingLiquidity,
                    totalWithdrawAmount
                ),
                VaultLib.VaultWithdrawals(
                    queuedWithdrawShares,
                    currentQueuedWithdrawShares
                ),
                dead
            );
    }

    /**
     * Function used to skip coverage on this file
     */
    function testCoverageSkip() private view {}
}
