// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IVaultParams} from "./IVaultParams.sol";

/**
    Seam point for Vault usage by a DVP.
 */
interface IVault is IVaultParams {
    /**
        @notice Gives the initial notional for the current epoch (base tokens)
        @return v0_ The number of base tokens available for issuing options
     */
    function v0() external view returns (uint256 v0_);

    /**
        @notice Adjusts the portfolio by trading the given amount of side tokens
        @param sideTokensAmount The amount of side tokens to buy (positive value) / sell (negative value)
        @return baseTokens The amount of exchanged base tokens
     */
    function deltaHedge(int256 sideTokensAmount) external returns (uint256 baseTokens);

    /**
        @notice Updates Vault State with the amount of reserved payoff
     */
    function reservePayoff(uint256 residualPayoff) external;

    /**
        @notice Tranfers an amount of reserved payoff to the user
        @param recipient The address receiving the quantity
        @param amount The number of base tokens to move
        @param isPastEpoch Flag to tell if the payoff is for an expired position
     */
    function transferPayoff(address recipient, uint256 amount, bool isPastEpoch) external;

}
