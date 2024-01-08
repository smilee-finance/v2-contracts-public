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

    struct FeeParams {
        // Seconds remaining until the next epoch to determine which minFee to use.
        uint256 timeToExpiryThreshold;
        // Minimum amount of fee paid for any buy trade made before the threshold time (denominated in token decimals of the token used to pay the fee).
        uint256 minFeeBeforeTimeThreshold;
        // Minimum amount of fee paid for any buy trade made after the threshold time  (denominated in token decimals of the token used to pay the fee).
        uint256 minFeeAfterTimeThreshold;
        // Percentage to be appied to the PNL of the sell.
        uint256 successFeeTier;
        // The minimum fee paid for any sell trade that hasn't reached maturity.
        uint256 vaultSellMinFee;
        // Fee percentage applied for each DVPs in WAD, it's used to calculate fees on notional.
        uint256 feePercentage;
        // CAP percentage, works like feePercentage in WAD, but it's used to calculate fees on premium.
        uint256 capPercentage;
        // Fee percentage applied for each DVPs in WAD after maturity, it's used to calculate fees on notional.
        uint256 maturityFeePercentage;
        // CAP percentage, works like feePercentage in WAD after maturity, but it's used to calculate fees on premium.
        uint256 maturityCapPercentage;
    }

    /// @notice Fee for each dvp
    mapping(address => FeeParams) public dvpsFeeParams;

    /// @notice Fee account per sender
    mapping(address => uint256) public senders;

    /// @notice Fee account per vault
    mapping(address => uint256) public vaultFeeAmounts;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    event UpdateTimeToExpiryThreshold(address dvp, uint256 timeToExpiryThreshold, uint256 previous);
    event UpdateMinFeeBeforeTimeThreshold(address dvp, uint256 minFeeBeforeTimeThreshold, uint256 previous);
    event UpdateMinFeeAfterTimeThreshold(address dvp, uint256 minFeeAfterTimeThreshold, uint256 previous);
    event UpdateVaultSellMinFee(address dvp, uint256 minFeeAfterTimeThreshold, uint256 previous);
    event UpdateSuccessFeeTier(address dvp, uint256 minFeeAfterTimeThreshold, uint256 previous);
    event UpdateFeePercentage(address dvp, uint256 fee, uint256 previous);
    event UpdateCapPercentage(address dvp, uint256 fee, uint256 previous);
    event UpdateMaturityFeePercentage(address dvp, uint256 fee, uint256 previous);
    event UpdateMaturityCapPercentage(address dvp, uint256 fee, uint256 previous);
    event ReceiveFee(address sender, uint256 amount);
    event WithdrawFee(address receiver, address sender, uint256 amount);
    event TransferVaultFee(address vault, uint256 feeAmount);

    error NoEnoughFundsFromSender();
    error OutOfAllowedRange();

    constructor() AccessControl() {
        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);
        _grantRole(ROLE_GOD, msg.sender);
        _grantRole(ROLE_ADMIN, msg.sender);

        // renounceRole(ROLE_ADMIN, msg.sender);
    }

    /**
        Set fee params for the given dvp.
        @param dvp The address of the DVP
        @param params The Fee Params to be set
     */
    function setDVPFee(address dvp, FeeParams calldata params) external {
        _checkRole(ROLE_ADMIN);

        _setTimeToExpiryThreshold(dvp, params.timeToExpiryThreshold);
        _setMinFeeBeforeTimeThreshold(dvp, params.minFeeBeforeTimeThreshold);
        _setMinFeeAfterTimeThreshold(dvp, params.minFeeAfterTimeThreshold);
        _setVaultSellMinFee(dvp, params.vaultSellMinFee);
        _setSuccessFeeTier(dvp, params.successFeeTier);
        _setFeePercentage(dvp, params.feePercentage);
        _setCapPercentage(dvp, params.capPercentage);
        _setMaturityFeePercentage(dvp, params.maturityFeePercentage);
        _setMaturityCapPercentage(dvp, params.maturityCapPercentage);
    }

    /// @inheritdoc IFeeManager
    function tradeBuyFee(
        address dvp,
        uint256 epoch,
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals
    ) external view returns (uint256 fee, uint256 minFee) {
        fee = _getFeeFromNotionalAndPremium(dvp, notional, premium, tokenDecimals, false);

        minFee = epoch - block.timestamp > dvpsFeeParams[dvp].timeToExpiryThreshold
            ? dvpsFeeParams[dvp].minFeeBeforeTimeThreshold
            : dvpsFeeParams[dvp].minFeeAfterTimeThreshold;

        if (fee < minFee) {
            fee = minFee;
        }
    }

    /// @inheritdoc IFeeManager
    function tradeSellFee(
        address dvp,
        uint256 notional,
        uint256 currPremium,
        uint256 entryPremium,
        uint8 tokenDecimals,
        bool expired
    ) external view returns (uint256 fee, uint256 vaultMinFee) {
        fee = _getFeeFromNotionalAndPremium(dvp, notional, currPremium, tokenDecimals, expired);

        if (currPremium > entryPremium) {
            uint256 pnl = currPremium - entryPremium;
            fee += pnl.wmul(dvpsFeeParams[dvp].successFeeTier);
        }

        if (!expired) {
            vaultMinFee = dvpsFeeParams[dvp].vaultSellMinFee;
            fee += vaultMinFee;
        }
    }

    function _getFeeFromNotionalAndPremium(
        address dvp,
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals,
        bool expired
    ) internal view returns (uint256 fee) {
        uint256 feeFromNotional;
        uint256 feeFromPremiumCap;
        notional = AmountsMath.wrapDecimals(notional, tokenDecimals);
        premium = AmountsMath.wrapDecimals(premium, tokenDecimals);

        if (expired) {
            feeFromNotional = notional.wmul(dvpsFeeParams[dvp].maturityFeePercentage);
            feeFromPremiumCap = premium.wmul(dvpsFeeParams[dvp].maturityCapPercentage);
        } else {
            feeFromNotional = notional.wmul(dvpsFeeParams[dvp].feePercentage);
            feeFromPremiumCap = premium.wmul(dvpsFeeParams[dvp].capPercentage);
        }

        fee = (feeFromNotional < feeFromPremiumCap) ? feeFromNotional : feeFromPremiumCap;
        fee = AmountsMath.unwrapDecimals(fee, tokenDecimals);
    }

    /// @inheritdoc IFeeManager
    function receiveFee(uint256 feeAmount) external {
        _getBaseTokenInfo(msg.sender).safeTransferFrom(msg.sender, address(this), feeAmount);
        senders[msg.sender] += feeAmount;

        emit ReceiveFee(msg.sender, feeAmount);
    }

    /// @inheritdoc IFeeManager
    function trackVaultFee(address vault, uint256 feeAmount) public {
        vaultFeeAmounts[vault] += feeAmount;

        emit TransferVaultFee(vault, feeAmount);
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

    /// @notice Update time to expiry threshold value
    function _setTimeToExpiryThreshold(address dvp, uint256 timeToExpiryThreshold) internal {
        if (timeToExpiryThreshold == 0) {
            revert OutOfAllowedRange();
        }

        uint256 previousTimeToExpiryThreshold = dvpsFeeParams[dvp].timeToExpiryThreshold;
        dvpsFeeParams[dvp].timeToExpiryThreshold = timeToExpiryThreshold;

        emit UpdateTimeToExpiryThreshold(dvp, timeToExpiryThreshold, previousTimeToExpiryThreshold);
    }

    /// @notice Update fee percentage value
    function _setMinFeeBeforeTimeThreshold(address dvp, uint256 minFee) internal {
        if (minFee > 5e6) {
            // calibrated on USDC
            revert OutOfAllowedRange();
        }

        uint256 previousMinFee = dvpsFeeParams[dvp].minFeeBeforeTimeThreshold;
        dvpsFeeParams[dvp].minFeeBeforeTimeThreshold = minFee;

        emit UpdateMinFeeBeforeTimeThreshold(dvp, minFee, previousMinFee);
    }

    /// @notice Update fee percentage value
    function _setMinFeeAfterTimeThreshold(address dvp, uint256 minFee) internal {
        if (minFee > 5e6) {
            // calibrated on USDC
            revert OutOfAllowedRange();
        }

        uint256 previousMinFee = dvpsFeeParams[dvp].minFeeAfterTimeThreshold;
        dvpsFeeParams[dvp].minFeeAfterTimeThreshold = minFee;

        emit UpdateMinFeeAfterTimeThreshold(dvp, minFee, previousMinFee);
    }

    /// @notice Update fee percentage value
    function _setVaultSellMinFee(address dvp, uint256 vaultSellMinFee) internal {
        if (vaultSellMinFee > 5e6) {
            // calibrated on USDC
            revert OutOfAllowedRange();
        }

        uint256 previousVaultSellMinFee = dvpsFeeParams[dvp].vaultSellMinFee;
        dvpsFeeParams[dvp].vaultSellMinFee = vaultSellMinFee;

        emit UpdateVaultSellMinFee(dvp, vaultSellMinFee, previousVaultSellMinFee);
    }

    /// @notice Update fee percentage value
    function _setSuccessFeeTier(address dvp, uint256 successFeeTier) internal {
        if (successFeeTier > 10e17) {
            // calibrated on USDC
            revert OutOfAllowedRange();
        }

        uint256 previousSuccessFeeTier = dvpsFeeParams[dvp].successFeeTier;
        dvpsFeeParams[dvp].successFeeTier = successFeeTier;

        emit UpdateSuccessFeeTier(dvp, successFeeTier, previousSuccessFeeTier);
    }

    /// @notice Update fee percentage value
    function _setFeePercentage(address dvp, uint256 feePercentage_) internal {
        if (feePercentage_ > 5e22) {
            revert OutOfAllowedRange();
        }

        uint256 previousFeePercentage = dvpsFeeParams[dvp].feePercentage;
        dvpsFeeParams[dvp].feePercentage = feePercentage_;

        emit UpdateFeePercentage(dvp, feePercentage_, previousFeePercentage);
    }

    /// @notice Update cap percentage value
    function _setCapPercentage(address dvp, uint256 capPercentage_) internal {
        if (capPercentage_ > 5e22) {
            revert OutOfAllowedRange();
        }

        uint256 previousCapPercentage = dvpsFeeParams[dvp].capPercentage;
        dvpsFeeParams[dvp].capPercentage = capPercentage_;

        emit UpdateCapPercentage(dvp, capPercentage_, previousCapPercentage);
    }

    /// @notice Update fee percentage value at maturity
    function _setMaturityFeePercentage(address dvp, uint256 maturityFeePercentage_) internal {
        if (maturityFeePercentage_ > 5e22) {
            revert OutOfAllowedRange();
        }

        uint256 previousMaturityFeePercentage = dvpsFeeParams[dvp].maturityFeePercentage;
        dvpsFeeParams[dvp].maturityFeePercentage = maturityFeePercentage_;

        emit UpdateMaturityFeePercentage(dvp, maturityFeePercentage_, previousMaturityFeePercentage);
    }

    /// @notice Update cap percentage value at maturity
    function _setMaturityCapPercentage(address dvp, uint256 maturityCapPercentage_) internal {
        if (maturityCapPercentage_ > 5e22) {
            revert OutOfAllowedRange();
        }

        uint256 previousMaturityCapPercentage = dvpsFeeParams[dvp].maturityCapPercentage;
        dvpsFeeParams[dvp].maturityCapPercentage = maturityCapPercentage_;

        emit UpdateMaturityCapPercentage(dvp, maturityCapPercentage_, previousMaturityCapPercentage);
    }

    /// @dev Get IERC20Metadata of baseToken of given sender
    function _getBaseTokenInfo(address sender) internal view returns (IERC20Metadata token) {
        token = IERC20Metadata(IVaultParams(sender).baseToken());
    }
}
