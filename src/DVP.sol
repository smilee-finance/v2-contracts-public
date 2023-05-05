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

    mapping(uint256 => mapping(bytes32 => Position.Info)) public epochPositions;

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

    /// @notice The total premium currently paid to the DVP
    /// @return The amount of base tokens deposited in the DVP
    function balance() public view returns (uint256) {
        return IERC20(baseToken).balanceOf(address(this));
    }

    function _mint(
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) internal epochActive returns (uint256 leverage) {
        if (amount == 0) {
            revert AmountZero();
        }

        // TBD: check liquidity availability on liquidity provider
        // TBD: trigger liquidity rebalance on liquidity provider

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
    ) internal epochActive returns (uint256 paidPayoff) {
        if (amount == 0) {
            revert AmountZero();
        }
        // TBD: check liquidity availability on liquidity provider
        // TBD: trigger liquidity rebalance on liquidity provider

        Position.Info storage position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));
        position.updateAmount(-int256(amount));

        paidPayoff = _computePayoff(position);
        // ToDo: handle payoff
        recipient;

        emit Burn(msg.sender);
    }

    function _getPosition(uint256 epochID, bytes32 positionID) internal view returns (Position.Info storage) {
        return epochPositions[epochID][positionID];
    }

    /// @inheritdoc EpochControls
    function rollEpoch() public override(EpochControls, IEpochControls) {
        // TBD: review
        if (vault != address(0)) {
            IEpochControls(vault).rollEpoch();
        }
        super.rollEpoch();
    }

    /// @inheritdoc IDVP
    function payoff(uint256 epoch, bool strategy, uint256 strike) public view override returns (uint256) {
        Position.Info storage position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));
        return _computePayoff(position);
    }

    function _computePayoff(Position.Info memory position) internal view virtual returns (uint256) {
        /// @dev: placeholder to be filled by the concrete DVPs.
        position;
        return 0;
    }
}
