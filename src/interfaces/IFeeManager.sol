// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IFeeManager {
    /**
     * Calculate trade fee given notional and premium
     * @param notional The notional to apply fee
     * @param premium The premium to apply fee
     * @param tokenDecimals The token decimals
     * @param reachedMaturity Is used to apply different fees based on the maturity of the position itself.
     * @return fee_ The fee to pay
     */
    function calculateTradeFee(
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals,
        bool reachedMaturity
    ) external view returns (uint256 fee_);

    /**
     * Notify that fee has been transfered to the FeeManager
     * @param vault The vault address
     * @param feeAmount The amount transfered to the FeeManager
     */
    function notifyTransfer(address vault, uint256 feeAmount) external;
}
