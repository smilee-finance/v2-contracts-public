// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IFeeManager {
    /**
     * Calculate trade fee given notional and premium
     * @param notional The notional to apply fee
     * @param premium The premium to apply fee
     * @param tokenDecimals Decimals of token
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
     * Calculate trade fee given netPremia
     * @param netPerformance The net performance value to apply the fees
     * @param tokenDecimals Decimals of token
     * @return vaultFee The fee to pay
     */
    function calculateVaultFee(uint256 netPerformance, uint8 tokenDecimals) external view returns (uint256 vaultFee);

    /**
     * Receive fee from sender and record the value into account
     * @param feeAmount The amount transfered to the FeeManager
     */
    function receiveFee(uint256 feeAmount) external;

    /**
     *
     * @param receiver The address where fees will send to.
     * @param sender The address who has paid fees.
     * @param feeAmount The fee amount to withdraw.
     */
    function withdrawFee(address receiver, address sender, uint256 feeAmount) external;
}
