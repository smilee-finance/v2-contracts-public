// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AmountsMath} from "./AmountsMath.sol";

/**
    @title Simple lib to ease DVP liquidity access and modification
 */
library Notional {
    using AmountsMath for uint256;

    struct Info {
        // initial value of the notional (at epoch begin) by strike
        mapping(uint256 => uint256[]) initial;
        // mapping strike => available liquidity per strategy
        mapping(uint256 => uint256[]) optioned;
        mapping(uint256 => uint256[]) payoff;
    }

    function _strategyIdx(bool strategy) private pure returns (uint256) {
        return strategy ? 1 : 0;
    }

    /**
        @notice Prepare the Notional.Info struct for the new epoch for the two strategies of the provided strike.
        @param self the Notional.Info struct for the new epoch.
        @param strike the reference strike.
        @dev must be called before any usage of the struct for each needed strike
     */
    function setup(Info storage self, uint256 strike) public {
        self.initial[strike] = new uint256[](2);
        self.optioned[strike] = new uint256[](2);
        self.payoff[strike] = new uint256[](2);
    }

    function setInitial(Info storage self, uint256 strike, bool strategy, uint256 notional) public {
        self.initial[strike][_strategyIdx(strategy)] = notional;
    }

    /**
        @notice
     */
    function available(Info storage self, uint256 strike, bool strategy) public view returns (uint256 avail) {
        return self.initial[strike][_strategyIdx(strategy)] - self.optioned[strike][_strategyIdx(strategy)];
    }

    /**
        @notice
        @dev Assume overflow checks done externally
     */
    function increaseUsage(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.optioned[strike][_strategyIdx(strategy)] += amount;
    }

    /**
        @notice
        @dev Assume overflow checks done externally
     */
    function decreaseUsage(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.optioned[strike][_strategyIdx(strategy)] -= amount;
    }

    function getOptioned(Info storage self, uint256 strike, bool strategy) public view returns (uint256) {
        return self.optioned[strike][_strategyIdx(strategy)];
    }

    function decreasePayoff(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.payoff[strike][_strategyIdx(strategy)] -= amount;
    }

    function accountPayoff(Info storage self, uint256 strike, bool strategy, uint256 payoff_) public {
        self.payoff[strike][_strategyIdx(strategy)] = payoff_;
    }

    function payoffShares(
        Info storage self,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) public view returns (uint256) {
        uint256 optioned = getOptioned(self, strike, strategy);
        uint256 payoff = self.payoff[strike][_strategyIdx(strategy)];

        // ToDo: use token decimal instead of WAD
        return amount.wmul(payoff).wdiv(optioned);
    }
}
