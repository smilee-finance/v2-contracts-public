// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IVaultParams} from "./interfaces/IVaultParams.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";

contract FeeManager is IFeeManager, AccessControl {
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

    /// @notice Fee Percentage applied for each Vault based on the netPerfomarce value
    uint256 public vaultFeePercentage;

    /// @notice Fee account per sender
    mapping(address => uint256) public senders;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    event UpdateFeePercentage(uint256 fee, uint256 previous);
    event UpdateCapPercentage(uint256 fee, uint256 previous);
    event UpdateMaturityFeePercentage(uint256 fee, uint256 previous);
    event UpdateMaturityCapPercentage(uint256 fee, uint256 previous);
    event UpdateVaultFeePercentage(uint256 fee, uint256 previous);
    event ReceiveFee(address sender, uint256 amount);
    event WithdrawFee(address receiver, address sender, uint256 amount);

    error NoEnoughFundsFromSender();

    constructor(
        uint256 feePercentage_,
        uint256 capPercentage_,
        uint256 maturityFeePercentage_,
        uint256 maturityCapPercentage_,
        uint256 vaultFeePercentage_
    ) AccessControl() {
        feePercentage = feePercentage_;
        capPercentage = capPercentage_;
        maturityFeePercentage = maturityFeePercentage_;
        maturityCapPercentage = maturityCapPercentage_;
        vaultFeePercentage = vaultFeePercentage_;

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
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
    function calculateVaultFee(
        uint256 netPerformance,
        uint8 tokenDecimals
    ) external view override returns (uint256 vaultFee) {
        if (netPerformance <= 0) {
            return 0;
        }

        uint256 netPerformanceAbs = AmountsMath.wrapDecimals(uint256(netPerformance), tokenDecimals);

        vaultFee = netPerformanceAbs.wmul(vaultFeePercentage);
        vaultFee = AmountsMath.unwrapDecimals(vaultFee, tokenDecimals);
    }

    /// @inheritdoc IFeeManager
    function receiveFee(uint256 feeAmount) external {
        _getBaseTokenInfo(msg.sender).safeTransferFrom(msg.sender, address(this), feeAmount);
        senders[msg.sender] += feeAmount;

        emit ReceiveFee(msg.sender, feeAmount);
    }

    /// @inheritdoc IFeeManager
    function withdrawFee(address receiver, address sender, uint256 feeAmount) external {
        _checkRole(ROLE_ADMIN);
        if (senders[sender] < feeAmount) {
            revert NoEnoughFundsFromSender();
        }

        senders[sender] -= feeAmount;
        _getBaseTokenInfo(sender).safeTransfer(receiver, feeAmount);

        emit WithdrawFee(receiver, sender, feeAmount);
    }

    /// @notice Update fee percentage value
    function setFeePercentage(uint256 feePercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousFeePercentage = feePercentage;
        feePercentage = feePercentage_;

        emit UpdateFeePercentage(feePercentage, previousFeePercentage);
    }

    /// @notice Update cap percentage value
    function setCapPercentage(uint256 capPercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousCapPercentage = capPercentage;
        capPercentage = capPercentage_;

        emit UpdateCapPercentage(capPercentage, previousCapPercentage);
    }

    /// @notice Update fee percentage value at maturity
    function setFeeMaturityPercentage(uint256 maturityFeePercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousMaturityFeePercentage = maturityFeePercentage;
        maturityFeePercentage = maturityFeePercentage_;

        emit UpdateMaturityFeePercentage(maturityFeePercentage, previousMaturityFeePercentage);
    }

    /// @notice Update cap percentage value at maturity
    function setCapMaturityPercentage(uint256 maturityCapPercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousMaturityCapPercentage = maturityCapPercentage;
        maturityCapPercentage = maturityCapPercentage_;

        emit UpdateMaturityCapPercentage(maturityCapPercentage, previousMaturityCapPercentage);
    }

    /// @notice Update vault fee percentage value
    function setVaultFeePercentage(uint256 vaultFeePercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousVaultFeePercentage = vaultFeePercentage;
        vaultFeePercentage = vaultFeePercentage_;

        emit UpdateVaultFeePercentage(vaultFeePercentage, previousVaultFeePercentage);
    }

    /// @dev Get IERC20Metadata of baseToken of given sender
    function _getBaseTokenInfo(address sender) internal view returns (IERC20Metadata token) {
        token = IERC20Metadata(IVaultParams(sender).baseToken());
    }
}
