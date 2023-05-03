// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IVault {
    /**
        @notice Gives portfolio composition for currently active epoch
        @return baseTokenAmount The amount of baseToken currently locked in the vault
        @return sideTokenAmount The amount of sideToken currently locked in the vault
     */
    function getPortfolio() external view returns (uint256 baseTokenAmount, uint256 sideTokenAmount);

    /**
        @notice Deposits an `amount` of `baseToken` from msg.sender
        @dev The shares are not directly minted to the user. We need to wait for epoch change in order to know how many
             shares these assets correspond to. So shares are minted to the contract in `rollEpoch()` and owed to the
             depositor.
        @param amount The amount of `baseToken` to deposit
     */
    function deposit(uint256 amount) external;

    /**
        @notice Get wallet balance of actual owned shares and owed shares.
        @return heldByAccount The amount of shares owned by the wallet
        @return heldByVault The amount of shares owed to the wallet
     */
    function shareBalances(address account) external view returns (uint256 heldByAccount, uint256 heldByVault);

    // /**
    //     @notice A trigger to move on to next epoch
    //     @dev Should be called from the associated DVP which is in charge of managing epoch synchronization
    //  */
    // function rollEpoch() external;
}
