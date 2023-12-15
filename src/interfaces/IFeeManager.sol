// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IFeeManager {
    /**
        Computes trade fee given notional and premium
        @param dvp The DVP which is performing the trade.
        @param epoch The current epoch of the DVP
        @param notional The notional to apply fee
        @param premium The premium to apply fee
        @param tokenDecimals Decimals of token
        @return fee_ The fee to pay
     */
    function tradeBuyFee(
        address dvp,
        uint256 epoch,
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals
    ) external view returns (uint256 fee_);

    /**
        Computes trade fee given notional and premium
        @param dvp The DVP which is performing the trade.
        @param notional The notional to apply fee
        @param premium The premium to apply fee
        @param initialPaidPremium The premium paid by the user.
        @param tokenDecimals Decimals of token
        @param reachedMaturity Is used to apply different fees based on the maturity of the position itself.
        @return fee_ The fee to pay
     */
    function tradeSellFee(
        address dvp,
        uint256 notional,
        uint256 premium,
        uint256 initialPaidPremium,
        uint8 tokenDecimals,
        bool reachedMaturity
    ) external view returns (uint256 fee_);

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
