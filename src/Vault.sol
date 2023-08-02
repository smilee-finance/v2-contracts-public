// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IExchange} from "./interfaces/IExchange.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVaultParams} from "./interfaces/IVaultParams.sol";
import {TokensPair} from "./lib/TokensPair.sol";
import {VaultLib} from "./lib/VaultLib.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {EpochControls} from "./EpochControls.sol";

contract Vault is IVault, ERC20, EpochControls, Ownable {
    using SafeMath for uint256;
    using VaultLib for VaultLib.DepositReceipt;

    /// @inheritdoc IVaultParams
    address public immutable baseToken;
    /// @inheritdoc IVaultParams
    address public immutable sideToken;

    VaultLib.VaultState internal _state;
    AddressProvider internal immutable _addressProvider;
    /// @notice The address of the DVP paired with this vault
    address public dvp; // NOTE: public for frontend purposes
    /// @notice Whether the transfer of shares between wallets is allowed or not
    bool internal _secondaryMarkedAllowed;

    // TBD: add to the IVault interface
    mapping(address => VaultLib.DepositReceipt) public depositReceipts;
    // TBD: add to the IVault interface
    mapping(address => VaultLib.Withdrawal) public withdrawals; // TBD: append receipt to the name
    mapping(uint256 => uint256) public epochPricePerShare; // NOTE: public for frontend and historical data purposes

    error DVPNotSet();
    error OnlyDVPAllowed();
    error AmountZero();
    error AddressZero();
    error ExceedsAvailable();
    error ExistingIncompleteWithdraw();
    error NothingToRescue();
    error SecondaryMarkedNotAllowed();
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
    ) EpochControls(epochFrequency_) ERC20("", "") Ownable() {
        TokensPair.validate(TokensPair.Pair({
            baseToken: baseToken_,
            sideToken: sideToken_
        }));
        baseToken = baseToken_;
        sideToken = sideToken_;

        _addressProvider = AddressProvider(addressProvider_);
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

    // ToDo: review as it's currently used only by tests
    // / @inheritdoc IVault
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

    /**
        @notice Allows to provide liquidity for the next epoch.
        @param amount The amount of base token to deposit.
        @dev The shares are not directly minted to the user. We need to wait for epoch change in order to know how many
        shares these assets correspond to. So shares are minted to the contract in `rollEpoch()` and owed to the depositor.
        @dev The liquidity provider can redeem its shares after the next epoch is rolled.
        @dev The user must approve the vault on the base token contract before attempting this operation.
     */
    function deposit(uint256 amount) external epochInitialized isNotDead epochNotFrozen {
        if (amount == 0) {
            revert AmountZero();
        }

        // TBD: accept only if it doesn't exceeds the TVL limit (cap)
        // ---- limitTVL - lockedInitially >= amount

        address creditor = msg.sender;

        IERC20(baseToken).transferFrom(creditor, address(this), amount);
        _emitUpdatedDepositReceipt(creditor, amount);

        _state.liquidity.pendingDeposits += amount;

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

        // Get the number of unredeemed shares from previous deposits, if any.
        // NOTE: the amount of unredeemed shares is the one of the previous epochs, as we still don't know the share price.
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            epochPricePerShare[depositReceipt.epoch]
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
            currentEpoch,
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
            currentEpoch,
            epochPricePerShare[depositReceipt.epoch]
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

    /**
        @notice Pre-order a withdrawal that can be executed after the end of the current epoch
        @param shares is the number of shares to convert in withdrawed liquidity
     */
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

    /**
        @notice Completes a scheduled withdrawal from a past epoch. Uses finalized share price for the epoch.
     */
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
        uint256 amountToWithdraw = VaultLib.sharesToAsset(sharesToWithdraw, epochPricePerShare[withdrawal.epoch]);

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

    // ------------------------------------------------------------------------
    // VAULT OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc EpochControls
    function _beforeRollEpoch() internal virtual override isNotDead {
        if (dvp != address(0) && msg.sender != dvp) {
            // NOTE: must be called only by the DVP after a DVP has been set.
            revert OnlyDVPAllowed();
        }

        // TBD: a dead vault can be revived ?
        // ToDo: review variable name
        uint256 lockedLiquidity = notional();

        // NOTE: the share price needs to account also the payoffs
        lockedLiquidity -= _state.liquidity.newPendingPayoffs;

        // TBD: rename to shareValue
        uint256 sharePrice = _computeSharePrice(lockedLiquidity);
        epochPricePerShare[currentEpoch] = sharePrice;

        if (sharePrice == 0) {
            // if vault underlying asset disappear, don't mint any shares.
            // Pending deposits will be enabled for withdrawal - see rescueDeposit()
            _state.dead = true;
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

        if (_state.dead) {
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
            uint256 sideTokensToSellForCoveringMissingBaseTokens = exchange.getInputAmount(sideToken, baseToken, baseTokensToReserve);

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
    function deltaHedge(int256 sideTokensAmount) external onlyDVP returns (uint256 baseTokens) {
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

        IERC20(baseToken).approve(exchangeAddress, baseTokensAmount);
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

        IERC20(sideToken).approve(exchangeAddress, amount);
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

        IERC20(baseToken).transfer(recipient, amount);
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
