// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP, IDVPImmutables} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IVault} from "./interfaces/IVault.sol";
import {DVPLogic} from "./lib/DVPLogic.sol";
import {Notional} from "./lib/Notional.sol";
import {Position} from "./lib/Position.sol";
import {EpochControls} from "./EpochControls.sol";

abstract contract DVP is IDVP, EpochControls {
    using Position for Position.Info;
    using Notional for Notional.Info;

    /// @inheritdoc IDVPImmutables
    address public immutable override baseToken;
    // @inheritdoc IDVPImmutables
    address public immutable override sideToken;
    /// @inheritdoc IDVPImmutables
    bool public immutable override optionType;
    /// @inheritdoc IDVP
    address public override vault;

    // ToDo: add payoff (mapping of struct)
    /// @notice Available liquidity for options indexed by epoch
    mapping(uint256 => Notional.Info) internal _liquidity;

    mapping(uint256 => mapping(bytes32 => Position.Info)) public epochPositions;

    error NotEnoughLiquidity();

    constructor(address vault_, bool optionType_) EpochControls(IEpochControls(vault_).epochFrequency()) {
        optionType = optionType_;
        vault = vault_;
        IVault vaultCt = IVault(vault);
        baseToken = vaultCt.baseToken();
        sideToken = vaultCt.sideToken();
        DVPLogic.valid(DVPLogic.DVPCreateParams(sideToken, baseToken));
    }

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
    ) internal epochActive epochNotFrozen(currentEpoch) returns (uint256 premium_) {
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
        position.updateAmount(int256(amount));

        emit Mint(msg.sender, recipient);
    }

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
    ) internal epochActive epochNotFrozen(currentEpoch) returns (uint256 paidPayoff) {
        // TBD: check liquidity availability on liquidity provider
        // TBD: trigger liquidity rebalance on liquidity provider

        Position.Info storage position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));

        // Option matured, the user have to close the entire position
        if (position.epoch != currentEpoch) {
            amount = position.amount;
        }

        if (amount == 0) {
            revert AmountZero();
        }

        position.updateAmount(-int256(amount));

        _liquidity[epoch].decreaseUsage(strike, strategy, amount);

        if (position.epoch == currentEpoch) {
            _deltaHedge(strike, strategy, amount);
        }
        paidPayoff = _payPayoff(position, recipient, amount);

        emit Burn(msg.sender);
    }

    /// @inheritdoc EpochControls
    function rollEpoch() public override(EpochControls, IEpochControls) {
        // NOTE: it implicitly verifies that the epoch can be rolled

        // ToDo: compute payoff and set it into the vault for its roll epoch computations
        // ----- Payoff := initial locked liquidity * utilization rate [0,1] * dvp payoff percentage (from formulas)
        // TBD: track amount of liquidity put aside for the DVP payoff of each epoch ?
        uint256 residualPayoff = _residualPayoff();
        /* TODO - IVault(vault.reservePayoff(residualPayoff)); */

        // ToDo: check if vault is dead and react to it

        IEpochControls(vault).rollEpoch();
        super.rollEpoch();

        _initLiquidity();
    }

    // TODO
    function _initLiquidity() internal virtual;

    function _residualPayoff() internal virtual returns (uint256);

    /// @inheritdoc IDVP
    function premium(uint256 strike, bool strategy, uint256 amount) public view virtual returns (uint256);

    /// @inheritdoc IDVP
    // TBD : What if user wants to burn a portion of position (of course if the burn will be done in the same epoch)?
    function payoff(uint256 epoch, uint256 strike, bool strategy, uint256 amount) public view virtual returns (uint256);

    function _payPayoff(
        Position.Info memory position,
        address recipient,
        uint256 amount
    ) internal virtual returns (uint256 payoff_) {
        payoff_ = payoff(position.epoch, position.strike, position.strategy, amount);
        IVault(vault).provideLiquidity(recipient, payoff_);
    }

    function _getPosition(uint256 epochID, bytes32 positionID) internal view returns (Position.Info storage) {
        return epochPositions[epochID][positionID];
    }
}
