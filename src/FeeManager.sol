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

    struct Params {
        // Minimum amount of fee paid for any trade (denominated in token decimals of the token used to pay the fee)
        uint256 minFee;
        // Fee percentage applied for each DVPs in WAD, it's used to calculate fees on notional
        uint256 feePercentage;
        // CAP percentage, works like feePercentage in WAD, but it's used to calculate fees on premium.
        uint256 capPercentage;
        // Fee percentage applied for each DVPs in WAD after maturity, it's used to calculate fees on notional
        uint256 maturityFeePercentage;
        // CAP percentage, works like feePercentage in WAD after maturity, but it's used to calculate fees on premium.
        uint256 maturityCapPercentage;
        // Fee Percentage applied for each Vault based on the netPerfomarce value
        uint256 vaultFeePercentage;
    }

    /// @notice Fee computation parameters
    Params private _params;

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

    constructor(Params memory params_) AccessControl() {
        _params.minFee = params_.minFee;
        _params.feePercentage = params_.feePercentage;
        _params.capPercentage = params_.capPercentage;
        _params.maturityFeePercentage = params_.maturityFeePercentage;
        _params.maturityCapPercentage = params_.maturityCapPercentage;
        _params.vaultFeePercentage = params_.vaultFeePercentage;

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    function getParams() external view returns (Params memory) {
        return _params;
    }

    /// @inheritdoc IFeeManager
    function tradeFee(
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals,
        bool reachedMaturity
    ) external view returns (uint256 fee) {
        uint256 feeFromNotional;
        uint256 feeFromPremiumCap;
        notional = AmountsMath.wrapDecimals(notional, tokenDecimals);
        premium = AmountsMath.wrapDecimals(premium, tokenDecimals);

        if (reachedMaturity) {
            feeFromNotional = notional.wmul(_params.maturityFeePercentage);
            feeFromPremiumCap = premium.wmul(_params.maturityCapPercentage);
        } else {
            feeFromNotional = notional.wmul(_params.feePercentage);
            feeFromPremiumCap = premium.wmul(_params.capPercentage);
        }

        fee = (feeFromNotional < feeFromPremiumCap) ? feeFromNotional : feeFromPremiumCap;
        fee = AmountsMath.unwrapDecimals(fee, tokenDecimals);
        if (fee < _params.minFee) {
            fee = _params.minFee;
        }
    }

    /// @inheritdoc IFeeManager
    function vaultFee(uint256 netPerformance, uint8 tokenDecimals) external view override returns (uint256 fee) {
        if (netPerformance <= 0) {
            return 0;
        }

        uint256 netPerformanceAbs = AmountsMath.wrapDecimals(uint256(netPerformance), tokenDecimals);

        fee = netPerformanceAbs.wmul(_params.vaultFeePercentage);
        fee = AmountsMath.unwrapDecimals(fee, tokenDecimals);
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
    function setMinFee(uint256 minFee_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousMinFee = _params.minFee;
        _params.minFee = minFee_;

        emit UpdateFeePercentage(minFee_, previousMinFee);
    }

    /// @notice Update fee percentage value
    function setFeePercentage(uint256 feePercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousFeePercentage = _params.feePercentage;
        _params.feePercentage = feePercentage_;

        emit UpdateFeePercentage(feePercentage_, previousFeePercentage);
    }

    /// @notice Update cap percentage value
    function setCapPercentage(uint256 capPercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousCapPercentage = _params.capPercentage;
        _params.capPercentage = capPercentage_;

        emit UpdateCapPercentage(capPercentage_, previousCapPercentage);
    }

    /// @notice Update fee percentage value at maturity
    function setFeeMaturityPercentage(uint256 maturityFeePercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousMaturityFeePercentage = _params.maturityFeePercentage;
        _params.maturityFeePercentage = maturityFeePercentage_;

        emit UpdateMaturityFeePercentage(maturityFeePercentage_, previousMaturityFeePercentage);
    }

    /// @notice Update cap percentage value at maturity
    function setCapMaturityPercentage(uint256 maturityCapPercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousMaturityCapPercentage = _params.maturityCapPercentage;
        _params.maturityCapPercentage = maturityCapPercentage_;

        emit UpdateMaturityCapPercentage(maturityCapPercentage_, previousMaturityCapPercentage);
    }

    /// @notice Update vault fee percentage value
    function setVaultFeePercentage(uint256 vaultFeePercentage_) public {
        _checkRole(ROLE_ADMIN);
        // ToDo: check range
        uint256 previousVaultFeePercentage = _params.vaultFeePercentage;
        _params.vaultFeePercentage = vaultFeePercentage_;

        emit UpdateVaultFeePercentage(vaultFeePercentage_, previousVaultFeePercentage);
    }

    /// @dev Get IERC20Metadata of baseToken of given sender
    function _getBaseTokenInfo(address sender) internal view returns (IERC20Metadata token) {
        token = IERC20Metadata(IVaultParams(sender).baseToken());
    }
}
