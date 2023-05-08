// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IVault} from "./interfaces/IVault.sol";
import {VaultLib} from "./lib/VaultLib.sol";
import {EpochControls} from "./EpochControls.sol";

contract Vault is IVault, ERC20, EpochControls {
    using SafeMath for uint256;
    using VaultLib for VaultLib.DepositReceipt;

    address public immutable baseToken;
    address public immutable sideToken;

    VaultLib.VaultState public vaultState;

    mapping(address => VaultLib.DepositReceipt) public depositReceipts;
    mapping(address => VaultLib.Withdrawal) public withdrawals;
    mapping(uint256 => uint256) internal _epochPricePerShare;

    error AmountZero();
    error ExceedsAvailable();
    error ExistingIncompleteWithdraw();
    error NothingToRescue();
    error SecondaryMarkedNotAllowed();
    error VaultDead();
    error VaultNotDead();
    error WithdrawNotInitiated();
    error WithdrawTooEarly();

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_
    ) EpochControls(epochFrequency_) ERC20("", "") {
        baseToken = baseToken_;
        sideToken = sideToken_;
    }

    /// @dev The Vault is alive until a certain amount of underlying asset is available to give value to outstanding shares
    modifier isNotDead() {
        if (vaultState.dead) {
            revert VaultDead();
        }
        _;
    }

    /// @dev The Vault is dead if underlying locked liquidity goes to zero because we can't mint new shares since then
    modifier isDead() {
        if (!vaultState.dead) {
            revert VaultNotDead();
        }
        _;
    }

    function getPortfolio() public view override returns (uint256 baseTokenAmount, uint256 sideTokenAmount) {
        baseTokenAmount = IERC20(baseToken).balanceOf(address(this));
        sideTokenAmount = IERC20(sideToken).balanceOf(address(this));
    }

    /// @inheritdoc IVault
    function deposit(uint256 amount) external override epochActive isNotDead {
        if (amount == 0) {
            revert AmountZero();
        }

        address creditor = msg.sender;

        IERC20(baseToken).transferFrom(creditor, address(this), amount);
        _emitUpdatedDepositReceipt(creditor, amount);

        vaultState.totalPendingLiquidity += amount;

        // ToDo emit Deposit event
    }

    function _emitUpdatedDepositReceipt(address creditor, uint256 amount) internal {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[creditor];

        // Get the number of unredeemed shares from previous deposits, if any.
        // That number will be used in order to update the user's receipt.
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            _epochPricePerShare[depositReceipt.epoch]
        );

        // If the user has already deposited in the current epoch, add the amount to the total one of the next epoch:
        if (currentEpoch == depositReceipt.epoch) {
            amount = depositReceipt.amount.add(amount);
        }

        depositReceipts[creditor] = VaultLib.DepositReceipt({
            epoch: currentEpoch,
            amount: amount,
            unredeemedShares: unredeemedShares
        });
    }

    /// @inheritdoc IVault
    function redeem(uint256 shares) external {
        if (shares == 0) {
            revert AmountZero();
        }
        _redeem(shares, false);
    }

    function _redeem(uint256 shares, bool isMax) internal {
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[msg.sender];

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            _epochPricePerShare[depositReceipt.epoch]
        );

        if (shares > unredeemedShares && !isMax) {
            revert ExceedsAvailable();
        }

        if (isMax) {
            shares = unredeemedShares;
        }

        // TBD: check if shares equals zero and return

        if (depositReceipt.epoch < currentEpoch) {
            // NOTE: all the amount - if any - has already been converted in unredeemedShares.
            depositReceipt.amount = 0;
        }

        depositReceipt.unredeemedShares = unredeemedShares.sub(shares);

        _transfer(address(this), msg.sender, shares);

        // ToDo emit Redeem event
    }

    /// @inheritdoc IVault
    function initiateWithdraw(uint256 shares) external {
        if (shares == 0) {
            revert AmountZero();
        }

        // We take advantage of this flow in order to also transfer all the unredeemed shares to the user.
        if (depositReceipts[msg.sender].amount > 0 || depositReceipts[msg.sender].unredeemedShares > 0) {
            // TBD: just call it without the if statement
            _redeem(0, true);
        }

        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        if (withdrawal.epoch < currentEpoch && withdrawal.shares > 0) {
            revert ExistingIncompleteWithdraw();
        }

        uint256 sharesToWithdraw = shares;
        if (withdrawal.epoch == currentEpoch) {
            // if user has already pre-ordered a withdrawal in this epoch just add to that
            sharesToWithdraw = withdrawal.shares.add(shares);
        }

        withdrawal.shares = sharesToWithdraw;
        withdrawal.epoch = currentEpoch;

        _transfer(msg.sender, address(this), shares);

        // NOTE: shall the user attempt to calls redeem after this one, there'll be no unredeemed shares
        vaultState.currentQueuedWithdrawShares += shares;

        // TBD: emit InitiateWithdraw event
    }

    /// @inheritdoc IVault
    function completeWithdraw() external {
        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        // Checks if there is an initiated withdrawal:
        if (withdrawal.shares == 0) {
            revert WithdrawNotInitiated();
        }

        // At least one epoch needs to be past since the initiated withdrawal:
        if (withdrawal.epoch == currentEpoch) {
            revert WithdrawTooEarly();
        }

        uint256 sharesToWithdraw = withdrawal.shares;
        uint256 withdrawAmount = VaultLib.sharesToAsset(sharesToWithdraw, _epochPricePerShare[withdrawal.epoch]);

        withdrawal.shares = 0;
        // NOTE: we choose to leave the epoch number as-is in order to save gas

        // NOTE: the user transferred the required shares to the vault when it initiated the withdraw
        _burn(address(this), sharesToWithdraw);

        IERC20(baseToken).transfer(msg.sender, withdrawAmount);

        vaultState.queuedWithdrawShares -= sharesToWithdraw;
        vaultState.totalWithdrawAmount -= withdrawAmount;

        // ToDo: emit Withdraw event
    }

    /// @inheritdoc IEpochControls
    function rollEpoch() public override isNotDead {
        // assume locked liquidity is updated after trades

        // ToDo: add comments
        uint256 sharePrice;
        if (totalSupply() == 0 || vaultState.lastLockedLiquidityZero) {
            // First time mint 1 share for each token
            sharePrice = VaultLib.UNIT_PRICE;

            vaultState.lastLockedLiquidityZero = false;
        } else {
            // if vaultState.lockedLiquidity is 0 price is set to 0
            sharePrice = VaultLib.pricePerShare(vaultState.lockedLiquidity, totalSupply());

            if (vaultState.lockedLiquidity == 0) {
                vaultState.lastLockedLiquidityZero = true;
            }
        }

        _epochPricePerShare[currentEpoch] = sharePrice;

        vaultState.queuedWithdrawShares += vaultState.currentQueuedWithdrawShares;
        uint256 lastWithdrawAmount = VaultLib.sharesToAsset(vaultState.currentQueuedWithdrawShares, sharePrice);
        vaultState.totalWithdrawAmount += lastWithdrawAmount;
        vaultState.currentQueuedWithdrawShares = 0;

        if (sharePrice == 0) {
            // if vault underlying asset disappear, don't mint any shares.
            // Pending deposits will be enabled for withdrawal - see rescueDeposit()
            vaultState.dead = true;
        } else {
            // Mint shares related to new deposits performed during the closing epoch:
            uint256 sharesToMint = VaultLib.assetToShares(vaultState.totalPendingLiquidity, sharePrice);
            _mint(address(this), sharesToMint);

            vaultState.lockedLiquidity += vaultState.totalPendingLiquidity;
            vaultState.lockedLiquidity -= lastWithdrawAmount;
            vaultState.totalPendingLiquidity = 0;
        }

        super.rollEpoch();
    }

    /**
        @notice Enables user withdrawal of a deposits executed during an epoch causing Vault death
     */
    function rescueDeposit() external isDead {
        uint256 amount = depositReceipts[msg.sender].amount;
        if (amount == 0) {
            revert NothingToRescue();
        }
        depositReceipts[msg.sender].amount = 0;
        IERC20(baseToken).transfer(msg.sender, amount);
    }

    /// @inheritdoc IVault
    function shareBalances(address account) public view returns (uint256 heldByAccount, uint256 heldByVault) {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[account];

        if (depositReceipt.epoch == 0) {
            return (0, 0);
        }

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            _epochPricePerShare[depositReceipt.epoch]
        );

        return (balanceOf(account), unredeemedShares);
    }

    // ToDo: review (delete ?)
    function testIncreaseDecreateLiquidityLocked(uint256 amount, bool increase) public {
        if (increase) {
            vaultState.lockedLiquidity = vaultState.lockedLiquidity.add(amount);
        } else {
            vaultState.lockedLiquidity = vaultState.lockedLiquidity.sub(amount);
        }
    }

    /**
        @dev Block shares transfer when not allowed (for testnet purposes)
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        amount;
        if (from == address(0) || to == address(0)) {
            // it's a valid mint/burn
            return;
        }
        if (from == address(this) || to == address(this)) {
            // it's a vault operation
            return;
        }
        revert SecondaryMarkedNotAllowed();
    }

    /**
        @notice
     */
    function moveAsset(int256 amount) public {
        if (amount > 0) {
            vaultState.lockedLiquidity = vaultState.lockedLiquidity.add(uint256(amount));
            IERC20(baseToken).transferFrom(msg.sender, address(this), uint256(amount));
        } else {
            if (uint256(-amount) > vaultState.lockedLiquidity) {
                revert ExceedsAvailable();
            }
            vaultState.lockedLiquidity = vaultState.lockedLiquidity.sub(uint256(-amount));
            IERC20(baseToken).transfer(msg.sender, uint256(-amount));
        }
    }
}
