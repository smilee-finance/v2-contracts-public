// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

library VaultLib {
    using SafeMath for uint256;

    uint256 constant DECIMALS = 18;
    uint256 constant UNIT_PRICE = 10 ** DECIMALS;

    struct VaultState {
        VaultLiquidity liquidity;
        VaultWithdrawals withdrawals;
        // Vault dies if ever the locked liquidity goes to zero (outstanding shares are worth 0, can't mint new shares ever)
        bool dead;
    }

    struct VaultLiquidity {
        // Liquidity currently used by associated DVP (without the side tokens value)
        uint256 locked;
        // Liquidity initially used by the associated DVP
        uint256 lockedInitially;
        // Liquidity from new deposits
        uint256 pendingDeposits;
        // Liquidity reserved for withdrawals
        uint256 pendingWithdrawals;
    }

    struct VaultWithdrawals {
        // Cumulated shares held by Vault for initiated withdraws (accounting purposes)
        uint256 heldShares;
        // Number of shares held by the contract because of inititateWithdraw() calls done during the current epoch
        uint256 newHeldShares;
    }

    struct DepositReceipt {
        uint256 epoch;
        uint256 amount;
        uint256 unredeemedShares;
    }

    struct Withdrawal {
        uint256 epoch; // Epoch in which the withdraw flow started
        uint256 shares; // Number of shares withdrawn
    }

    /**
        @notice Returns the number of shares corresponding to given amount of asset
        @param assetAmount The amount of assets to be converted to shares
        @param sharePrice The price (in asset) for 1 share
     */
    function assetToShares(uint256 assetAmount, uint256 sharePrice) public pure returns (uint256) {
        // If sharePrice goes to zero, the asset cannot minted, this means the assetAmount is to rescue
        if (sharePrice == 0) {
            return 0;
        }
        if (assetAmount == 0) {
            return 0;
        }

        return assetAmount.mul(UNIT_PRICE).div(sharePrice);
    }

    /**
        @notice Returns the amount of asset corresponding to given number of shares
        @param shares The number of shares to be converted to asset
        @param sharePrice The price (in asset) for 1 share
     */
    function sharesToAsset(uint256 shares, uint256 sharePrice) public pure returns (uint256) {
        return shares.mul(sharePrice).div(UNIT_PRICE);
    }

    function pricePerShare(uint256 assets, uint256 shares) public pure returns (uint256) {
        return assets.mul(UNIT_PRICE).div(shares);
    }

    /**
        @notice Returns the shares unredeemed by the user given their DepositReceipt
        @param depositReceipt is the user's deposit receipt
        @param currentEpoch is the `epoch` stored on the vault
        @param sharePrice is the price in asset per share with `DECIMALS` decimals
        @return unredeemedShares is the user's virtual balance of shares that are owed
     */
    function getSharesFromReceipt(
        DepositReceipt memory depositReceipt,
        uint256 currentEpoch,
        uint256 sharePrice
    ) public pure returns (uint256 unredeemedShares) {
        if (depositReceipt.epoch == 0 || depositReceipt.epoch == currentEpoch) {
            return depositReceipt.unredeemedShares;
        }

        uint256 sharesFromRound = assetToShares(depositReceipt.amount, sharePrice);
        return depositReceipt.unredeemedShares.add(sharesFromRound);
    }
}
