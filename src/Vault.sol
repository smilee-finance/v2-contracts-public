// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAddressProvider} from "./interfaces/IAddressProvider.sol";
import {IExchange} from "./interfaces/IExchange.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVaultAccessNFT} from "./interfaces/IVaultAccessNFT.sol";
import {IVaultParams} from "./interfaces/IVaultParams.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";
import {Epoch, EpochController} from "./lib/EpochController.sol";
import {TokensPair} from "./lib/TokensPair.sol";
import {VaultLib} from "./lib/VaultLib.sol";
import {EpochControls} from "./EpochControls.sol";

contract Vault is IVault, ERC20, EpochControls, AccessControl, Pausable {
    using AmountsMath for uint256;
    using VaultLib for VaultLib.DepositReceipt;
    using EpochController for Epoch;
    using SafeERC20 for IERC20;

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
    mapping(address => VaultLib.Withdrawal) public withdrawals;

    mapping(uint256 => uint256) public epochPricePerShare; // NOTE: public for frontend and historical data purposes

    VaultLib.VaultState internal _state;

    bool public manuallyKilled;

    /// @notice The provider for external services addresses
    IAddressProvider internal immutable _addressProvider;

    /// @notice A flag to tell if this vault is currently bound to priority access for deposits
    bool public priorityAccessFlag = false;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    bytes32 public constant ROLE_EPOCH_ROLLER = keccak256("ROLE_EPOCH_ROLLER");

    error AddressZero();
    error AmountZero();
    error DVPAlreadySet();
    error DVPNotSet();
    error ExceedsAvailable();
    error ExceedsMaxDeposit();
    error ExistingIncompleteWithdraw();
    error NothingToRescue();
    error NothingToWithdraw();
    error OnlyDVPAllowed();
    error PriorityAccessDenied();
    error SecondaryMarketNotAllowed();
    error VaultDead();
    error VaultNotDead();
    error WithdrawNotInitiated();
    error WithdrawTooEarly();
    error NotManuallyKilled();

    event Deposit(uint256 amount);
    event Redeem(uint256 amount);
    event InitiateWithdraw(uint256 amount);
    event Withdraw(uint256 amount);

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_,
        address addressProvider_
    ) ERC20("Smilee Share", ":)") EpochControls(epochFrequency_) AccessControl() Pausable() {
        TokensPair.validate(TokensPair.Pair({baseToken: baseToken_, sideToken: sideToken_}));
        baseToken = baseToken_;
        sideToken = sideToken_;

        _addressProvider = IAddressProvider(addressProvider_);
        // ToDo: move to constructor parameter (wrong decimals)
        maxDeposit = 10_000_000e18;

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);
        _setRoleAdmin(ROLE_EPOCH_ROLLER, ROLE_ADMIN);

        _grantRole(ROLE_GOD, msg.sender);
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(baseToken).decimals();
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
        @notice Allows the contract's owner to set the DVP paired with this vault
        @dev The address is injected after-build, because the DVP needs an already built vault as constructor-injected dependency
     */
    function setAllowedDVP(address dvp_) external {
        _checkRole(ROLE_ADMIN);

        if (dvp != address(0)) {
            revert DVPAlreadySet();
        }

        dvp = dvp_;
        _grantRole(ROLE_EPOCH_ROLLER, dvp_);
    }

    /**
        @notice Set maximum deposit capacity for the Vault
        @param maxDeposit_ The number of base tokens
     */
    function setMaxDeposit(uint256 maxDeposit_) public {
        _checkRole(ROLE_ADMIN);

        maxDeposit = maxDeposit_;
    }

    function killVault() external {
        _checkRole(ROLE_ADMIN);

        manuallyKilled = true;
    }

    /**
     *
     * @return totalDeposit Represent the overall deposit value
     * @return dead Check if the vault is dead or not
     * @return deadReason The reason of the death
     */
    function getInfo() external view returns (uint256, bool, bytes4) {
        return (_state.liquidity.totalDeposit, _state.dead, _state.deadReason);
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
        (uint256 baseTokens, ) = _tokenBalances();

        return
            baseTokens -
            _state.liquidity.pendingWithdrawals -
            _state.liquidity.pendingDeposits -
            _state.liquidity.pendingPayoffs;
    }

    /**
        @notice Provides the amount of side tokens from the portfolio of the current epoch.
        @return amount_ The amount of side tokens
     */
    function _notionalSideTokens() internal view returns (uint256 amount_) {
        (, amount_) = _tokenBalances();
    }

    function _tokenBalances() internal view returns (uint256 baseTokens, uint256 sideTokens) {
        baseTokens = IERC20(baseToken).balanceOf(address(this));
        sideTokens = IERC20(sideToken).balanceOf(address(this));
    }

    /// @inheritdoc IVault
    function v0() public view virtual returns (uint256) {
        return _state.liquidity.lockedInitially;
    }

    /// @inheritdoc IVault
    function changePauseState() external override {
        _checkRole(ROLE_ADMIN);

        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    // ------------------------------------------------------------------------
    // USER OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc IVault
    function deposit(uint256 amount, address receiver, uint256 accessTokenId) external isNotDead whenNotPaused {
        _checkEpochNotFinished();

        if (amount == 0) {
            revert AmountZero();
        }

        // Avoids underflows when the maxDeposit is setted below than the totalDeposit
        if (_state.liquidity.totalDeposit > maxDeposit) {
            revert ExceedsMaxDeposit();
        }

        uint256 depositCapacity = maxDeposit - _state.liquidity.totalDeposit;
        if (amount > depositCapacity) {
            revert ExceedsMaxDeposit();
        }

        _usePriorityAccess(amount, receiver, accessTokenId);

        _state.liquidity.pendingDeposits += amount;
        _state.liquidity.totalDeposit += amount;
        _emitUpdatedDepositReceipt(receiver, amount);

        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(amount);
    }

    /**
        @notice Create or update a deposit receipt for a given deposit operation.
        @param creditor The wallet of the creditor
        @param amount The deposited amount
        @dev The deposit receipt allows the creditor to redeem its shares or withdraw liquidity.
     */
    function _emitUpdatedDepositReceipt(address creditor, uint256 amount) internal {
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[creditor];
        Epoch memory epoch = getEpoch();

        // If the user has already deposited in the current epoch, add the amount to the total one of the next epoch:
        if (epoch.current == depositReceipt.epoch) {
            amount = depositReceipt.amount.add(amount);
        }

        // Get the number of unredeemed shares from previous deposits, if any.
        // NOTE: the amount of unredeemed shares is the one of the previous epochs, as we still don't know the share price.
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            epoch.current,
            epochPricePerShare[depositReceipt.epoch],
            decimals()
        );

        depositReceipt.epoch = epoch.current;
        depositReceipt.amount = amount;
        depositReceipt.cumulativeAmount = depositReceipt.cumulativeAmount.add(amount);
        depositReceipt.unredeemedShares = unredeemedShares;
    }

    /**
        @notice Get wallet balance of actual owned shares and owed shares.
        @return heldByAccount The amount of shares owned by the wallet
        @return heldByVault The amount of shares owed to the wallet
     */
    function shareBalances(address account) public view returns (uint256 heldByAccount, uint256 heldByVault) {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[account];

        if (depositReceipt.epoch == 0) {
            return (0, 0);
        }

        heldByAccount = balanceOf(account);

        heldByVault = depositReceipt.getSharesFromReceipt(
            getEpoch().current,
            epochPricePerShare[depositReceipt.epoch],
            decimals()
        );
    }

    /**
        @notice Redeems shares held by the vault for the calling wallet
        @param shares is the number of shares to redeem
     */
    function redeem(uint256 shares) external whenNotPaused {
        if (shares == 0) {
            revert AmountZero();
        }
        // NOTE: if the epoch has not been initialized, it reverts with ExceedsAvailable.
        _redeem(shares, false);
    }

    function _redeem(uint256 shares, bool isMax) internal {
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        Epoch memory epoch = getEpoch();

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            epoch.current,
            epochPricePerShare[depositReceipt.epoch],
            decimals()
        );

        if (!isMax && shares > unredeemedShares) {
            revert ExceedsAvailable();
        }

        if (isMax) {
            shares = unredeemedShares;
        }

        if (depositReceipt.epoch < epoch.current) {
            // NOTE: all the amount - if any - has already been converted in unredeemedShares.
            depositReceipt.amount = 0;
        }

        depositReceipt.unredeemedShares = unredeemedShares.sub(shares);

        _transfer(address(this), msg.sender, shares);

        emit Redeem(shares);
    }

    /// @inheritdoc IVault
    function initiateWithdraw(uint256 shares) external whenNotPaused {
        _checkEpochNotFinished();

        _initiateWithdraw(shares, false);
    }

    function _initiateWithdraw(uint256 shares, bool isMax) internal {
        if (!isMax && shares == 0) {
            revert AmountZero();
        }

        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[msg.sender];

        // We take advantage of this flow in order to also transfer all the unredeemed shares to the user.
        if (depositReceipt.amount > 0 || depositReceipt.unredeemedShares > 0) {
            _redeem(0, true);
        }

        // NOTE: since we made a 'redeem all', from now on all the user's shares are owned by him.
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
            // if user has already pre-ordered a withdrawal in this epoch just increase the order
            sharesToWithdraw = withdrawal.shares.add(shares);
        }

        // -----------------------------
        // Update vault capacity:
        //   - Estimate the increased capacity by computing the following proportion:
        //       withdrawed_shares : user_shares = x : user_deposits
        //   - Use it by decreasing the current number of deposits.
        //   - update the user's deposit receipt [cumulativeAmount]

        uint256 userCumulativeDeposits = depositReceipt.cumulativeAmount;
        // NOTE: Don't consider the current epoch deposits in the "all-time deposits" computation
        if (depositReceipt.epoch == epoch.current) {
            userCumulativeDeposits -= depositReceipt.amount;
        }

        uint256 withdrawDepositEquivalent = userCumulativeDeposits.wmul(shares).wdiv(userShares);

        // ToDo: review to check if those can underflow under certain circumstances
        depositReceipt.cumulativeAmount -= withdrawDepositEquivalent;
        _state.liquidity.totalDeposit -= withdrawDepositEquivalent;
        // -----------------------------

        // update receipt:
        withdrawal.shares = sharesToWithdraw;
        withdrawal.epoch = epoch.current;

        _state.withdrawals.newHeldShares += shares;

        _transfer(msg.sender, address(this), shares);

        emit InitiateWithdraw(shares);
    }

    /**
        @notice Completes a scheduled withdrawal from a past epoch. Uses finalized share price for the epoch.
     */
    function completeWithdraw() external whenNotPaused {
        _completeWithdraw();
    }

    function _completeWithdraw() internal {
        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        // Checks if there is an initiated withdrawal
        if (withdrawal.shares == 0) {
            revert WithdrawNotInitiated();
        }

        Epoch memory epoch = getEpoch();

        // At least one epoch must have passed since the start of the withdrawal
        if (withdrawal.epoch == epoch.current && _state.deadReason != VaultLib.DeadManualKillReason) {
            revert WithdrawTooEarly();
        }

        uint256 amountToWithdraw;
        if (_state.deadReason == VaultLib.DeadManualKillReason && withdrawal.epoch == epoch.current) {
            amountToWithdraw = VaultLib.sharesToAsset(
                withdrawal.shares,
                epochPricePerShare[epoch.previous],
                decimals()
            );
        } else {
            amountToWithdraw = VaultLib.sharesToAsset(
                withdrawal.shares,
                epochPricePerShare[withdrawal.epoch],
                decimals()
            );
        }

        // NOTE: the user transferred the required shares to the vault when she initiated the withdraw
        if (!_state.dead) {
            _state.withdrawals.heldShares -= withdrawal.shares;
            _state.liquidity.pendingWithdrawals -= amountToWithdraw;
        }

        uint256 sharesToWithdraw = withdrawal.shares;
        withdrawal.shares = 0;
        _burn(address(this), sharesToWithdraw);
        IERC20(baseToken).safeTransfer(msg.sender, amountToWithdraw);

        emit Withdraw(amountToWithdraw);
    }

    /**
        @notice Enables user withdrawal of a deposits executed during an epoch causing Vault death
     */
    function rescueDeposit() external isDead whenNotPaused {
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[msg.sender];

        // User enabled to rescue only if the user has deposited in the last epoch before the Vault died.
        if (depositReceipt.epoch != getEpoch().previous) {
            revert NothingToRescue();
        }

        _state.liquidity.pendingDeposits -= depositReceipt.amount;

        uint256 rescuedAmount = depositReceipt.amount;
        depositReceipt.amount = 0;
        IERC20(baseToken).safeTransfer(msg.sender, rescuedAmount);
    }

    function rescueShares() external isDead whenNotPaused {
        if (!manuallyKilled) {
            revert NotManuallyKilled();
        }

        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        // If an uncompleted withdraw exists, complete this one before to start with new one.
        if (withdrawal.shares > 0) {
            _completeWithdraw();
        }

        _initiateWithdraw(0, true);
        _completeWithdraw();
    }

    /**
        @notice Allows the contract's owner to enable or disable the priority access to deposit operations
     */
    function setPriorityAccessFlag(bool flag) external {
        _checkRole(ROLE_ADMIN);

        priorityAccessFlag = flag;
    }

    // ------------------------------------------------------------------------
    // VAULT OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc EpochControls
    function _beforeRollEpoch() internal virtual override isNotDead {
        _checkRole(ROLE_EPOCH_ROLLER);

        uint256 lockedLiquidity = notional();
        // NOTE: the share price needs to account also the payoffs
        lockedLiquidity -= _state.liquidity.newPendingPayoffs;

        {
            if (lockedLiquidity > _state.liquidity.lockedInitially) {
                uint256 netPerformance = lockedLiquidity - _state.liquidity.lockedInitially;
                uint256 fee = IFeeManager(_addressProvider.feeManager()).vaultFee(
                    netPerformance,
                    IERC20Metadata(baseToken).decimals()
                );

                if (lockedLiquidity - fee >= _state.liquidity.lockedInitially) {
                    IERC20(baseToken).safeApprove(_addressProvider.feeManager(), fee);
                    IFeeManager(_addressProvider.feeManager()).receiveFee(fee);
                    lockedLiquidity -= fee;
                }
            }
        }

        if (manuallyKilled) {
            _state.dead = true;

            // Sell all sideToken to be able to pay all the withdraws initiated after manual kill.
            (, uint256 sideTokens) = _tokenBalances();
            _sellSideTokens(sideTokens);
        }

        uint256 sharePrice = _computeSharePrice(lockedLiquidity);
        epochPricePerShare[getEpoch().current] = sharePrice;

        if (sharePrice == 0) {
            // if vault underlying asset disappear, don't mint any shares.
            // Pending deposits will be enabled for withdrawal - see rescueDeposit()
            _state.dead = true;
            _state.deadReason = VaultLib.DeadMarketReason;
        }

        if (manuallyKilled) {
            _state.deadReason = VaultLib.DeadManualKillReason;
        }

        // Increase shares hold due to initiated withdrawals:
        _state.withdrawals.heldShares += _state.withdrawals.newHeldShares;

        // Reserve the liquidity needed to cover the withdrawals initiated in the current epoch:
        // NOTE: here we just account the amounts and we delay all the actual swaps to the final one in order to optimize them.
        // NOTE: if sharePrice is zero, the users will receive zero from withdrawals
        uint256 newPendingWithdrawals = VaultLib.sharesToAsset(
            _state.withdrawals.newHeldShares,
            sharePrice,
            decimals()
        );
        _state.liquidity.pendingWithdrawals += newPendingWithdrawals;
        lockedLiquidity -= newPendingWithdrawals;

        // Reset the counter for the next epoch:
        _state.withdrawals.newHeldShares = 0;

        // Set aside the payoff to be paid:
        _state.liquidity.pendingPayoffs += _state.liquidity.newPendingPayoffs;

        // _state.liquidity.newPendingPayoffs are set to 0 by `adjustReservedPayoff()`;

        if (_state.dead && !manuallyKilled) {
            _state.liquidity.lockedInitially = 0;
            return;
        }

        // Mint shares related to new deposits performed during the closing epoch:
        uint256 sharesToMint = VaultLib.assetToShares(_state.liquidity.pendingDeposits, sharePrice, decimals());
        _mint(address(this), sharesToMint);

        lockedLiquidity += _state.liquidity.pendingDeposits;
        _state.liquidity.pendingDeposits = 0;

        _state.liquidity.lockedInitially = lockedLiquidity;

        if (manuallyKilled) {
            return;
        }

        // NOTE: leave only an even number of base tokens for the DVP epoch
        if (lockedLiquidity % 2 != 0) {
            _state.liquidity.lockedInitially -= 1;
        }

        _adjustBalances();
    }

    // ToDo: review as notional and price may have different decimals!
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
            sharePrice = 10 ** decimals();
        } else {
            // NOTE: if the locked liquidity is 0, the price is set to 0
            sharePrice = VaultLib.pricePerShare(notional_, outstandingShares, decimals());
        }
    }

    /// @notice Adjusts the balances in order to cover the liquidity locked for pending operations and obtain an equal weight portfolio.
    function _adjustBalances() internal {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        (uint256 baseTokens, uint256 sideTokens) = _tokenBalances();
        uint256 pendings = _state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs;

        if (baseTokens < pendings) {
            // We must cover the missing base tokens by selling an amount of side tokens:
            uint256 missingBaseTokens = pendings - baseTokens;
            uint256 sideTokensToSellToCoverMissingBaseTokens = exchange.getInputAmount(
                sideToken,
                baseToken,
                missingBaseTokens
            );

            // Once we covered the missing base tokens, we still have to reach
            // an equal weight portfolio of unlocked liquidity, so we also have
            // to sell half of the remaining side tokens.
            uint256 halfOfRemainingSideTokens = (sideTokens - sideTokensToSellToCoverMissingBaseTokens) / 2;

            uint256 sideTokensToSell = sideTokensToSellToCoverMissingBaseTokens + halfOfRemainingSideTokens;
            _sellSideTokens(sideTokensToSell);
        } else {
            uint256 halfNotional = notional() / 2;
            uint256 targetSideTokens = exchange.getOutputAmount(baseToken, sideToken, halfNotional);

            // NOTE: here we are not interested in the number of exchanged base tokens
            _deltaHedge(int256(targetSideTokens) - int256(sideTokens));
        }
    }

    /// @inheritdoc IVault
    function deltaHedge(int256 sideTokensAmount) external onlyDVP isNotDead whenNotPaused returns (uint256 baseTokens) {
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

        uint256 baseTokensAmount = exchange.getInputAmountMax(baseToken, sideToken, amount);

        // Should never happen: `_deltaHedge()` should call this function with a correct amount of side tokens
        // But the DVP client of `deltaHedge()` may not...
        if (baseTokensAmount > _notionalBaseTokens()) {
            revert ExceedsAvailable();
        }

        IERC20(baseToken).safeApprove(exchangeAddress, baseTokensAmount);
        baseTokens = exchange.swapOut(baseToken, sideToken, amount, baseTokensAmount);
    }

    /**
        @notice Swap the provided amount of side tokens in exchange for base tokens.
        @param amount The amount of side tokens to sell.
        @return baseTokens The amount of exchanged base tokens.
     */
    function _sellSideTokens(uint256 amount) internal returns (uint256 baseTokens) {
        (, uint256 sideTokens) = _tokenBalances();
        if (amount > sideTokens) {
            revert ExceedsAvailable();
        }

        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        IERC20(sideToken).safeApprove(exchangeAddress, amount);
        baseTokens = exchange.swapIn(sideToken, baseToken, amount);
    }

    /// @inheritdoc IVault
    function reservePayoff(uint256 residualPayoff) external onlyDVP {
        _state.liquidity.newPendingPayoffs = residualPayoff;
    }

    /// @inheritdoc IVault
    function adjustReservedPayoff(uint256 adjustedPayoff) external onlyDVP {
        _state.liquidity.pendingPayoffs =
            _state.liquidity.pendingPayoffs -
            _state.liquidity.newPendingPayoffs +
            adjustedPayoff;
        _state.liquidity.newPendingPayoffs = 0;
    }

    /// @inheritdoc IVault
    function transferPayoff(address recipient, uint256 amount, bool isPastEpoch) external onlyDVP whenNotPaused {
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

        IERC20(baseToken).safeTransfer(recipient, amount);
    }

    /// @dev Checks if given deposit is allowed to be made and calls nft usage callback function if needed
    function _usePriorityAccess(uint256 amount, address receiver, uint256 accessTokenId) private {
        if (priorityAccessFlag) {
            IVaultAccessNFT nft = IVaultAccessNFT(_addressProvider.vaultAccessNFT());
            if (accessTokenId == 0 || nft.ownerOf(accessTokenId) != receiver) {
                revert PriorityAccessDenied();
            }
            if (amount > nft.priorityAmount(accessTokenId)) {
                revert PriorityAccessDenied();
            }
            nft.decreasePriorityAmount(accessTokenId, amount);
        }
    }
}
