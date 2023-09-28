// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IVaultParams} from "./interfaces/IVaultParams.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";

contract FeeManager is IFeeManager, Ownable {
    using AmountsMath for uint256;
    using SafeERC20 for IERC20Metadata;

    /// @notice Fee percentage applied for each DVPs in WAD, it's used to calculate fees on notional
    uint256 public feePercentage;

    /// @notice CAP percentage, works like feePercentage in WAD, but it's used to calculate fees on premium.
    uint256 public capPercentage;

    /// @notice Fee percentage applied for each DVPs in WAD after maturity, it's used to calculate fees on notional
    uint256 public maturityFeePercentage;

    /// @notice CAP percentage, works like feePercentage in WAD after maturity, but it's used to calculate fees on premium.
    uint256 public maturityCapPercentage;

    /// @notice Fee Percentage applied for each Vault based on the netPremia value
    uint256 public vaultAPYFeePercentage;

    /// @notice Fee account per sender
    mapping(address => uint256) public senders;

    event UpdateFeePercentage(uint256 fee, uint256 previous);
    event UpdateCapPercentage(uint256 fee, uint256 previous);
    event UpdateFeePercentageMaturity(uint256 fee, uint256 previous);
    event UpdateCapPercentageMaturity(uint256 fee, uint256 previous);
    event UpdateVaultAPYFeePercentage(uint256 fee, uint256 previous);
    event FeeReceived(address sender, uint256 amount);
    event FeeWithdrawed(address receiver, address sender, uint256 amount);

    error NoEnoughFundsFromSender();

    constructor(
        uint256 feePercentage_,
        uint256 capPercentage_,
        uint256 maturityFeePercentage_,
        uint256 maturityCapPercentage_,
        uint256 vaultAPYFeePercentage_
    ) Ownable() {
        feePercentage = feePercentage_;
        capPercentage = capPercentage_;
        maturityFeePercentage = maturityFeePercentage_;
        maturityCapPercentage = maturityCapPercentage_;
        vaultAPYFeePercentage = vaultAPYFeePercentage_;
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

    /// @inheritdoc IFeeManager
    function calculateVaultAPYFee(
        int256 netPremia,
        uint8 tokenDecimals
    ) external view override returns (uint256 vaultAPYFee) {
        if (netPremia <= 0) {
            return 0;
        }

        uint256 netPremiaAbs = AmountsMath.wrapDecimals(uint256(netPremia), tokenDecimals);

        vaultAPYFee = netPremiaAbs.wmul(vaultAPYFeePercentage);
        vaultAPYFee = AmountsMath.unwrapDecimals(vaultAPYFee, tokenDecimals);
    }

    // TBD behaviour
    /// @inheritdoc IFeeManager
    function receiveFee(uint256 feeAmount) external {
        address sender = msg.sender;

        _getBaseTokenInfo(sender).safeTransferFrom(sender, address(this), feeAmount);
        senders[sender] += feeAmount;

        emit FeeReceived(sender, feeAmount);
    }

    function withdrawFee(address receiver, address sender, uint256 feeAmount) external onlyOwner {
        uint256 storedFeeSender = senders[sender];
        if (storedFeeSender < feeAmount) {
            revert NoEnoughFundsFromSender();
        }

        senders[sender] -= feeAmount;
        _getBaseTokenInfo(sender).safeTransfer(receiver, feeAmount);

        emit FeeWithdrawed(receiver, sender, feeAmount);
    }

    /// @notice Update fee percentage value
    function setFeePercentage(uint256 feePercentage_) public onlyOwner {
        // ToDo: check range
        uint256 previousFeePercentage = feePercentage;
        feePercentage = feePercentage_;

        emit UpdateFeePercentage(feePercentage, previousFeePercentage);
    }

    /// @notice Update cap percentage value
    function setCapPercentage(uint256 capPercentage_) public onlyOwner {
        // ToDo: check range
        uint256 previousCapPercentage = capPercentage;
        capPercentage = capPercentage_;

        emit UpdateCapPercentage(capPercentage, previousCapPercentage);
    }

    /// @notice Update fee percentage value at maturity
    function setFeeMaturityPercentage(uint256 maturityFeePercentage_) public onlyOwner {
        // ToDo: check range
        uint256 previousMaturityFeePercentage = maturityFeePercentage;
        maturityFeePercentage = maturityFeePercentage_;

        emit UpdateFeePercentageMaturity(maturityFeePercentage, previousMaturityFeePercentage);
    }

    /// @notice Update cap percentage value at maturity
    function setCapMaturityPercentage(uint256 maturityCapPercentage_) public onlyOwner {
        // ToDo: check range
        uint256 previousMaturityCapPercentage = maturityCapPercentage;
        maturityCapPercentage = maturityCapPercentage_;

        emit UpdateCapPercentageMaturity(maturityCapPercentage, previousMaturityCapPercentage);
    }

    function setVaultAPYFeePercentage(uint256 vaultAPYFeePercentage_) public onlyOwner {
        uint256 previousVaultAPYFeePercentage = vaultAPYFeePercentage;
        vaultAPYFeePercentage = vaultAPYFeePercentage_;

        emit UpdateCapPercentageMaturity(vaultAPYFeePercentage, previousVaultAPYFeePercentage);
    }

    function _getBaseTokenInfo(address sender) internal view returns (IERC20Metadata token) {
        token = IERC20Metadata(IVaultParams(sender).baseToken());
    }
}
