// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IExchange} from "./interfaces/IExchange.sol";
import {IVault} from "./interfaces/IVault.sol";
import {VaultLib} from "./lib/VaultLib.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {EpochControls} from "./EpochControls.sol";

contract Vault is IVault, ERC20, EpochControls {
    using SafeMath for uint256;
    using VaultLib for VaultLib.DepositReceipt;

    address public immutable baseToken;
    address public immutable sideToken;

    VaultLib.VaultState internal _state;
    AddressProvider _addressProvider;

    mapping(address => VaultLib.DepositReceipt) public depositReceipts;
    mapping(address => VaultLib.Withdrawal) public withdrawals; // TBD: append receipt to the name
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
        uint256 epochFrequency_,
        address addressProvider_
    ) EpochControls(epochFrequency_) ERC20("", "") {
        baseToken = baseToken_;
        sideToken = sideToken_;

        _addressProvider = AddressProvider(addressProvider_);
    }

    /// @dev The Vault is alive until a certain amount of underlying asset is available to give value to outstanding shares
    modifier isNotDead() {
        if (_state.dead) {
            revert VaultDead();
        }
        _;
    }

    /// @dev The Vault is dead if underlying locked liquidity goes to zero because we can't mint new shares since then
    modifier isDead() {
        if (!_state.dead) {
            revert VaultNotDead();
        }
        _;
    }

    /// @inheritdoc IVault
    function vaultState()
        external
        view
        returns (
            uint256 lockedLiquidity,
            uint256 lastLockedLiquidity,
            bool lastLockedLiquidityZero,
            uint256 totalPendingLiquidity,
            uint256 totalWithdrawAmount,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead
        )
    {
        return (
            _state.liquidity.locked,
            0,
            _state.liquidity.lockedByPreviousEpochWasZero,
            _state.liquidity.availableForNextEpoch,
            _state.liquidity.pendingWithdrawals,
            _state.withdrawals.heldShares,
            _state.withdrawals.newHeldShares,
            _state.dead
        );
    }

    function getPortfolio() public view override returns (uint256 baseTokenAmount, uint256 sideTokenAmount) {
        baseTokenAmount = IERC20(baseToken).balanceOf(address(this));
        sideTokenAmount = IERC20(sideToken).balanceOf(address(this));
    }

    /// @inheritdoc IVault
    function deposit(uint256 amount) external override epochActive isNotDead epochNotFrozen(currentEpoch) {
        if (amount == 0) {
            revert AmountZero();
        }

        address creditor = msg.sender;

        IERC20(baseToken).transferFrom(creditor, address(this), amount);
        _emitUpdatedDepositReceipt(creditor, amount);

        _state.liquidity.availableForNextEpoch += amount;

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
    function initiateWithdraw(uint256 shares) external epochNotFrozen(currentEpoch) {
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
        _state.withdrawals.newHeldShares += shares;

        // TBD: emit InitiateWithdraw event
    }

    /// @inheritdoc IVault
    function completeWithdraw() external epochNotFrozen(currentEpoch) {
        // ToDo: review in order to consider also the side tokens...
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
        uint256 amountToWithdraw = VaultLib.sharesToAsset(sharesToWithdraw, _epochPricePerShare[withdrawal.epoch]);

        withdrawal.shares = 0;
        // NOTE: we choose to leave the epoch number as-is in order to save gas

        // NOTE: the user transferred the required shares to the vault when it initiated the withdraw
        _burn(address(this), sharesToWithdraw);
        _state.withdrawals.heldShares -= sharesToWithdraw;

        IERC20(baseToken).transfer(msg.sender, amountToWithdraw);
        _state.liquidity.pendingWithdrawals -= amountToWithdraw;

        // ToDo: emit Withdraw event
    }

    /// @inheritdoc IEpochControls
    function rollEpoch() public override isNotDead {
        // NOTE: assume locked liquidity is updated after trades

        // Trigger management of vault locked liquidity (inverse rebalance):
        // ToDo [mainnet]: do not swap everything, but only what's needed for the next epoch.
        // NOTE: the penguin says that doing so will let us save money...
        _sellSideTokens();

        // Set share price for the ending epoch:
        uint256 sharePrice;
        uint256 outstandingShares = totalSupply() - _state.withdrawals.heldShares;
        if (outstandingShares == 0) {
            // First time mint 1 share for each token
            sharePrice = VaultLib.UNIT_PRICE;
        } else {
            // NOTE: if the locked liquidity is 0, the price is set to 0
            // NOTE: if the number of shares is 0, it will revert due to a division by zero
            sharePrice = VaultLib.pricePerShare(_state.liquidity.locked, outstandingShares);
        }

        _epochPricePerShare[currentEpoch] = sharePrice;

        if (sharePrice == 0) {
            // if vault underlying asset disappear, don't mint any shares.
            // Pending deposits will be enabled for withdrawal - see rescueDeposit()
            _state.dead = true;
        }

        // NOTE: if sharePrice went to zero, the user will receive zero
        _state.withdrawals.heldShares += _state.withdrawals.newHeldShares;
        uint256 newPendingWithdrawals = VaultLib.sharesToAsset(_state.withdrawals.newHeldShares, sharePrice);
        _state.withdrawals.newHeldShares = 0;
        _state.liquidity.pendingWithdrawals += newPendingWithdrawals;

        if (!_state.dead) {
            // Mint shares related to new deposits performed during the closing epoch:
            // ToDo: do not use only the availableForNextEpoch, but also the amount from the premiums paid in the current epoch.
            uint256 sharesToMint = VaultLib.assetToShares(_state.liquidity.availableForNextEpoch, sharePrice);
            _mint(address(this), sharesToMint);

            _state.liquidity.locked += _state.liquidity.availableForNextEpoch;
            _state.liquidity.locked -= newPendingWithdrawals;
            _state.liquidity.availableForNextEpoch = 0;
        }

        super.rollEpoch();

        _splitIntoEqualWeightPortfolio();
    }

    /**
        @notice Enables user withdrawal of a deposits executed during an epoch causing Vault death
     */
    function rescueDeposit() external isDead {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[msg.sender];

        // User enabled to rescue only if the user has deposited in the last epoch before the Vault died.
        if (depositReceipt.epoch != getLastRolledEpoch()) {
            revert NothingToRescue();
        }

        uint256 amount = depositReceipt.amount;

        depositReceipts[msg.sender].amount = 0;
        IERC20(baseToken).transfer(msg.sender, amount);
    }

    /// @inheritdoc IVault
    function shareBalances(address account) public view returns (uint256 heldByAccount, uint256 heldByVault) {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[account];

        // TBD: wrap in a function
        if (depositReceipt.epoch == 0) {
            return (0, 0);
        }

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            _epochPricePerShare[depositReceipt.epoch]
        );

        return (balanceOf(account), unredeemedShares);
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
        @dev ToDo: replace with something that hedges a side token amount
     */
    function moveAsset(int256 amount) public {
        _sellSideTokens();

        if (amount > 0) {
            _state.liquidity.locked = _state.liquidity.locked.add(uint256(amount));
            IERC20(baseToken).transferFrom(msg.sender, address(this), uint256(amount));
        } else {
            if (uint256(-amount) > _state.liquidity.locked) {
                revert ExceedsAvailable();
            }
            _state.liquidity.locked = _state.liquidity.locked.sub(uint256(-amount));
            IERC20(baseToken).transfer(msg.sender, uint256(-amount));
        }

        _splitIntoEqualWeightPortfolio();
    }

    function _splitIntoEqualWeightPortfolio() internal {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        IExchange exchange = IExchange(exchangeAddress);

        uint256 amountToSwap = _state.liquidity.locked / 2;
        IERC20(baseToken).approve(exchangeAddress, amountToSwap);
        uint256 swappedAmount = exchange.swap(baseToken, sideToken, amountToSwap);

        _state.liquidity.locked -= swappedAmount;
    }

    function _sellSideTokens() internal {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        IExchange exchange = IExchange(exchangeAddress);

        uint256 amountToSwap = IERC20(sideToken).balanceOf(address(this));
        IERC20(sideToken).approve(exchangeAddress, amountToSwap);
        uint256 swappedAmount = exchange.swap(sideToken, baseToken, amountToSwap);

        _state.liquidity.locked += swappedAmount;
    }

    /**
        @notice Provides the total portfolio value in base tokens
        @return value The total portfolio value in base tokens
     */
    function lockedValue() view public returns (uint256) {
        // ToDo: allow the IExchange to preview the swapped amount
        (, uint256 sideTokens) = getPortfolio();
        // NOTE: stub assuming price 1:1
        return _state.liquidity.locked + sideTokens;
    }
}
