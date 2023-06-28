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
        // ToDo: compute
        return amount / 10; // 10%
    }

    /// @inheritdoc DVP
    function _payoffPerc(uint256 strike, bool strategy) internal view virtual override returns (uint256) {
        strike;
        strategy;
        // ToDo: compute
        // igPayoffPerc(currentStrike, oracle.getPrice(...))
        return 1e17;
    }

    /// @inheritdoc DVP
    function _residualPayoff() internal view virtual override returns (uint256 residualPayoff) {
        Notional.Info storage liquidity = _liquidity[currentEpoch];

        uint256 pCall = liquidity.getAccountedPayoff(currentStrike, OptionStrategy.CALL);
        uint256 pPut = liquidity.getAccountedPayoff(currentStrike, OptionStrategy.PUT);

        residualPayoff = pCall + pPut;
    }

    /// @inheritdoc DVP
    function _accountResidualPayoffs() internal virtual override {
        _accountResidualPayoff(currentStrike, OptionStrategy.CALL);
        _accountResidualPayoff(currentStrike, OptionStrategy.PUT);
    }

    function _afterRollEpoch() internal virtual override {
        if (_lastRolledEpoch() != 0) {
            // Update strike price:
            // NOTE: both amounts are after equal weight rebalance, hence we can just compute their ratio.
            (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
            // ToDo: fix decimals
            // ToDo: check division by zero
            // ----- TBD: check if vault is dead
            currentStrike = sideTokenAmount / baseTokenAmount;
        }

        super._afterRollEpoch();
    }

    /// @inheritdoc DVP
    function _allocateLiquidity(uint256 initialCapital) internal virtual override {
        Notional.Info storage liquidity = _liquidity[currentEpoch];

        // The impermanent gain DVP only has one strike:
        liquidity.setup(currentStrike);

        // The initialCapital is split 50:50 on the two strategies:
        uint256 halfInitialCapital = initialCapital / 2;
        liquidity.setInitial(currentStrike, OptionStrategy.CALL, halfInitialCapital);
        liquidity.setInitial(currentStrike, OptionStrategy.PUT, initialCapital - halfInitialCapital);
    }

}
