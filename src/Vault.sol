// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IExchange} from "./interfaces/IExchange.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVaultParams} from "./interfaces/IVaultParams.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";
import {Epoch, EpochController} from "./lib/EpochController.sol";
import {TokensPair} from "./lib/TokensPair.sol";
import {VaultLib} from "./lib/VaultLib.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {EpochControls} from "./EpochControls.sol";

contract Vault is IVault, ERC20, EpochControls, Ownable, Pausable {
    using AmountsMath for uint256;
    using VaultLib for VaultLib.DepositReceipt;
    using EpochController for Epoch;

    /// @inheritdoc IVaultParams
    address public immutable baseToken;

    /// @inheritdoc IVaultParams
    address public immutable sideToken;

    /// @notice The address of the DVP paired with this vault
    address public dvp; // NOTE: public for frontend purposes

    /// @notice Maximum threshold for users cumulative deposit (see VaultLib.VaultState.liquidity.totalDeposit)
    uint256 public maxDeposit;

    /// @inheritdoc IVault
    mapping(address => VaultLib.DepositReceipt) public depositReceipts;

    /// @inheritdoc IVault
    mapping(address => VaultLib.Withdrawal) public withdrawals; // TBD: append receipt to the name

    mapping(uint256 => uint256) public epochPricePerShare; // NOTE: public for frontend and historical data purposes

    /// @notice Whether the transfer of shares between wallets is allowed or not
    bool internal _secondaryMarkedAllowed;

    VaultLib.VaultState internal _state;

    // ToDo: Name Refactor?
    bool public manualKill;

    AddressProvider internal immutable _addressProvider;

    error AddressZero();
    error AmountZero();
    error ApproveFailed();
    error DVPNotSet();
    error ExceedsAvailable();
    error ExceedsMaxDeposit();
    error ExistingIncompleteWithdraw();
    error NothingToRescue();
    error NothingToWithdraw();
    error OnlyDVPAllowed();
    error SecondaryMarkedNotAllowed();
    error TransferFailed();
    error VaultDead();
    error VaultNotDead();
    error WithdrawNotInitiated();
    error WithdrawTooEarly();

    // TBD: create ERC20 name and symbol from the underlying tokens
    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_,
        address addressProvider_
    ) ERC20("", "") EpochControls(epochFrequency_) Ownable() Pausable() {
        TokensPair.validate(TokensPair.Pair({baseToken: baseToken_, sideToken: sideToken_}));
        baseToken = baseToken_;
        sideToken = sideToken_;

        _addressProvider = AddressProvider(addressProvider_);
        // ToDo: Add constructor parameter
        maxDeposit = 1e25;
        _secondaryMarkedAllowed = false;
    }

    modifier isNotDead() {
        if (_state.dead) {
            revert VaultDead();
        }
        _;
    }

    modifier isDead() {
        if (!_state.dead) {
            revert VaultNotDead();
        }
        _;
    }

    modifier onlyDVP() {
        if (dvp == address(0)) {
            revert DVPNotSet();
        }
        if (msg.sender != dvp) {
            revert OnlyDVPAllowed();
        }
        _;
    }

    /**
        @notice Allows the contract's owner to set the DVP paired with this vault.
        @dev The address is injected after-build, because the DVP needs an already built vault as constructor-injected dependency.
     */
    function setAllowedDVP(address dvp_) external onlyOwner {
        dvp = dvp_;
    }

    /**
        @notice Set LimitTVL
        @param limitTVL_ LimitTVL to set
     */
    function setMaxDeposit(uint256 limitTVL_) external onlyOwner {
        maxDeposit = limitTVL_;
    }

    function killVault() public onlyOwner isNotDead {
        manualKill = true;
    }

    // ToDo: review as it's currently used only by tests
    function vaultState()
        external
        view
        returns (
            uint256 lockedLiquidityInitially,
            uint256 pendingDeposit,
            uint256 totalWithdrawAmount,
            uint256 pendingPayoffs,
            uint256 totalDeposit,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead,
            bytes4 deadReason
        )
    {
        return (
            _state.liquidity.lockedInitially,
            _state.liquidity.pendingDeposits,
            _state.liquidity.pendingWithdrawals,
            _state.liquidity.pendingPayoffs,
            _state.liquidity.totalDeposit,
            _state.withdrawals.heldShares,
            _state.withdrawals.newHeldShares,
            _state.dead,
            _state.deadReason
        );
    }

    /// @inheritdoc IVault
    function balances() public view returns (uint256 baseTokenAmount, uint256 sideTokenAmount) {
        baseTokenAmount = _notionalBaseTokens();
        sideTokenAmount = _notionalSideTokens();
    }

    // TBD: add to the IVault interface
    /**
        @notice Provides the total portfolio value in base tokens
        @return value The total portfolio value in base tokens
     */
    function notional() public view returns (uint256) {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        uint256 baseTokens = _notionalBaseTokens();
        uint256 sideTokens = _notionalSideTokens();
        uint256 valueOfSideTokens = exchange.getOutputAmount(sideToken, baseToken, sideTokens);

        return baseTokens + valueOfSideTokens;
    }

    /**
        @notice Provides the current amount of base tokens available for DVP operations in the current epoch.
        @return amount_ The current amount of available base tokens
        @dev In the current epoch, that amount is everything except the amounts putted aside.
     */
    function _notionalBaseTokens() internal view returns (uint256 amount_) {
        return
            IERC20(baseToken).balanceOf(address(this)) -
            _state.liquidity.pendingWithdrawals -
            _state.liquidity.pendingDeposits -
            _state.liquidity.pendingPayoffs;
    }

    /**
        @notice Provides the amount of side tokens from the portfolio of the current epoch.
        @return amount_ The amount of side tokens
     */
    function _notionalSideTokens() internal view returns (uint256 amount_) {
        // TBD: use an internal account in order to avoid external manipulations where a malicious actor sends tokens to the vault in order to impact the share price or the DVP
        return IERC20(sideToken).balanceOf(address(this));
    }

    // TBD: rename to initial notional
    /// @inheritdoc IVault
    function v0() public view virtual returns (uint256) {
        return _state.liquidity.lockedInitially;
    }

    /// @inheritdoc IVault
    function changePauseState() external override {
        _checkOwner();

        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    // ToDo: try to remove as `paused` is already public
    /// @inheritdoc IVault
    function isPaused() public view override returns (bool paused_) {
        paused_ = paused();
    }

    // ------------------------------------------------------------------------
    // USER OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc IVault
    function deposit(
        uint256 amount,
        address receiver
    ) external isNotDead whenNotPaused {
        _checkEpochInitialized();
        _checkEpochNotFinished();
        if (amount == 0) {
            revert AmountZero();
        }

        uint256 depositCapacity = maxDeposit - _state.liquidity.totalDeposit;
        if (amount > depositCapacity) {
            revert ExceedsMaxDeposit();
        }

        address creditor = receiver;

        _state.liquidity.pendingDeposits += amount;
        _state.liquidity.totalDeposit += amount;
        _emitUpdatedDepositReceipt(creditor, amount);

        if (!IERC20(baseToken).transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }

        // ToDo emit Deposit event
    }

    /**
        @notice Create or update a deposit receipt for a given deposit operation.
        @param creditor The wallet of the creditor
        @param amount The deposited amount
        @dev The deposit receipt allows the creditor to redeem its shares or withdraw liquidity.
     */
    function _emitUpdatedDepositReceipt(address creditor, uint256 amount) internal {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[creditor];
        Epoch memory epoch = getEpoch();

        // Get the number of unredeemed shares from previous deposits, if any.
        // NOTE: the amount of unredeemed shares is the one of the previous epochs, as we still don't know the share price.
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            epoch.current,
            epochPricePerShare[depositReceipt.epoch]
        );

        uint256 cumulativeUserAmount = depositReceipt.cumulativeAmount.add(amount);

        // If the user has already deposited in the current epoch, add the amount to the total one of the next epoch:
        if (epoch.current == depositReceipt.epoch) {
            amount = depositReceipt.amount.add(amount);
        }

        depositReceipts[creditor] = VaultLib.DepositReceipt({
            epoch: epoch.current,
            amount: amount,
            unredeemedShares: unredeemedShares,
            cumulativeAmount: cumulativeUserAmount
        });
    }

    // ToDo: review
    // /**
    //      @notice Enables withdraw assets deposited in the same epoch (withdraws using the outstanding
    //              `DepositReceipt.amount`)
    //      @param amount is the amount to withdraw
    //  */
    // function withdrawInstantly(uint256 amount) external;

    /**
        @notice Get wallet balance of actual owned shares and owed shares.
        @return heldByAccount The amount of shares owned by the wallet
        @return heldByVault The amount of shares owed to the wallet
     */
    function shareBalances(address account) public view returns (uint256 heldByAccount, uint256 heldByVault) {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[account];

        // TBD: wrap in a function
        if (depositReceipt.epoch == 0) {
            return (0, 0);
        }

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            getEpoch().current,
            epochPricePerShare[depositReceipt.epoch]
        );

        return (balanceOf(account), unredeemedShares);
    }

    /**
        @notice Redeems shares held by the vault for the calling wallet
        @param shares is the number of shares to redeem
     */
    function redeem(uint256 shares) external {
        if (shares == 0) {
            revert AmountZero();
        }
        // NOTE: if the epoch has not been initialized, it reverts with ExceedsAvailable.
        // ----- TBD: add the epochInitialized modifier
        _redeem(shares, false);
    }

    function _redeem(uint256 shares, bool isMax) internal {
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[msg.sender];

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            getEpoch().current,
            epochPricePerShare[depositReceipt.epoch]
        );

        if (shares > unredeemedShares && !isMax) {
            revert ExceedsAvailable();
        }

        if (isMax) {
            shares = unredeemedShares;
        }

        // TBD: check if shares equals zero and return

        if (depositReceipt.epoch < getEpoch().current) {
            // NOTE: all the amount - if any - has already been converted in unredeemedShares.
            depositReceipt.amount = 0;
        }

        depositReceipt.unredeemedShares = unredeemedShares.sub(shares);

        _transfer(address(this), msg.sender, shares);

        // ToDo emit Redeem event
    }

    /// @inheritdoc IVault
    function initiateWithdraw(uint256 shares) external whenNotPaused {
        _checkEpochNotFinished();
        _initiateWithdraw(shares, false);
    }

    function _initiateWithdraw(uint256 shares, bool isMax) internal {
        if (shares == 0 && !isMax) {
            revert AmountZero();
        }

        // We take advantage of this flow in order to also transfer all the unredeemed shares to the user.
        if (depositReceipts[msg.sender].amount > 0 || depositReceipts[msg.sender].unredeemedShares > 0) {
            // TBD: just call it without the if statement

            _redeem(0, true);
        }

        // NOTE: all shares belong to the user since we made a 'redeem all'
        uint256 userShares = balanceOf(msg.sender);

        if (isMax) {
            shares = userShares;
        }

        if (shares > userShares) {
            revert ExceedsAvailable();
        }

        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];
        Epoch memory epoch = getEpoch();

        if (withdrawal.epoch < epoch.current && withdrawal.shares > 0) {
            revert ExistingIncompleteWithdraw();
        }

        uint256 sharesToWithdraw = shares;
        if (withdrawal.epoch == epoch.current) {
            // if user has already pre-ordered a withdrawal in this epoch just add to that
            sharesToWithdraw = withdrawal.shares.add(shares);
        }

        // In order to update vault capacity we need to understand how much of her all-time deposit the user is removing from the vault
        // We compute this as the proportion: (burning shares / total shares) * all-time deposit

        // Don't consider current epoch deposits in all-time deposits computation
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        uint256 cumulativeDeposit = depositReceipt.cumulativeAmount;
        if (depositReceipt.epoch == epoch.current) {
            cumulativeDeposit -= depositReceipt.amount;
        }

        uint256 withdrawDeposit = cumulativeDeposit.wmul(shares).wdiv(userShares);
        depositReceipt.cumulativeAmount -= withdrawDeposit;
        _state.liquidity.totalDeposit -= withdrawDeposit;

        // update receipt

        withdrawal.shares = sharesToWithdraw;
        withdrawal.epoch = epoch.current;

        // NOTE: shall the user attempt to calls redeem after this one, there'll be no unredeemed shares
        _state.withdrawals.newHeldShares += shares;

        _transfer(msg.sender, address(this), shares);

        // TBD: emit InitiateWithdraw event
    }

    /**
        @notice Completes a scheduled withdrawal from a past epoch. Uses finalized share price for the epoch.
     */
    function completeWithdraw() external whenNotPaused {
        _checkEpochNotFinished();
        _completeWithdraw();
    }

    function _completeWithdraw() internal {
        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];
        uint256 sharesToWithdraw = withdrawal.shares;

        // Checks if there is an initiated withdrawal
        if (sharesToWithdraw == 0) {
            revert WithdrawNotInitiated();
        }

        Epoch memory epoch = getEpoch();

        // At least one epoch must have passed since the start of the withdrawal
        if (withdrawal.epoch == epoch.current && _state.deadReason != VaultLib.DeadManualKillReason) {
            revert WithdrawTooEarly();
        }
        uint256 amountToWithdraw;
        if (withdrawal.epoch == epoch.current && _state.deadReason == VaultLib.DeadManualKillReason) {
            amountToWithdraw = VaultLib.sharesToAsset(sharesToWithdraw, epochPricePerShare[epoch.previous]);
        } else {
            amountToWithdraw = VaultLib.sharesToAsset(sharesToWithdraw, epochPricePerShare[withdrawal.epoch]);
        }
        withdrawal.shares = 0;

        // NOTE: the user transferred the required shares to the vault when she initiated the withdraw
        if (!_state.dead) {
            _state.withdrawals.heldShares -= sharesToWithdraw;
            _state.liquidity.pendingWithdrawals -= amountToWithdraw;
        }

        _burn(address(this), sharesToWithdraw);
        if (!IERC20(baseToken).transfer(msg.sender, amountToWithdraw)) {
            revert TransferFailed();
        }

        // ToDo: emit Withdraw event
    }

    /**
        @notice Enables user withdrawal of a deposits executed during an epoch causing Vault death
     */
    function rescueDeposit() external isDead {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[msg.sender];

        // User enabled to rescue only if the user has deposited in the last epoch before the Vault died.
        if (depositReceipt.epoch != getEpoch().previous) {
            revert NothingToRescue();
        }

        _state.liquidity.pendingDeposits -= depositReceipt.amount;

        depositReceipts[msg.sender].amount = 0;
        if (!IERC20(baseToken).transfer(msg.sender, depositReceipt.amount)) {
            revert TransferFailed();
        }
    }

    function rescueShares() external isDead {
        // ToDo: Change reason
        require(_state.deadReason == VaultLib.DeadManualKillReason, "Vault dead due to market conditions");

        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        // If an uncompleted withdraw exists, complete this one before to start with new one.
        if (withdrawal.shares > 0) {
            _completeWithdraw();
        }

        _initiateWithdraw(0, true);
        _completeWithdraw();
    }

    // ------------------------------------------------------------------------
    // VAULT OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc EpochControls
    function _beforeRollEpoch() internal virtual override isNotDead {
        _requireNotPaused();

        if (dvp == address(0)) {
            _checkOwner();
        }
        if (dvp != address(0) && msg.sender != dvp) {
            // NOTE: must be called only by the DVP after a DVP has been set.
            revert OnlyDVPAllowed();
        }

        // TBD: a dead vault can be revived ?
        // ToDo: review variable name
        uint256 lockedLiquidity = notional();

        // NOTE: the share price needs to account also the payoffs
        lockedLiquidity -= _state.liquidity.newPendingPayoffs;

        if (manualKill) {
            _state.dead = true;

            // Sell all sideToken to be able to pay all the withdraws initiate after manual kill.
            uint256 sideTokens = IERC20(sideToken).balanceOf(address(this));
            _deltaHedge(-int256(sideTokens));
        }

        // TBD: rename to shareValue
        uint256 sharePrice = _computeSharePrice(lockedLiquidity);
        epochPricePerShare[getEpoch().current] = sharePrice;

        if (sharePrice == 0) {
            // if vault underlying asset disappear, don't mint any shares.
            // Pending deposits will be enabled for withdrawal - see rescueDeposit()
            _state.dead = true;
            _state.deadReason = VaultLib.DeadMarketReason;
        }

        if (manualKill) {
            _state.deadReason = VaultLib.DeadManualKillReason;
        }

        // Increase shares hold due to initiated withdrawals:
        _state.withdrawals.heldShares += _state.withdrawals.newHeldShares;

        // Reserve the liquidity needed to cover the withdrawals initiated in the current epoch:
        // NOTE: here we just account the amounts and we delay all the actual swaps to the final one in order to optimize them.
        // NOTE: if sharePrice is zero, the users will receive zero from withdrawals
        uint256 newPendingWithdrawals = VaultLib.sharesToAsset(_state.withdrawals.newHeldShares, sharePrice);
        _state.liquidity.pendingWithdrawals += newPendingWithdrawals;
        lockedLiquidity -= newPendingWithdrawals;

        // Reset the counter for the next epoch:
        _state.withdrawals.newHeldShares = 0;

        // Set aside the payoff to be paid:
        _state.liquidity.pendingPayoffs += _state.liquidity.newPendingPayoffs;
        _state.liquidity.newPendingPayoffs = 0;

        if (_state.dead && !manualKill) {
            // ToDo: review
            _state.liquidity.lockedInitially = 0;
            return;
        }

        // Mint shares related to new deposits performed during the closing epoch:
        uint256 sharesToMint = VaultLib.assetToShares(_state.liquidity.pendingDeposits, sharePrice);
        _mint(address(this), sharesToMint);

        lockedLiquidity += _state.liquidity.pendingDeposits;
        _state.liquidity.pendingDeposits = 0;

        _state.liquidity.lockedInitially = lockedLiquidity;

        if (manualKill) {
            return;
        }

        // NOTE: leave only an even number of base tokens for the DVP epoch
        if (lockedLiquidity % 2 != 0) {
            _state.liquidity.lockedInitially -= 1;
        }

        _adjustBalances();
        // TBD: re-compute here the lockedInitially
    }

    /**
        @notice Computes the share price for the ending epoch
        @param notional_ The DVP portfolio value at the end of the epoch
        @return sharePrice the price of one share
     */
    function _computeSharePrice(uint256 notional_) internal view returns (uint256 sharePrice) {
        uint256 outstandingShares = totalSupply() - _state.withdrawals.heldShares;
        // NOTE: if the number of shares is 0, pricePerShare will revert due to a division by zero
        if (outstandingShares == 0) {
            // First time mint 1 share for each token
            sharePrice = VaultLib.UNIT_PRICE;
        } else {
            // NOTE: if the locked liquidity is 0, the price is set to 0
            sharePrice = VaultLib.pricePerShare(notional_, outstandingShares);
        }
    }

    /**
        @notice Adjust the balances in order to cover the liquidity locked for pending operations and obtain an equal weight portfolio.
        @dev We are ignoring fees...
     */
    function _adjustBalances() internal {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        uint256 baseTokens = IERC20(baseToken).balanceOf(address(this));
        uint256 sideTokens = IERC20(sideToken).balanceOf(address(this));
        uint256 pendings = _state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs;

        if (baseTokens < pendings) {
            // We must cover the missing base tokens by selling an amount of side tokens:
            uint256 baseTokensToReserve = pendings - baseTokens;
            uint256 sideTokensToSellForCoveringMissingBaseTokens = exchange.getInputAmount(
                sideToken,
                baseToken,
                baseTokensToReserve
            );

            // Once we covered the missing base tokens, we still have to reach
            // an equal weight portfolio of unlocked liquidity, so we also have
            // to sell half of the remaining side tokens.
            uint256 halfOfRemainingSideTokens = (sideTokens - sideTokensToSellForCoveringMissingBaseTokens) / 2;

            uint256 sideTokensToSell = sideTokensToSellForCoveringMissingBaseTokens + halfOfRemainingSideTokens;
            _sellSideTokens(sideTokensToSell);
        } else {
            uint256 halfNotional = notional() / 2;
            uint256 targetSideTokens = exchange.getOutputAmount(baseToken, sideToken, halfNotional);

            // NOTE: here we are not interested in the number of exchanged base tokens
            _deltaHedge(int256(targetSideTokens) - int256(sideTokens));
        }
    }

    /// @inheritdoc IVault
    function deltaHedge(int256 sideTokensAmount) external onlyDVP isNotDead returns (uint256 baseTokens) {
        return _deltaHedge(sideTokensAmount);
    }

    /**
        @notice Adjust the portfolio by trading the given amount of side tokens.
        @param sideTokensAmount The amount of side tokens to buy (positive value) / sell (negative value).
        @return baseTokens The amount of exchanged base tokens.
     */
    function _deltaHedge(int256 sideTokensAmount) internal returns (uint256 baseTokens) {
        if (sideTokensAmount > 0) {
            uint256 amount = uint256(sideTokensAmount);
            return _buySideTokens(amount);
        } else {
            uint256 amount = uint256(-sideTokensAmount);
            return _sellSideTokens(amount);
        }
    }

    /**
        @notice Swap some of the available base tokens in order to obtain the provided amount of side tokens.
        @param amount The amount of side tokens to buy.
        @return baseTokens The amount of exchanged base tokens.
     */
    function _buySideTokens(uint256 amount) internal returns (uint256 baseTokens) {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        uint256 baseTokensAmount = exchange.getInputAmount(baseToken, sideToken, amount);

        // Should never happen: `_deltaHedge()` should call this function with a correct amount of side tokens
        // But the DVP client of `deltaHedge()` may not... (ToDo: verify!)
        if (baseTokensAmount > _notionalBaseTokens()) {
            revert ExceedsAvailable();
        }

        bool ok = IERC20(baseToken).approve(exchangeAddress, baseTokensAmount);
        if (!ok) {
            revert ApproveFailed();
        }
        baseTokens = exchange.swapOut(baseToken, sideToken, amount);
    }

    /**
        @notice Swap the provided amount of side tokens in exchange for base tokens.
        @param amount The amount of side tokens to sell.
        @return baseTokens The amount of exchanged base tokens.
     */
    function _sellSideTokens(uint256 amount) internal returns (uint256 baseTokens) {
        uint256 sideTokens = IERC20(sideToken).balanceOf(address(this));
        if (amount > sideTokens) {
            revert ExceedsAvailable();
        }

        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        bool ok = IERC20(sideToken).approve(exchangeAddress, amount);
        if (!ok) {
            revert ApproveFailed();
        }
        baseTokens = exchange.swapIn(sideToken, baseToken, amount);
    }

    /// @inheritdoc IVault
    function reservePayoff(uint256 residualPayoff) external onlyDVP {
        _state.liquidity.newPendingPayoffs = residualPayoff;
    }

    /// @inheritdoc IVault
    function transferPayoff(address recipient, uint256 amount, bool isPastEpoch) external onlyDVP {
        if (amount == 0) {
            return;
        }

        if (isPastEpoch) {
            if (amount > _state.liquidity.pendingPayoffs) {
                revert ExceedsAvailable();
            }
            _state.liquidity.pendingPayoffs -= amount;
        } else {
            // NOTE: it should never happen as `_deltaHedge()` must always be executed before transfers
            if (amount > _notionalBaseTokens()) {
                revert ExceedsAvailable();
            }
        }

        if (!IERC20(baseToken).transfer(recipient, amount)) {
            revert TransferFailed();
        }
    }

    /// @inheritdoc ERC20
    /// @dev Block transfer of shares when not allowed (for testnet purposes)
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
        if (!_secondaryMarkedAllowed) {
            revert SecondaryMarkedNotAllowed();
        }
    }

    /**
        @notice Allows the contract's owner to enable or disable the secondary market for the vault's shares.
     */
    function setAllowedSecondaryMarked(bool allowed) external onlyOwner {
        _secondaryMarkedAllowed = allowed;
    }
}
