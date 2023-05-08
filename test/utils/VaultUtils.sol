// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {TokenUtils} from "./TokenUtils.sol";
import {VaultLib} from "../../src/lib/VaultLib.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";

library VaultUtils {
    /// @dev Test function to give a certain amount of base tokens to a Vault
    function vaultState(IVault vault) internal view returns (VaultLib.VaultState memory) {
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
        return
            VaultLib.VaultState(
                lockedLiquidity,
                lastLockedLiquidity,
                lastLockedLiquidityZero,
                totalPendingLiquidity,
                totalWithdrawAmount,
                queuedWithdrawShares,
                currentQueuedWithdrawShares,
                dead
            );
    }
}
