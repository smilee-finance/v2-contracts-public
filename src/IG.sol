// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {DVPType} from "./lib/DVPType.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Position} from "./lib/Position.sol";
import {DVP} from "./DVP.sol";

contract IG is DVP {
    /// @notice Common strike price for all impermanent gain positions in this DVP, set at epoch start
    uint256 public currentStrike;

    constructor(address vault_) DVP(vault_, DVPType.IG) {}

    /// @inheritdoc IDVP
    function mint(
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) external override returns (uint256 leverage) {
        strike;
        leverage = _mint(recipient, currentStrike, strategy, amount);
    }

    /// @inheritdoc IDVP
    function burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) external override returns (uint256 paidPayoff) {
        paidPayoff = _burn(epoch, recipient, strike, strategy, amount);
    }

    /// @inheritdoc IDVP
    function premium(uint256 strike, bool strategy, uint256 amount) public view override virtual returns (uint256) {
        strike;
        strategy;
        // ToDo: compute price and premium
        return amount / 10; // 10%
    }

    function payoff(uint256 epoch, uint256 strike, bool strategy) public view override virtual returns (uint256) {
        Position.Info memory position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));
        //ToDo: Compute Payoff
        return position.amount / 10;
    }

}
