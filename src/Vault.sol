// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {VaultLib} from "./lib/VaultLib.sol";
import {EpochControls} from "./EpochControls.sol";

contract Vault is EpochControls, ERC20, IVault {
    using SafeMath for uint256;
    using VaultLib for VaultLib.DepositReceipt;

    address public immutable baseToken;
    address public immutable sideToken;

    VaultLib.VaultState public vaultState;
    mapping(address => VaultLib.DepositReceipt) public depositReceipts;
    mapping(address => VaultLib.Withdrawal) public withdrawals;
    mapping(uint256 => uint256) public epochPricePerShare;
    uint256 currentQueuedWithdrawShares = 0;

    error OnlyDVPAllowed();
    error AmountZero();
    error ExceedsAvailable();
    error ExistingIncompleteWithdraw();
    error SecondaryMarkedNotAllowed();

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_
    ) EpochControls(epochFrequency_) ERC20("", "") {
        baseToken = baseToken_;
        sideToken = sideToken_;
    }

    function getPortfolio() public view override returns (uint256 baseTokenAmount, uint256 sideTokenAmount) {
        baseTokenAmount = IERC20(baseToken).balanceOf(address(this));
        sideTokenAmount = IERC20(sideToken).balanceOf(address(this));
    }

    /// @inheritdoc IVault
    function deposit(uint256 amount) external override epochActive {
        if (!(amount > 0)) {
            revert AmountZero();
        }

        address creditor = msg.sender;

        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[creditor];

        // If a user deposited in the past and never redeemed her shares, update her receipt with the shares
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            epochPricePerShare[depositReceipt.epoch]
        );

        uint256 depositAmount = amount;

        // If the user has already deposited in the current epoch, add the amount to the pending deposit
        if (currentEpoch == depositReceipt.epoch) {
            uint256 newAmount = uint256(depositReceipt.amount).add(amount);
            depositAmount = newAmount;
        }

        depositReceipts[creditor] = VaultLib.DepositReceipt({
            epoch: currentEpoch,
            amount: depositAmount,
            unredeemedShares: unredeemedShares
        });
        vaultState.totalPendingLiquidity = vaultState.totalPendingLiquidity.add(amount);

        // TODO emit Deposit

        IERC20(baseToken).transferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IVault
    function redeem(uint256 shares) external {
        if (!(shares > 0)) {
            revert AmountZero();
        }
        _redeem(shares, false);
    }

    function _redeem(uint256 shares, bool isMax) internal {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[msg.sender];

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            epochPricePerShare[depositReceipt.epoch]
        );

        if (shares > unredeemedShares) {
            revert ExceedsAvailable();
        }

        if (isMax) {
            shares = unredeemedShares;
        }

        // If we have a depositReceipt on the same round, BUT we have some unredeemed shares
        // we debit from the unredeemedShares, but leave the amount field intact
        // If the round has past, with no new deposits, we just zero it out for new deposits.
        // The amount is being transformed in unredeemed shares from line 92.
        if (depositReceipt.epoch < currentEpoch) {
            depositReceipts[msg.sender].amount = 0;
        }

        depositReceipts[msg.sender].unredeemedShares = unredeemedShares.sub(shares);

        // TODO emit Redeem

        _transfer(address(this), msg.sender, shares);
    }

    /// @inheritdoc IVault
    function initiateWithdraw(uint256 shares) external {
        if (!(shares > 0)) {
            revert AmountZero();
        }

        // We do a max redeem before initiating a withdrawal
        // But we check if they must first have unredeemed shares
        if (depositReceipts[msg.sender].amount > 0 || depositReceipts[msg.sender].unredeemedShares > 0) {
            _redeem(0, true);
        }

        // // This caches the `round` variable used in shareBalances
        // uint256 currentRound = vaultState.round;

        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        bool withdrawalIsSameRound = withdrawal.epoch == currentEpoch;

        // emit InitiateWithdraw

        uint256 existingShares = withdrawal.shares;

        uint256 withdrawalShares;
        if (withdrawalIsSameRound) {
            // if user has already pre-ordered a withdrawal in this epoch just add to that
            withdrawalShares = existingShares.add(shares);
        } else {
            if (existingShares > 0) {
                revert ExistingIncompleteWithdraw();
            }
            withdrawalShares = shares;
            withdrawals[msg.sender].epoch = currentEpoch;
        }

        withdrawals[msg.sender].shares = withdrawalShares;

        _transfer(msg.sender, address(this), shares);

        currentQueuedWithdrawShares = currentQueuedWithdrawShares.add(shares);
    }

    // /// @inheritdoc IVault
    // function completeWithdraw() external {
    //     uint256 withdrawAmount = _completeWithdraw();
    //     lastQueuedWithdrawAmount = uint128(uint256(lastQueuedWithdrawAmount).sub(withdrawAmount));
    // }

    function rollEpoch() public override {
        // assume locked liquidity is updated after trades

        uint256 sharePrice;
        if (totalSupply() == 0) {
            // first time mint 1:1
            sharePrice = VaultLib.UNIT_PRICE;
        } else {
            if (vaultState.lockedLiquidity > 0) {
                sharePrice = vaultState.lockedLiquidity / totalSupply();
            } else {
                // if locked liquidity goes to 0 (market crash) need to burn all shares supply
                // TODO
            }
        }

        epochPricePerShare[currentEpoch] = sharePrice;
        uint256 sharesToMint = VaultLib.assetToShares(vaultState.totalPendingLiquidity, sharePrice);
        _mint(address(this), sharesToMint);
        vaultState.lockedLiquidity = vaultState.lockedLiquidity.add(vaultState.totalPendingLiquidity);
        vaultState.totalPendingLiquidity = 0;
        super.rollEpoch();
    }

    /// @inheritdoc IVault
    function shareBalances(address account) public view override returns (uint256 heldByAccount, uint256 heldByVault) {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[account];

        if (!(depositReceipt.epoch > 0)) {
            return (0, 0);
        }

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            epochPricePerShare[depositReceipt.epoch]
        );
        return (balanceOf(account), unredeemedShares);
    }

    /**
        @dev Block shares transfer when not allowed (for testnet purposes)
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        amount;
        if (from == address(this) || to == address(this) || from == address(0) || to == address(0)) {
            // it's a valid mint/burn
            return;
        }
        revert SecondaryMarkedNotAllowed();
    }
}
