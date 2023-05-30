// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVP} from "./interfaces/IDVP.sol";
import {IVault} from "./interfaces/IVault.sol";
import {DVPType} from "./lib/DVPType.sol";
import {Notional} from "./lib/Notional.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {DVP} from "./DVP.sol";

contract IG is DVP {
    using Notional for Notional.Info;

    /// @notice Common strike price for all impermanent gain positions in this DVP, set at epoch start
    uint256 public currentStrike;

    constructor(address vault_, address addressProvider_) DVP(vault_, DVPType.IG, addressProvider_) {}

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
    function premium(uint256 strike, bool strategy, uint256 amount) public view virtual override returns (uint256) {
        strike;
        strategy;
        // ToDo: compute premium
        return amount / 10; // 10%
    }

    /// @inheritdoc DVP
    function _payoffPerc(uint256 strike, bool strategy) internal view virtual override returns (uint256) {
        strike;
        strategy;
        // igPayoffPerc(currentStrike, oracle.getPrice(...))
        return 1e17;
    }

    /// @inheritdoc DVP
    function _allocateLiquidity(uint256 notional) internal virtual override {
        _liquidity[currentEpoch].setup(currentStrike);

        uint256 halfNotional = notional / 2;
        _liquidity[currentEpoch].setInitial(currentStrike, OptionStrategy.CALL, halfNotional);
        _liquidity[currentEpoch].setInitial(currentStrike, OptionStrategy.PUT, notional - halfNotional);
    }

    /// @inheritdoc DVP
    function _residualPayoff() internal virtual override returns (uint256 residualPayoff) {
        uint256 pCall = _computeResidualPayoff(currentStrike, OptionStrategy.CALL);
        _liquidity[currentEpoch].accountPayoff(currentStrike, OptionStrategy.CALL, pCall);

        uint256 pPut = _computeResidualPayoff(currentStrike, OptionStrategy.PUT);
        _liquidity[currentEpoch].accountPayoff(currentStrike, OptionStrategy.PUT, pPut);

        residualPayoff = pCall + pPut;
    }

    function _afterRollEpoch() internal virtual override {
        // ToDo: set the current strike
        super._afterRollEpoch();
    }

}
