// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP, IDVPImmutables} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IVault} from "./interfaces/IVault.sol";
import {DVPLogic} from "./lib/DVPLogic.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {Position} from "./lib/Position.sol";
import {EpochControls} from "./EpochControls.sol";

abstract contract DVP is IDVP, EpochControls {
    using Position for Position.Info;
    using OptionStrategy for uint256;

    // NOTE: used come residuo da ritirare post fine epoca ?
    struct Liquidity {
        uint256 initial;
        uint256 used;
    }

    /// @inheritdoc IDVPImmutables
    address public immutable override factory;
    /// @inheritdoc IDVPImmutables
    address public immutable override baseToken;
    /// @inheritdoc IDVPImmutables
    address public immutable override sideToken;
    /// @inheritdoc IDVPImmutables
    bool public immutable override optionType;

    /// @inheritdoc IDVP
    address public override vault;
    // ToDo: index by epoch and add payoff (mapping of struct)
    /// @notice Liquidity of the current epoch
    Liquidity internal _liquidity;

    mapping(uint256 => mapping(bytes32 => Position.Info)) public epochPositions;

    // error NotEnoughLiquidity();

    // ToDo: retrieve tokens from vault
    constructor(
        address baseToken_,
        address sideToken_,
        address vault_,
        bool optionType_
    ) EpochControls(IEpochControls(vault_).epochFrequency()) {
        DVPLogic.valid(DVPLogic.DVPCreateParams(baseToken_, sideToken_));
        factory = msg.sender;
        baseToken = baseToken_;
        sideToken = sideToken_;
        optionType = optionType_;
        vault = vault_;
    }

    /// @inheritdoc IDVP
    function positions(
        bytes32 positionID
    ) public view override returns (uint256 amount, bool strategy, uint256 strike, uint256 epoch) {
        Position.Info storage position = _getPosition(currentEpoch, positionID);

        return (position.amount, position.strategy, position.strike, position.epoch);
    }

    // /// @notice The total premium currently paid to the DVP
    // /// @return The amount of base tokens deposited in the DVP
    // function balance() public view returns (uint256) {
    //     return IERC20(baseToken).balanceOf(address(this));
    // }

    // ToDo: replace amount with notional instead of premium
    function _mint(
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) internal epochActive epochNotFrozen(currentEpoch) returns (uint256 leverage) {
        if (amount == 0) {
            revert AmountZero();
        }

        // TBD: check liquidity availability on liquidity provider
        // TBD: trigger liquidity rebalance on liquidity provider
        // TBD: perhaps the DVP needs to know how much premium was paid (in a given epoch ?)...

        // ToDo: compute premium
        uint256 premium = 1;
        // Transfer premium:
        IERC20(baseToken).transferFrom(msg.sender, vault, premium);

        // ToDo: delta hedge
        // hedge_notional := initial - (amount + used)
        // ∆hedge := hedge_notional * ig_delta(...)
        // vault._____(∆hedge)

        // Check available liquidity:
        // if (_liquidity.initial - _liquidity.used < amount) {
        //     revert NotEnoughLiquidity();
        // }
        // TBD: let the vault know that it's locked
        _liquidity.used += amount;

        Position.Info storage position = _getPosition(currentEpoch, Position.getID(recipient, strategy, strike));

        // Initialize position:
        position.epoch = currentEpoch;
        position.strike = strike;
        position.strategy = strategy;
        position.updateAmount(int256(amount));

        leverage = 1;
        emit Mint(msg.sender, recipient);
    }

    function _burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) internal epochActive epochNotFrozen(currentEpoch) returns (uint256 paidPayoff) {
        if (amount == 0) {
            revert AmountZero();
        }
        // TBD: check liquidity availability on liquidity provider
        // TBD: trigger liquidity rebalance on liquidity provider

        Position.Info storage position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));
        position.updateAmount(-int256(amount));

        _liquidity.used -= amount;

        // ToDo: delta hedge
        paidPayoff = _computePayoff(position);
        IVault(vault).provideLiquidity(recipient, paidPayoff);

        emit Burn(msg.sender);
    }

    function _getPosition(uint256 epochID, bytes32 positionID) internal view returns (Position.Info storage) {
        return epochPositions[epochID][positionID];
    }

    /// @inheritdoc EpochControls
    function rollEpoch() public override(EpochControls, IEpochControls) {
        // NOTE: it implicitly verifies that the epoch can be rolled

        // ToDo: compute payoff and set it into the vault for its roll epoch computations
        // ----- Payoff := initial locked liquidity * utilization rate [0,1] * dvp payoff percentage (from formulas)
        // TBD: track amount of liquidity put aside for the DVP payoff of each epoch ?

        IEpochControls(vault).rollEpoch();
        // ToDo: check if vault is dead and react to it

        _liquidity.initial = IVault(vault).getLockedValue();
        // _liquidity.initial = 1000; // TMP

        super.rollEpoch();
    }

    /// @inheritdoc IDVP
    function payoff(uint256 epoch, uint256 strike, bool strategy) public view override returns (uint256) {
        Position.Info storage position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));
        return _computePayoff(position);
    }

    function _computePayoff(Position.Info memory position) internal view virtual returns (uint256) {
        /// @dev: placeholder to be filled by the concrete DVPs.
        position;
        return 0;
    }
}
