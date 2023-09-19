// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

// Add events
contract FeeManager is IFeeManager, Ownable {
    using AmountsMath for uint256;

    /// @notice Fee percentage applied for each DVPs in WAD, it's used to calculate fees on notional
    uint256 public feePercentage;

    /// @notice CAP percentage, works like feePercentage in WAD, but it's used to calculate fees on premium.
    uint256 public capPercentage;

    /// @notice Fee percentage applied for each DVPs in WAD after maturity, it's used to calculate fees on notional
    uint256 public maturityFeePercentage;

    /// @notice CAP percentage, works like feePercentage in WAD after maturity, but it's used to calculate fees on premium.
    uint256 public maturityCapPercentage;

    event UpdateFeePercentage(uint256 previous, uint256 fee);
    event UpdateCapPercentage(uint256 previous, uint256 fee);
    event UpdateFeePercentageMaturity(uint256 previous, uint256 fee);
    event UpdateCapPercentageMaturity(uint256 previous, uint256 fee);

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

    /// @inheritdoc IFeeManager
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
    /// @inheritdoc IFeeManager
    function notifyTransfer(address vault, uint256 feeAmount) public {}

    /// @notice Change fee percentage value
    function setFeePercentage(uint256 feePercentage_) public onlyOwner {
        uint256 feePercentageOld = feePercentage;
        feePercentage = feePercentage_;
        emit UpdateFeePercentage(feePercentageOld, feePercentage);
    }

    /// @notice Change cap percentage value
    function setCapPercentage(uint256 capPercentage_) public onlyOwner {
        uint256 capPercentageOld = capPercentage;
        capPercentage = capPercentage_;
        emit UpdateCapPercentage(capPercentageOld, capPercentageOld);
    }

    /// @notice Change fee percentage value at maturity
    function setFeeMaturityPercentage(uint256 maturityFeePercentage_) public onlyOwner {
        uint256 maturityFeePercentageOld = maturityFeePercentage;
        maturityFeePercentage = maturityFeePercentage_;
        emit UpdateFeePercentageMaturity(maturityFeePercentageOld, maturityFeePercentage);
    }

    /// @notice Change cap percentage value at maturity
    function setCapMaturityPercentage(uint256 maturityCapPercentage_) public onlyOwner {
        uint256 maturityCapPercentageOld = maturityCapPercentage;
        maturityCapPercentage = maturityCapPercentage_;
        emit UpdateCapPercentageMaturity(maturityCapPercentageOld, maturityCapPercentageOld);
    }
}
