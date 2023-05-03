// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

library VaultLib {
    using SafeMath for uint256;

    uint256 constant DECIMALS = 18;
    uint256 constant UNIT_PRICE = 10 ** DECIMALS;

    struct Withdrawal {
        uint256 epoch;
        uint256 shares; // Number of shares withdrawn
    }

    struct VaultState {
        uint256 lockedLiquidity; // liquidity currently used by associated DVP
        uint256 totalPendingLiquidity; // liquidity deposited during current epoch (to be locked on the next one)
    }

    struct DepositReceipt {
        uint256 epoch;
        uint256 amount;
        uint256 unredeemedShares;
    }

    function assetToShares(uint256 assetAmount, uint256 assetPerShare) internal pure returns (uint256) {
        return assetAmount.mul(10 ** DECIMALS).div(assetPerShare);
    }

    /**
     * @notice Returns the shares unredeemed by the user given their DepositReceipt
     * @param depositReceipt is the user's deposit receipt
     * @param currentEpoch is the `epoch` stored on the vault
     * @param sharePrice is the price in asset per share with `DECIMALS` decimals
     * @return unredeemedShares is the user's virtual balance of shares that are owed
     */
    function getSharesFromReceipt(
        DepositReceipt memory depositReceipt,
        uint256 currentEpoch,
        uint256 sharePrice
    ) internal pure returns (uint256 unredeemedShares) {
        if (depositReceipt.epoch > 0 && depositReceipt.epoch < currentEpoch) {
            uint256 sharesFromRound = assetToShares(depositReceipt.amount, sharePrice);

            return uint256(depositReceipt.unredeemedShares).add(sharesFromRound);
        }
        return depositReceipt.unredeemedShares;
    }
}
