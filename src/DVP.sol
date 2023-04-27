// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP, IDVPImmutables} from "./interfaces/IDVP.sol";
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
    uint256 public immutable override optionSize;

    /// @inheritdoc IDVP
    address public override liquidityProvider;

    mapping(uint256 => mapping(bytes32 => Position.Info)) public epochPositions;

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 frequency_,
        uint256 optionSize_
    ) EpochControls(frequency_) {
        DVPLogic.valid(DVPLogic.DVPCreateParams(baseToken_, sideToken_));
        factory = msg.sender;
        baseToken = baseToken_;
        sideToken = sideToken_;
        optionSize = optionSize_;
    }

    /// @inheritdoc IDVP
    function positions(
        bytes32 positionID
    ) public view override returns (uint256 amount, uint256 strategy, uint256 strike, uint256 epoch) {
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
        uint256 strategy,
        uint256 amount
    ) internal epochActive returns (uint256 leverage) {
        if (amount == 0) {
            revert AmountZero();
        }
        if (!OptionStrategy.isValid(strategy)) {
            revert InvalidStrategy();
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
        uint256 strategy,
        uint256 amount
    ) internal epochActive returns (uint256 payoff) {
        if (amount == 0) {
            revert AmountZero();
        }
        if (!OptionStrategy.isValid(strategy)) {
            revert InvalidStrategy();
        }

        // TBD: check liquidity availability on liquidity provider
        // TBD: trigger liquidity rebalance on liquidity provider

        Position.Info storage position = _getPosition(epoch, Position.getID(recipient, strategy, strike));

        position.updateAmount(-int256(amount));

        payoff = 0;
        emit Burn(msg.sender);
    }

    function _getPosition(uint256 epochID, bytes32 positionID) internal view returns (Position.Info storage) {
        return epochPositions[epochID][positionID];
    }
}
