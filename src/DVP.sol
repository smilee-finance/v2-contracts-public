// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP, IDVPImmutables} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IVault} from "./interfaces/IVault.sol";
import {DVPLogic} from "./lib/DVPLogic.sol";
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
    bool public immutable override optionType; // ToDo: review (it's a DVPType) (also see IDVPImmutables)
    /// @inheritdoc IDVP
    address public immutable override vault;
    AddressProvider internal immutable _addressProvider;

    // TBD: extract payoff from Notional.Info
    // TBD: move strike and strategy outside of struct as indexes
    /// @notice liquidity for options indexed by epoch
    mapping(uint256 => Notional.Info) internal _liquidity;

    mapping(uint256 => mapping(bytes32 => Position.Info)) public epochPositions;

    error NotEnoughLiquidity();
    error PositionNotFound();
    error CantBurnMoreThanMinted();

    constructor(address vault_, bool optionType_, address addressProvider_) EpochControls(IEpochControls(vault_).epochFrequency()) {
        optionType = optionType_;
        vault = vault_;
        IVault vaultCt = IVault(vault);
        baseToken = vaultCt.baseToken();
        sideToken = vaultCt.sideToken();
        _addressProvider = AddressProvider(addressProvider_);
        // ToDo: review
        DVPLogic.valid(DVPLogic.DVPCreateParams(sideToken, baseToken));
    }

    // ToDo: review usage
    /// @inheritdoc IDVP
    function positions(
        bytes32 positionID
    ) public view override returns (uint256 amount, bool strategy, uint256 strike, uint256 epoch) {
        Position.Info storage position = _getPosition(currentEpoch, positionID);

        return (position.amount, position.strategy, position.strike, position.epoch);
    }

    function _mint(
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) internal epochInitialized epochNotFrozen returns (uint256 premium_) {
        if (amount == 0) {
            revert AmountZero();
        }

        // Check available liquidity
        if (_liquidity[currentEpoch].available(strike, strategy) < amount) {
            revert NotEnoughLiquidity();
        }

        _liquidity[currentEpoch].increaseUsage(strike, strategy, amount);

        // Get premium from sender
        premium_ = premium(strike, strategy, amount);
        IERC20(baseToken).transferFrom(msg.sender, vault, premium_);

        _deltaHedge(strike, strategy, amount);

        Position.Info storage position = _getPosition(currentEpoch, Position.getID(recipient, strategy, strike));

        // Initialize position:
        position.epoch = currentEpoch;
        position.strike = strike;
        position.strategy = strategy;
        position.amount += amount;

        emit Mint(msg.sender, recipient);
    }

    // ToDo: review as it seems strange that there's no direction (mint/burn)
    function _deltaHedge(uint256 strike, bool strategy, uint256 amount) internal virtual {
        // ToDo: delta hedge
        // uint256 notional = _liquidity.initial - (amount + _liquidity.used);
        // sideTokensAmount := notional * ig_delta(...)
        // IVault(vault).deltaHedge(sideTokensAmount);
    }

    function _burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) internal epochInitialized epochNotFrozen returns (uint256 paidPayoff) {
        Position.Info storage position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));
        if (!position.exists()) {
            revert PositionNotFound();
        }
        // Option reached maturity, hence the user have to close the entire position
        if (position.epoch != currentEpoch) {
            amount = position.amount;
        } else {
            if (amount > position.amount) {
                revert CantBurnMoreThanMinted();
            }
        }
        if (amount == 0) {
            revert AmountZero();
        }

        if (position.epoch == currentEpoch) {
            _deltaHedge(strike, strategy, amount);
        }

        paidPayoff = payoff(position.epoch, position.strike, position.strategy, amount);

        position.amount -= amount;
        bool pastEpoch = _isEpochFinished(position.epoch);

        _liquidity[position.epoch].decreaseUsage(position.strike, position.strategy, amount);
        if (pastEpoch) {
            _liquidity[position.epoch].decreasePayoff(position.strike, position.strategy, paidPayoff);
        }

        IVault(vault).transferPayoff(recipient, paidPayoff, pastEpoch);

        emit Burn(msg.sender);
    }

    /// @inheritdoc EpochControls
    function _beforeRollEpoch() internal virtual override {
        if (_isEpochInitialized()) {
            uint256 residualPayoff = _residualPayoff();
            IVault(vault).reservePayoff(residualPayoff);
        }

        IEpochControls(vault).rollEpoch();
        // ToDo: check if vault is dead and react to it
    }

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        uint256 notional = IVault(vault).v0();
        _allocateLiquidity(notional);
    }

    /**
        @notice Setup initial notional for a new epoch.
        @dev The concrete DVP must allocate the initial notional on the various strikes and strategies.
     */
    function _allocateLiquidity(uint256 notional) internal virtual;

    // ToDo: split in two functions
    /**
        @notice computes and stores the payoffs for the closing epoch.
        @return residualPayoff the overall payoff to be set aside for the closing epoch.
        @dev The concrete DVP must compute and account the payoff for the various strikes and strategies.
     */
    function _residualPayoff() internal virtual returns (uint256 residualPayoff);

    /**
        @notice computes the payoff to be put aside at the end of the epoch for the provided strike and strategy.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return payoff_ the residual payoff.
     */
    function _computeResidualPayoff(uint256 strike, bool strategy) internal view returns (uint256 payoff_)  {
        uint256 residualAmount = _liquidity[currentEpoch].getOptioned(strike, strategy);
        payoff_ = _computePayoff(strike, strategy, residualAmount);
    }

    function _computePayoff(uint256 strike, bool strategy, uint256 amount) internal view returns (uint256 payoff_) {
        uint256 percentage = _payoffPerc(strike, strategy);
        payoff_ = (amount * percentage) / 1e18;
    }

    /// @inheritdoc IDVP
    function premium(uint256 strike, bool strategy, uint256 amount) public view virtual returns (uint256);

    /**
        @notice computes the payoff percentage for the given strike and strategy
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return percentage the payoff percentage.
     */
    function _payoffPerc(uint256 strike, bool strategy) internal view virtual returns (uint256 percentage);

    /// @inheritdoc IDVP
    function payoff(
        uint256 epoch,
        uint256 strike,
        bool strategy,
        uint256 positionAmount
    ) public view virtual returns (uint256 payoff_) {
        Position.Info storage position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));
        if (!position.exists()) {
            // TBD: return 0
            revert PositionNotFound();
        }

        if (_isEpochFinished(position.epoch)) {
            // The position is eligible for a share of the <epoch, strike, strategy> payoff put aside at epoch end
            payoff_ = _liquidity[position.epoch].shareOfPayoff(position.strike, position.strategy, positionAmount);
        } else {
            payoff_ = _computePayoff(strike, strategy, positionAmount);
        }
    }

    // TBD: compute the positionID within the function
    function _getPosition(uint256 epochID, bytes32 positionID) internal view returns (Position.Info storage) {
        return epochPositions[epochID][positionID];
    }
}
