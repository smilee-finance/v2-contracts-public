// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultParams} from "./IVaultParams.sol";
import {IEpochControls} from "./IEpochControls.sol";

interface IVault is IVaultParams {
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
        @notice Gives portfolio composition for currently active epoch
        @return baseTokenAmount The amount of baseToken currently locked in the vault
        @return sideTokenAmount The amount of sideToken currently locked in the vault
     */
    function balances() external view returns (uint256 baseTokenAmount, uint256 sideTokenAmount);

    /**
        @notice Gives the initial notional for the current epoch (base tokens)
        @return v0_ The number of base tokens available for issuing options
     */
    function v0() external view returns (uint256 v0_);

    /**
        @notice Deposits an `amount` of `baseToken` from msg.sender
        @dev The shares are not directly minted to the user. We need to wait for epoch change in order to know how many
        shares these assets correspond to. So shares are minted to the contract in `rollEpoch()` and owed to the depositor.
        @param amount The amount of `baseToken` to deposit
     */
    function deposit(uint256 amount) external;

    /**
        @notice Redeems shares held by the vault for the calling wallet
        @param shares is the number of shares to redeem
     */
    function redeem(uint256 shares) external;

    // /**
    //      @notice Enables withdraw assets deposited in the same epoch (withdraws using the outstanding
    //              `DepositReceipt.amount`)
    //      @param amount is the amount to withdraw
    //  */
    // function withdrawInstantly(uint256 amount) external;

    /**
        @notice Initiates a withdrawal that can be executed on epoch roll on
        @param shares is the number of shares to withdraw
     */
    function initiateWithdraw(uint256 shares) external;

    /**
        @notice Completes a scheduled withdrawal from a past epoch. Uses finalized share price for the epoch.
     */
    function completeWithdraw() external;

    /**
        @notice Get wallet balance of actual owned shares and owed shares.
        @return heldByAccount The amount of shares owned by the wallet
        @return heldByVault The amount of shares owed to the wallet
     */
    function shareBalances(address account) external view returns (uint256 heldByAccount, uint256 heldByVault);

    /**
        @notice Moves an amount of base tokens to a given wallet
        @dev Used to directly pay payoff to the given address without transferring it to DVP.
        @param recipient The address receiving the quantity
        @param amount The number of base tokens to move
     */
    function provideLiquidity(address recipient, uint256 amount) external;

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
     */
    function transferPayoff(address recipient, uint256 amount) external;
}
