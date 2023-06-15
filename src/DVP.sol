// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP, IDVPImmutables} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Notional} from "./lib/Notional.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {Position} from "./lib/Position.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {EpochControls} from "./EpochControls.sol";

abstract contract DVP is IDVP, EpochControls {
    using Position for Position.Info;
    using Notional for Notional.Info;

    /// @inheritdoc IDVPImmutables
    address public immutable override baseToken;
    /// @inheritdoc IDVPImmutables
    address public immutable override sideToken;
    /// @inheritdoc IDVPImmutables
    bool public immutable override optionType; // ToDo: review (it's a DVPType)
    /// @inheritdoc IDVP
    address public immutable override vault;
    AddressProvider internal immutable _addressProvider;

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

    error NotEnoughLiquidity();
    error PositionNotFound();
    error CantBurnMoreThanMinted();

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
    }

    /**
        @notice Mint or increase a position.
        @param recipient The wallet of the recipient for the opened position.
        @param strike The strike.
        @param strategy The OptionStrategy strategy (i.e. Call or Put).
        @param amount The notional.
        @return premium_ The paid premium.
        @dev The client must have approved the needed premium.
     */
    function _mint(
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) internal epochInitialized epochNotFrozen returns (uint256 premium_) {
        if (amount == 0) {
            revert AmountZero();
        }

        Notional.Info storage liquidity = _liquidity[currentEpoch];

        // Check available liquidity:
        if (liquidity.available(strike, strategy) < amount) {
            revert NotEnoughLiquidity();
        }

        // Get premium from sender:
        premium_ = premium(strike, strategy, amount);
        IERC20(baseToken).transferFrom(msg.sender, vault, premium_);

        // Decrease available liquidity:
        liquidity.increaseUsage(strike, strategy, amount);

        // TBD: add comments
        _deltaHedgePosition(strike, strategy, int256(amount));

        // Create or update position:
        Position.Info storage position = _getPosition(currentEpoch, recipient, strategy, strike);
        position.epoch = currentEpoch;
        position.strike = strike;
        position.strategy = strategy;
        position.amount += amount;

        emit Mint(msg.sender, recipient);
    }

    /**
        @notice It attempts to flat the DVP's delta by selling/buying an amount of side tokens in order to hedge the position.
        @notice By hedging the position, we avoid the impermanent loss.
        @param strike The position strike.
        @param strategy The position strategy.
        @param notional The position notional; positive if buyed by a user, negative otherwise.
     */
    function _deltaHedgePosition(uint256 strike, bool strategy, int256 notional) internal virtual {
        // ToDo: delta hedge
        // uint256 totalNotional = _liquidity.initial - (notional + _liquidity.used);
        // sideTokensAmount := totalNotional * ig_delta(...)
        // IVault(vault).deltaHedge(sideTokensAmount);
    }

    /**
        @notice Burn or decrease a position.
        @param epoch The epoch of the position.
        @param recipient The wallet of the recipient for the opened position.
        @param strike The strike
        @param strategy The OptionStrategy strategy (i.e. Call or Put).
        @param amount The notional.
        @return paidPayoff The paid payoff.
     */
    function _burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) internal epochInitialized epochNotFrozen returns (uint256 paidPayoff) {
        Position.Info storage position = _getPosition(epoch, msg.sender, strategy, strike);
        if (!position.exists()) {
            revert PositionNotFound();
        }

        // // If the position reached maturity, the user must close the entire position
        // // NOTE: we have to avoid this due to the PositionManager that holds positions for multiple tokens.
        // if (position.epoch != currentEpoch) {
        //     amount = position.amount;
        // }
        if (amount == 0) {
            // NOTE: a zero amount may have some parasite effect, henct we proactively protect against it.
            // ToDo: review
            revert AmountZero();
        }
        if (amount > position.amount) {
            revert CantBurnMoreThanMinted();
        }

        bool pastEpoch = true;
        if (position.epoch == currentEpoch) {
            pastEpoch = false;
            // TBD: add comments
            _deltaHedgePosition(strike, strategy, -int256(amount));
        }

        // Compute the payoff to be paid:
        // NOTE: must be computed here, before the next account of used liquidity.
        paidPayoff = payoff(position.epoch, position.strike, position.strategy, amount);

        // Account change of used liquidity between wallet and protocol:
        position.amount -= amount;
        Notional.Info storage liquidity = _liquidity[position.epoch];
        liquidity.decreaseUsage(position.strike, position.strategy, amount);

        if (pastEpoch) {
            // Account transfer of setted aside payoff:
            liquidity.decreasePayoff(position.strike, position.strategy, paidPayoff);
        }

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

        uint256 payoff_ = _computeResidualPayoff(strike, strategy);
        liquidity.accountPayoff(strike, strategy, payoff_);
    }

    /**
        @notice computes the payoff to be set aside at the end of the epoch for the provided strike and strategy.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return payoff_ the residual payoff.
     */
    function _computeResidualPayoff(uint256 strike, bool strategy) internal view returns (uint256 payoff_) {
        Notional.Info storage liquidity = _liquidity[currentEpoch];
        uint256 residualAmount = liquidity.getUsed(strike, strategy);
        payoff_ = _computePayoff(strike, strategy, residualAmount);
    }

    /**
        @notice Returns the accounted payoff of the positions in circulation that is still to be redeemed.
        @return residualPayoff the overall payoff to be set aside for the closing epoch.
        @dev The concrete DVP must iterate on the various strikes and strategies.
     */
    function _residualPayoff() internal view virtual returns (uint256 residualPayoff);

    /**
        @notice Compute the payoff of a position within the current epoch.
        @param strike the position strike.
        @param strategy the position strategy.
        @param amount the position notional.
        @return payoff_ The payoff value.
        @dev It's also used for the DVP's overall position at maturity.
     */
    function _computePayoff(uint256 strike, bool strategy, uint256 amount) internal view returns (uint256 payoff_) {
        uint256 percentage = _payoffPerc(strike, strategy);
        payoff_ = (amount * percentage) / 1e18;
    }

    /**
        @notice computes the payoff percentage (a scale factor) for the given strike and strategy.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return percentage the payoff percentage.
     */
    function _payoffPerc(uint256 strike, bool strategy) internal view virtual returns (uint256 percentage);

    /// @inheritdoc IDVP
    function premium(uint256 strike, bool strategy, uint256 amount) public view virtual returns (uint256);

    /// @inheritdoc IDVP
    function payoff(
        uint256 epoch,
        uint256 strike,
        bool strategy,
        uint256 positionAmount
    ) public view virtual returns (uint256 payoff_) {
        Position.Info storage position = _getPosition(epoch, msg.sender, strategy, strike);
        if (!position.exists()) {
            // TBD: return 0
            revert PositionNotFound();
        }

        if (position.epoch == currentEpoch) {
            // The user wants to know how much it can receive from selling the position before its maturity:
            payoff_ = _computePayoff(strike, strategy, positionAmount);
        } else {
            // // The position reached maturity, hence the user must close the entire position:
            // // NOTE: we have to avoid this due to the PositionManager that holds positions for multiple tokens.
            // positionAmount = position.amount;
            // The position is eligible for a share of the <epoch, strike, strategy> payoff set aside at epoch end:
            payoff_ = _liquidity[position.epoch].shareOfPayoff(position.strike, position.strategy, positionAmount);
        }
    }

    /**
        @notice Lookups the requested position.
        @param epoch The epoch of the position.
        @param owner The owner of the position.
        @param strategy The strategy of the position.
        @param strike The strike of the position.
        @return position_ The requested position.
        @dev The client should check if the position exists by calling `exists()` on it.
     */
    function _getPosition(uint256 epoch, address owner, bool strategy, uint256 strike) internal view returns (Position.Info storage position_) {
        bytes32 positionID = Position.getID(owner, strategy, strike);
        return _epochPositions[epoch][positionID];
    }
}
