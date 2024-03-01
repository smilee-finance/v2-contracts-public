// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IVaultUser {
    /**
        @notice Provides liquidity for the next epoch
        @param amount The amount of base token to deposit
        @param receiver The wallet accounted for the deposit
        @param accessTokenId The id of the owned priority NFT, if necessary (use 0 if not needed)
        @dev The shares are not directly minted to the given wallet. We need to wait for epoch change in order to know
             how many shares these assets correspond to. Shares are minted to Vault contract in `rollEpoch()` and owed
             to the receiver of deposit
        @dev The receiver can redeem its shares after the next epoch is rolled
        @dev This Vault contract need to be approved on the base token contract before attempting this operation
     */
    function deposit(uint256 amount, address receiver, uint256 accessTokenId) external;
}
