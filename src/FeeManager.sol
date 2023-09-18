// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";

// Add comments
// Add events
contract FeeManager is Ownable {
    using AmountsMath for uint256;

    /// @notice Fee percentage applied for each DVPs in WAD, it's used to calculate fees on notional
    uint256 public feePercentage;

    /// @notice CAP percentage, works like feePercentage in WAD, but it's used to calculate fees on premium.
    uint256 public capPercentage;

    /// @notice Fee percentage applied for each DVPs in WAD after maturity, it's used to calculate fees on notional
    uint256 public maturityFeePercentage;

    /// @notice CAP percentage, works like feePercentage in WAD after maturity, but it's used to calculate fees on premium.
    uint256 public maturityCapPercentage;

    constructor(
        uint256 feePercentage_,
        uint256 capPercentage_,
        uint256 maturityFeePercentage_,
        uint256 maturityCapPercentage_
    ) Ownable() {
        feePercentage = feePercentage_;
        capPercentage = capPercentage_;
        maturityFeePercentage = maturityFeePercentage_;
        maturityCapPercentage = maturityCapPercentage_;
    }

    function calculateTradeFee(
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals,
        bool reachedMaturity
    ) external view returns (uint256 fee_) {
        uint256 feeFromNotional;
        uint256 feeFromPremiumCap;
        notional = AmountsMath.wrapDecimals(notional, tokenDecimals);
        premium = AmountsMath.wrapDecimals(premium, tokenDecimals);

        if (reachedMaturity) {
            feeFromNotional = notional.wmul(maturityFeePercentage);
            feeFromPremiumCap = premium.wmul(maturityCapPercentage);
        } else {
            feeFromNotional = notional.wmul(feePercentage);
            feeFromPremiumCap = premium.wmul(capPercentage);
        }

        fee_ = (feeFromNotional < feeFromPremiumCap) ? feeFromNotional : feeFromPremiumCap;

        fee_ = AmountsMath.unwrapDecimals(fee_, tokenDecimals);
    }

    // TBD behaviour
    function notifyTransfer(address vault, uint256 feeAmount) public {}

    function setFeePercentage(uint256 feePercentage_) public onlyOwner {
        feePercentage = feePercentage_;
    }

    function setCapPercentage(uint256 capPercentage_) public onlyOwner {
        capPercentage = capPercentage_;
    }

    function setFeeMaturityPercentage(uint256 maturityFeePercentage_) public onlyOwner {
        maturityFeePercentage = maturityFeePercentage_;
    }

    function setCapMaturityPercentage(uint256 maturityCapPercentage_) public onlyOwner {
        maturityCapPercentage = maturityCapPercentage_;
    }
}
