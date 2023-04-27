// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVP} from "./interfaces/IDVP.sol";
import {DVP} from "./DVP.sol";

contract IG is DVP {

    /// @notice Common strike price for all impermanent gain positions in this DVP, set at epoch start
    uint256 public currentStrike;

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 frequency_,
        uint256 optionSize_
    ) DVP(baseToken_, sideToken_, frequency_, optionSize_) {}

    /// @inheritdoc IDVP
    function premium(uint256 strike, uint256 strategy, uint256 amount) public view override returns (uint256) {
        strike;
        strategy;
        amount;
        return 0.1 ether;
    }

    /// @inheritdoc IDVP
    function payoff(bytes32 key) public pure override returns (uint256) {
        key;
        return 0.1 ether;
    }

    /// @inheritdoc IDVP
    function mint(address recipient, uint256 strike, uint256 strategy, uint256 amount) external override {
        strike;
        _mint(recipient, currentStrike, strategy, amount);
    }

    /// @inheritdoc IDVP
    function burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        uint256 strategy,
        uint256 amount
    ) external override {
        _burn(epoch, recipient, strike, strategy, amount);
    }
}
