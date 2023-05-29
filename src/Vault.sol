// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IExchange} from "./interfaces/IExchange.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
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

    // TBD: currently used only by tests
    /// @inheritdoc IVault
    function vaultState()
        external
        view
        returns (
            uint256 lockedLiquidityInitially,
            uint256 pendingDeposit,
            uint256 totalWithdrawAmount,
            uint256 pendingPayoffs,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead
        )
    {
        return (
            _state.liquidity.lockedInitially,
            _state.liquidity.pendingDeposits,
            _state.liquidity.pendingWithdrawals,
            _state.liquidity.pendingPayoffs,
            _state.withdrawals.heldShares,
            _state.withdrawals.newHeldShares,
            _state.dead
        );
    }

    // TBD: currently used only by tests
    function balances() public view override returns (uint256 baseTokenAmount, uint256 sideTokenAmount) {
        baseTokenAmount = _notionalBaseTokens();
        sideTokenAmount = IERC20(sideToken).balanceOf(address(this));
    }

    // TBD: add to the IVault interface
    /**
        @notice Provides the total portfolio value in base tokens
        @return value The total portfolio value in base tokens
     */
    function notional() public view returns (uint256) {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        IExchange exchange = IExchange(exchangeAddress);

        uint256 baseTokens = _notionalBaseTokens();
        uint256 sideTokens = _notionalSideTokens();
        uint256 valueOfSideTokens = exchange.getOutputAmount(sideToken, baseToken, sideTokens);

        return baseTokens + valueOfSideTokens;
    }

    /// @dev Gives the current amount of base tokens available to make options related operations (payoff payments, portfolio hedging)
    function _notionalBaseTokens() internal view returns (uint256) {
        return
            IERC20(baseToken).balanceOf(address(this)) -
            _state.liquidity.pendingWithdrawals -
            _state.liquidity.pendingDeposits -
            _state.liquidity.pendingPayoffs;
    }

    /// @dev Gives the current amount of base tokens available to make options related operations (payoff payments, portfolio hedging)
    function _notionalSideTokens() internal view returns (uint256) {
        return IERC20(sideToken).balanceOf(address(this));
    }

    // TBD: rename to initial notional
    /// @inheritdoc IVault
    function v0() public view virtual returns (uint256) {
        return _state.liquidity.lockedInitially;
    }

    // ------------------------------------------------------------------------
    // USER OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc IVault
    function deposit(uint256 amount) external override epochInitialized isNotDead epochNotFrozen {
        if (amount == 0) {
            revert AmountZero();
        }

        address creditor = msg.sender;

        IERC20(baseToken).transferFrom(creditor, address(this), amount);
        _emitUpdatedDepositReceipt(creditor, amount);

        _state.liquidity.pendingDeposits += amount;

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
    function initiateWithdraw(uint256 shares) external epochNotFrozen {
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
    function completeWithdraw() external epochNotFrozen {
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

    /**
        @notice Enables user withdrawal of a deposits executed during an epoch causing Vault death
     */
    function rescueDeposit() external isDead {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[msg.sender];

        // User enabled to rescue only if the user has deposited in the last epoch before the Vault died.
        if (depositReceipt.epoch != _lastRolledEpoch()) {
            revert NothingToRescue();
        }

        _state.liquidity.pendingDeposits -= depositReceipt.amount;

        depositReceipts[msg.sender].amount = 0;
        IERC20(baseToken).transfer(msg.sender, depositReceipt.amount);
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

    // ------------------------------------------------------------------------
    // VAULT OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc IEpochControls
    function rollEpoch() public override isNotDead {
        // ToDo: review variable name
        uint256 lockedLiquidity = notional();

        uint256 sharePrice;
        uint256 outstandingShares = totalSupply() - _state.withdrawals.heldShares;
        // NOTE: if the number of shares is 0, pricePerShare will revert due to a division by zero
        if (outstandingShares == 0) {
            // First time mint 1 share for each token
            sharePrice = VaultLib.UNIT_PRICE;
        } else {
            // NOTE: if the locked liquidity is 0, the price is set to 0
            sharePrice = VaultLib.pricePerShare(lockedLiquidity, outstandingShares);
        }

        _epochPricePerShare[currentEpoch] = sharePrice;

        if (sharePrice == 0) {
            // if vault underlying asset disappear, don't mint any shares.
            // Pending deposits will be enabled for withdrawal - see rescueDeposit()
            _state.dead = true;
        }

        // NOTE: if sharePrice went to zero, the users will receive zero
        _state.withdrawals.heldShares += _state.withdrawals.newHeldShares;
        uint256 newPendingWithdrawals = VaultLib.sharesToAsset(_state.withdrawals.newHeldShares, sharePrice);
        // TODO - make one call to exchange (unify with ew rebalance)
        _reserveBaseTokens(newPendingWithdrawals);
        // NOTE: the internal state must be updated after the call to `_reserveBaseTokens`
        _state.liquidity.pendingWithdrawals += newPendingWithdrawals;
        _state.withdrawals.newHeldShares = 0;

        lockedLiquidity -= newPendingWithdrawals;

        // TODO: put aside the payoff to be paid
        _reserveBaseTokens(_state.liquidity.pendingPayoffs);

        if (!_state.dead) {
            // Mint shares related to new deposits performed during the closing epoch:
            uint256 sharesToMint = VaultLib.assetToShares(_state.liquidity.pendingDeposits, sharePrice);
            _mint(address(this), sharesToMint);

            _state.liquidity.lockedInitially = lockedLiquidity + _state.liquidity.pendingDeposits;
            _state.liquidity.pendingDeposits = 0;

            _equalWeightRebalance();
        }

        super.rollEpoch();

        // TBD: what if sideTokenBalance == 0 and lockedValue != 0 ?
    }

    /// @dev Ensure we have enough base token to pay for withdraws
    function _reserveBaseTokens(uint256 amount) private {
        uint256 baseTokenAmount = _notionalBaseTokens();
        if (baseTokenAmount >= amount) {
            return;
        }

        address exchangeAddress = _addressProvider.exchangeAdapter();
        IExchange exchange = IExchange(exchangeAddress);

        uint256 amountBaseTokenToAcquire = amount - baseTokenAmount;
        int256 deltaHedgeIdx = int256(exchange.getOutputAmount(baseToken, sideToken, amountBaseTokenToAcquire));
        deltaHedge(-deltaHedgeIdx);
    }

    /// @dev ...
    function _equalWeightRebalance() internal {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        IExchange exchange = IExchange(exchangeAddress);

        uint256 halfNotional = notional() / 2;

        uint256 finalSideTokens = exchange.getOutputAmount(baseToken, sideToken, halfNotional);
        uint256 sideTokens = _notionalSideTokens();
        deltaHedge(int256(finalSideTokens) - int256(sideTokens));
    }

    function deltaHedge(int256 sideTokensAmount) public {
        if (sideTokensAmount > 0) {
            uint256 amount = uint256(sideTokensAmount);
            _buySideTokens(amount);
        } else {
            uint256 amount = uint256(-sideTokensAmount);
            _sellSideTokens(amount);
        }
    }

    function _buySideTokens(uint256 amount) internal {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        IExchange exchange = IExchange(exchangeAddress);

        uint256 baseTokensAmount = exchange.getInputAmount(baseToken, sideToken, amount);

        // Should never happen: `deltaHedge()` should call this function with a correct amount of side tokens
        if (baseTokensAmount > _notionalBaseTokens()) {
            revert ExceedsAvailable();
        }

        IERC20(baseToken).approve(exchangeAddress, baseTokensAmount);

        exchange.swapOut(baseToken, sideToken, amount);
    }

    function _sellSideTokens(uint256 amount) internal {
        uint256 sideTokensAmount = IERC20(sideToken).balanceOf(address(this));
        if (sideTokensAmount < amount) {
            revert ExceedsAvailable();
        }
        address exchangeAddress = _addressProvider.exchangeAdapter();
        IExchange exchange = IExchange(exchangeAddress);

        IERC20(sideToken).approve(exchangeAddress, amount);
        exchange.swapIn(sideToken, baseToken, amount);
    }

    function reservePayoff(uint256 residualPayoff) external {
        _state.liquidity.pendingPayoffs += residualPayoff;
    }

    function transferPayoff(address recipient, uint256 amount, bool isPastEpoch) external {
        if (amount == 0) {
            return;
        }

        if (isPastEpoch) {
            if (amount > _state.liquidity.pendingPayoffs) {
                revert ExceedsAvailable();
            }
            _state.liquidity.pendingPayoffs -= amount;
        } else {
            // NOTE: it should never happen as `deltaHedge()` must always be executed before transfers
            if (amount > _notionalBaseTokens()) {
                revert ExceedsAvailable();
            }
        }

        IERC20(baseToken).transfer(recipient, amount);
    }

    /// @dev Block shares transfer when not allowed (for testnet purposes)
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
}
