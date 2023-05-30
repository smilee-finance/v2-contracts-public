// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IVaultParams} from "./IVaultParams.sol";

// TBD: extend IEpochControls as the interface client (DVP) also needs rollEpoch and epochFrequency.
// TBD: the DVP is the one receiving an already deployed vault, hence it doesn't really needs this interface...
/**
    Seam point for Vault usage by a DVP.
 */
interface IVault is IVaultParams {
    // ToDo: review in order to keep only the state needed by the DVP (e.g. dead).
    function vaultState()
        external
        view
        returns (
            uint256 lockedLiquidityInitially,
            uint256 pendingDeposits,
            uint256 totalWithdrawAmount,
            uint256 pendingPayoffs,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead
        );

    /**
        @notice Gives the initial notional for the current epoch (base tokens)
        @return v0_ The number of base tokens available for issuing options
     */
    function v0() external view returns (uint256 v0_);

    /**
        TODOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
     */
    function deltaHedge(int256 sideTokensAmount) external;

    /**
        @notice Update Vault State with the amount of reserved payoff
     */
    function reservePayoff(uint256 residualPayoff) external;

    /**
        @notice Tranfer an amount of reserved payoff to the user
        @param recipient The address receiving the quantity
        @param amount The number of base tokens to move
        @param isPastEpoch TODO
     */
    function transferPayoff(address recipient, uint256 amount, bool isPastEpoch) external;
}
