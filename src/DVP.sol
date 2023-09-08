// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IDVP, IDVPImmutables} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IToken} from "./interfaces/IToken.sol";
import {IVault} from "./interfaces/IVault.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";
import {Notional} from "./lib/Notional.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {Position} from "./lib/Position.sol";
import {SignedMath} from "./lib/SignedMath.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {EpochControls} from "./EpochControls.sol";

abstract contract DVP is IDVP, EpochControls {
    using AmountsMath for uint256;
    using Position for Position.Info;
    using Notional for Notional.Info;

    /// @inheritdoc IDVPImmutables
    address public immutable override baseToken;
    /// @inheritdoc IDVPImmutables
    address public immutable override sideToken;
    // /// @inheritdoc IDVPImmutables
    bool public immutable override optionType; // ToDo: review (it's a DVPType)
    /// @inheritdoc IDVP
    address public immutable override vault;
    AddressProvider internal immutable _addressProvider;
    /// @dev mutable parameter for the computation of the trade volatility
    uint256 internal _tradeVolatilityUtilizationRateFactor;
    /// @dev mutable parameter for the computation of the trade volatility
    uint256 internal _tradeVolatilityTimeDecay;
    uint8 internal immutable _baseTokenDecimals;
    uint8 internal immutable _sideTokenDecimals;
    // ToDo: define lot size

    // TBD: extract payoff from Notional.Info
    // TBD: move strike and strategy outside of struct as indexes
    // TBD: merge with _epochPositions as both are indexed by epoch
    /**
        @notice liquidity for options indexed by epoch
        @dev mapping epoch -> Notional.Info
     */
    mapping(uint256 => Notional.Info) internal _liquidity;

    // ToDo: review definition of position ID
    /**
        @notice Users positions
        @dev mapping epoch -> Position.getID(...) -> Position.Info
        @dev There is an index by epoch in order to further avoid collisions within the hash of the position ID.
     */
    mapping(uint256 => mapping(bytes32 => Position.Info)) internal _epochPositions;

    error TransferFailed();
    error NotEnoughLiquidity();
    error PositionNotFound();
    error CantBurnMoreThanMinted();
    error VaultPaused();
    error MissingMarketOracle();
    error MissingPriceOracle();
    error SlippedMarketValue();

    modifier whenVaultIsNotPaused() {
        if (IEpochControls(vault).isPaused()) {
            revert VaultPaused();
        }
        _;
    }

    constructor(
        address vault_,
        bool optionType_,
        address addressProvider_
    ) EpochControls(IEpochControls(vault_).epochFrequency()) {
        optionType = optionType_;
        vault = vault_;
        IVault vaultCt = IVault(vault);
        baseToken = vaultCt.baseToken();
        sideToken = vaultCt.sideToken();
        _addressProvider = AddressProvider(addressProvider_);
        _baseTokenDecimals = IToken(baseToken).decimals();
        _sideTokenDecimals = IToken(sideToken).decimals();

        _tradeVolatilityUtilizationRateFactor = AmountsMath.wrap(2);
        _tradeVolatilityTimeDecay = AmountsMath.wrap(1) / 4; // 0.25
    }

    /**
        @notice Mint or increase a position.
        @param recipient The wallet of the recipient for the opened position.
        @param strike The strike.
        @param amount The notional.
        @param expectedPremium The expected premium; used to check the slippage.
        @param maxSlippage The maximum slippage percentage.
        @return premium_ The paid premium.
        @dev The client must have approved the needed premium.
     */
    function _mint(
        address recipient,
        uint256 strike,
        Notional.Amount memory amount,
        uint256 expectedPremium,
        uint256 maxSlippage
    ) internal epochInitialized epochNotFrozen whenNotPaused whenVaultIsNotPaused returns (uint256 premium_) {
        if (amount.up == 0 && amount.down == 0) {
            revert AmountZero();
        }

        Notional.Info storage liquidity = _liquidity[currentEpoch];

        // Check available liquidity:
        if (
            liquidity.available(strike, OptionStrategy.CALL) < amount.up ||
            liquidity.available(strike, OptionStrategy.PUT) < amount.down
        ) {
            revert NotEnoughLiquidity();
        }

        uint256 swapPrice = _deltaHedgePosition(strike, amount, true);

        premium_ = _getMarketValue(strike, amount, true, swapPrice);

        // Revert if actual price exceeds the previewed premium
        // ----- TBD: use the approved premium as a reference ? No due to the PositionManager...
        // ----- TBD: Right now we may choose to use a DVP-wide slippage of +10% (-10% for burn).
        if (premium_ > expectedPremium + expectedPremium.wmul(maxSlippage)) {
            revert SlippedMarketValue();
        }
        // ToDo: revert if the premium is zero due to an underflow
        // ----- it may be avoided by asking for a positive number of lots as notional...

        // Get premium from sender:
        if (!IToken(baseToken).transferFrom(msg.sender, vault, premium_)) {
            revert TransferFailed();
        }

        // Decrease available liquidity:
        liquidity.increaseUsage(strike, OptionStrategy.CALL, amount.up);
        liquidity.increaseUsage(strike, OptionStrategy.PUT, amount.down);

        // Create or update position:
        Position.Info storage position = _getPosition(currentEpoch, recipient, strike);
        position.epoch = currentEpoch;
        position.strike = strike;
        position.amountUp += amount.up;
        position.amountDown += amount.down;

        emit Mint(msg.sender, recipient);
    }

    /**
        @notice It attempts to flat the DVP's delta by selling/buying an amount of side tokens in order to hedge the position.
        @notice By hedging the position, we avoid the impermanent loss.
        @param strike The position strike.
        @param amount The position notional.
        @param tradeIsBuy Positive if buyed by a user, negative otherwise.
     */
    function _deltaHedgePosition(
        uint256 strike,
        Notional.Amount memory amount,
        bool tradeIsBuy
    ) internal virtual returns (uint256 swapPrice);

    /**
        @notice Burn or decrease a position.
        @param epoch The epoch of the position.
        @param recipient The wallet of the recipient for the opened position.
        @param strike The strike
        @param amount The notional.
        @param expectedMarketValue The expected market value when the epoch is the current one.
        @param maxSlippage The maximum slippage percentage.
        @return paidPayoff The paid payoff.
     */
    function _burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        Notional.Amount memory amount,
        uint256 expectedMarketValue,
        uint256 maxSlippage
    ) internal epochInitialized epochNotFrozen whenNotPaused whenVaultIsNotPaused returns (uint256 paidPayoff) {
        Position.Info storage position = _getPosition(epoch, msg.sender, strike);
        if (!position.exists()) {
            revert PositionNotFound();
        }

        // // If the position reached maturity, the user must close the entire position
        // // NOTE: we have to avoid this due to the PositionManager that holds positions for multiple tokens.
        // if (position.epoch != currentEpoch) {
        //     amount = position.amount;
        // }
        if (amount.up == 0 && amount.down == 0) {
            // NOTE: a zero amount may have some parasite effect, henct we proactively protect against it.
            // ToDo: review
            revert AmountZero();
        }
        if (amount.up > position.amountUp || amount.down > position.amountDown) {
            revert CantBurnMoreThanMinted();
        }

        Notional.Info storage liquidity = _liquidity[epoch];

        bool pastEpoch = true;
        if (epoch == currentEpoch) {
            pastEpoch = false;
            // TBD: add comments
            uint256 swapPrice = _deltaHedgePosition(strike, amount, false);
            // Compute the payoff to be paid:
            paidPayoff = _getMarketValue(strike, amount, false, swapPrice);
            if (paidPayoff < expectedMarketValue - expectedMarketValue.wmul(maxSlippage)) {
                revert SlippedMarketValue();
            }
        } else {
            // Compute the payoff to be paid:
            if (amount.up > 0) {
                uint256 payoff_ = liquidity.shareOfPayoff(strike, OptionStrategy.CALL, amount.up, _baseTokenDecimals);
                paidPayoff += payoff_;
                // Account transfer of setted aside payoff:
                liquidity.decreasePayoff(strike, OptionStrategy.CALL, payoff_);
            }
            if (amount.down > 0) {
                uint256 payoff_ = liquidity.shareOfPayoff(strike, OptionStrategy.PUT, amount.down, _baseTokenDecimals);
                paidPayoff += payoff_;
                // Account transfer of setted aside payoff:
                liquidity.decreasePayoff(strike, OptionStrategy.PUT, payoff_);
            }
        }

        // Account change of used liquidity between wallet and protocol:
        position.amountUp -= amount.up;
        position.amountDown -= amount.down;
        // NOTE: must be updated after the previous computations based on used liquidity.
        liquidity.decreaseUsage(strike, OptionStrategy.CALL, amount.up);
        liquidity.decreaseUsage(strike, OptionStrategy.PUT, amount.down);

        IVault(vault).transferPayoff(recipient, paidPayoff, pastEpoch);

        emit Burn(msg.sender);
    }

    /// @inheritdoc EpochControls
    function _beforeRollEpoch() internal virtual override {
        if (_isEpochInitialized()) {
            // Accounts the payoff for each strike and strategy of the positions in circulation that is still to be redeemed:
            _accountResidualPayoffs();
            // Reserve the payoff of those positions:
            uint256 payoffToReserve = _residualPayoff();
            IVault(vault).reservePayoff(payoffToReserve);
        }

        IEpochControls(vault).rollEpoch();
        // TBD: check if vault is dead and set a specific internal state ?
    }

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        // TBD: check if the epoch was initialized ?
        // TBD: set a specific internal state if the initial capital is zero ?
        uint256 initialCapital = IVault(vault).v0();
        _allocateLiquidity(initialCapital);
    }

    /**
        @notice Setup initial notional for a new epoch.
        @param initialCapital The initial notional.
        @dev The concrete DVP must allocate the initial notional on the various strikes and strategies.
     */
    function _allocateLiquidity(uint256 initialCapital) internal virtual;

    /**
        @notice computes and stores the residual payoffs of the positions in circulation that is still to be redeemed for the closing epoch.
        @dev The concrete DVP must compute and account the payoff for the various strikes and strategies.
     */
    function _accountResidualPayoffs() internal virtual;

    /**
        @notice Utility function made in order to simplify the work done in _accountResidualPayoffs().
     */
    function _accountResidualPayoff(uint256 strike, bool strategy) internal {
        Notional.Info storage liquidity = _liquidity[currentEpoch];

        // computes the payoff to be set aside at the end of the epoch for the provided strike and strategy.
        uint256 payoff_ = 0;
        uint256 residualAmount = liquidity.getUsed(strike, strategy);
        if (residualAmount > 0) {
            payoff_ = _computeResidualPayoff(strike, strategy, residualAmount);
        }
        liquidity.accountPayoff(strike, strategy, payoff_);
    }

    /**
        @notice Returns the accounted payoff of the positions in circulation that is still to be redeemed.
        @return residualPayoff the overall payoff to be set aside for the closing epoch.
        @dev The concrete DVP must iterate on the various strikes and strategies.
     */
    function _residualPayoff() internal view virtual returns (uint256 residualPayoff);

    // TBD: inline with _accountResidualPayoff
    /**
        @notice Compute the payoff of a position within the current epoch.
        @param strike the position strike.
        @param strategy the position strategy.
        @param amount the position notional.
        @return payoff_ The payoff value.
        @dev It's also used for the DVP's overall position at maturity.
     */
    function _computeResidualPayoff(
        uint256 strike,
        bool strategy,
        uint256 amount
    ) internal view returns (uint256 payoff_) {
        amount = AmountsMath.wrapDecimals(amount, _baseTokenDecimals);
        uint256 percentage = _residualPayoffPerc(strike, strategy);

        payoff_ = amount.wmul(percentage);
        payoff_ = AmountsMath.unwrapDecimals(payoff_, _baseTokenDecimals);
    }

    /**
        @notice computes the payoff percentage (a scale factor) for the given strike and strategy at epoch end.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return percentage the payoff percentage.
        @dev The percentage is expected to be defined in Wad (i.e. 100 % := 1e18)
     */
    function _residualPayoffPerc(uint256 strike, bool strategy) internal view virtual returns (uint256 percentage);

    /// @dev computes the premium/payoff with the given amount, swap price and post-trade volatility
    function _getMarketValue(
        uint256 strike,
        Notional.Amount memory amount,
        bool tradeIsBuy,
        uint256 swapPrice
    ) internal view virtual returns (uint256);

    /// @inheritdoc IDVP
    function payoff(
        uint256 epoch,
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) public view virtual returns (uint256 payoff_) {
        Position.Info storage position = _getPosition(epoch, msg.sender, strike);
        if (!position.exists()) {
            // TBD: return 0
            revert PositionNotFound();
        }

        Notional.Amount memory amount_ = Notional.Amount({up: amountUp, down: amountDown});

        if (position.epoch == currentEpoch) {
            // The user wants to know how much it can receive from selling the position before its maturity:
            uint256 swapPrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
            payoff_ = _getMarketValue(strike, amount_, false, swapPrice);
        } else {
            // // The position reached maturity, hence the user must close the entire position:
            // // NOTE: we have to avoid this due to the PositionManager that holds positions for multiple tokens.
            // positionAmount = position.amount;
            // The position is eligible for a share of the <epoch, strike, strategy> payoff set aside at epoch end:
            if (amount_.up > 0) {
                payoff_ += _liquidity[position.epoch].shareOfPayoff(
                    position.strike,
                    OptionStrategy.CALL,
                    amount_.up,
                    _baseTokenDecimals
                );
            }
            if (amount_.down > 0) {
                payoff_ += _liquidity[position.epoch].shareOfPayoff(
                    position.strike,
                    OptionStrategy.PUT,
                    amount_.down,
                    _baseTokenDecimals
                );
            }
        }
    }

    /**
        @notice Lookups the requested position.
        @param epoch The epoch of the position.
        @param owner The owner of the position.
        @param strike The strike of the position.
        @return position_ The requested position.
        @dev The client should check if the position exists by calling `exists()` on it.
     */
    function _getPosition(
        uint256 epoch,
        address owner,
        uint256 strike
    ) internal view returns (Position.Info storage position_) {
        return _epochPositions[epoch][Position.getID(owner, strike)];
    }

    /**
        @notice Get the overall used and total liquidity of the current epoche, independent of strike and strategy.
        @return used The overall used liquidity.
        @return total The overall liquidity.
     */
    function _getUtilizationRateFactors() internal view virtual returns (uint256 used, uint256 total);

    // TBD: is this needed ?
    // function getUtilizationRate() public view returns (uint256) {
    //     (uint256 used, uint256 total) = _getUtilizationRateFactors();

    //     used = AmountsMath.wrapDecimals(used, _baseTokenDecimals);
    //     total = AmountsMath.wrapDecimals(total, _baseTokenDecimals);

    //     return used.wdiv(total);
    // }

    // TBD: make an updateMarketOracle instead of a getter
    function _getMarketOracle() internal view returns (address) {
        address marketOracle = _addressProvider.marketOracle();

        if (marketOracle == address(0)) {
            revert MissingMarketOracle();
        }

        return marketOracle;
    }

    // TBD: make an updatePriceOracle instead of a getter
    function _getPriceOracle() internal view returns (address) {
        address priceOracle = _addressProvider.priceOracle();

        if (priceOracle == address(0)) {
            revert MissingPriceOracle();
        }

        return priceOracle;
    }

    // must be defined in Wad
    function setTradeVolatilityUtilizationRateFactor(uint256 utilizationRateFactor) external onlyOwner {
        // ToDo: make the change effective from the next epoch
        _tradeVolatilityUtilizationRateFactor = utilizationRateFactor;
    }

    // must be defined in Wad
    function setTradeVolatilityTimeDecay(uint256 timeDecay) external onlyOwner {
        // ToDo: make the change effective from the next epoch
        _tradeVolatilityTimeDecay = timeDecay;
    }
}
