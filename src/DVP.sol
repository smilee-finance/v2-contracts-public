// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EpochControls} from "./EpochControls.sol";
import {IDVP, IDVPImmutables} from "./interfaces/IDVP.sol";
import {Position} from "./lib/Position.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {DVPLogic} from "./lib/DVPLogic.sol";

abstract contract DVP is IDVP, EpochControls {
    using Position for mapping(bytes32 => Position.Info); // can get position from identifying params
    using Position for Position.Info; // can update single position
    using OptionStrategy for uint256;

    /// @inheritdoc IDVPImmutables
    address public immutable override factory;
    /// @inheritdoc IDVPImmutables
    address public immutable override baseToken;
    /// @inheritdoc IDVPImmutables
    address public immutable override sideToken;
    /// @inheritdoc IDVPImmutables
    uint256 public immutable override optionSize;

    constructor(
        address _baseToken,
        address _sideToken,
        uint256 _frequency,
        uint256 _optionSize
    ) EpochControls(_frequency) {
        DVPLogic.valid(DVPLogic.DVPCreateParams(_baseToken, _sideToken));
        factory = msg.sender;
        baseToken = _baseToken;
        sideToken = _sideToken;
        optionSize = _optionSize;
    }

    /// @inheritdoc IDVP
    function positions(
        bytes32 id
    ) public view override returns (uint256 amount, uint256 strategy, uint256 entryPrice, uint256 epoch) {
        return (
            epochPositions[currentEpoch][id].amount,
            epochPositions[currentEpoch][id].strategy,
            epochPositions[currentEpoch][id].entryPrice,
            epochPositions[currentEpoch][id].epoch
        );
    }

    /// @inheritdoc IDVP
    address public override liquidityProvider;

    mapping(uint256 => mapping(bytes32 => Position.Info)) public epochPositions;

    /// @notice The total premium currently paid to the DVP
    /// @return The amount of base tokens deposited in the DVP
    function balance() public view returns (uint256) {
        (bool success, bytes memory data) = baseToken.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    struct UpdatePositionParams {
        address owner; // the address that owns the position
        uint256 strategy; // the option payoff type
        int256 amount; // the number of options to be created
    }

    /// @inheritdoc IDVP
    function mint(address recipient, uint256 strategy, uint256 amount) external override epochActive {
        require(amount > 0);
        require(strategy.isValid());

        (uint256 amountBase, uint256 amountSide) = _updatePosition(
            UpdatePositionParams({owner: recipient, strategy: strategy, amount: int256(amount)})
        );

        amountBase;
        amountSide;
        emit Mint(msg.sender, recipient);
    }

    /// @inheritdoc IDVP
    function burn(address recipient, uint256 strategy, uint256 amount) external override epochActive {
        require(amount > 0);
        require(strategy.isValid());

        (uint256 amountBase, uint256 amountSide) = _updatePosition(
            UpdatePositionParams({owner: recipient, strategy: strategy, amount: -int256(amount)})
        );

        amountBase;
        amountSide;
        emit Burn(msg.sender);
    }

    function _updatePosition(
        UpdatePositionParams memory params
    ) private returns (uint256 amountBase, uint256 amountSide) {
        // check liquidity availability on liquidity provider

        // trigger liquidity rebalance on liquidity provider

        // get entry price of the position
        uint256 entryPrice = 0; // LiquidityPool.mint(option);

        Position.Info storage position = epochPositions[currentEpoch].get(params.owner, params.strategy, entryPrice);

        // update or create position
        position.update(params.amount);

        return (0, 0);
    }
}
