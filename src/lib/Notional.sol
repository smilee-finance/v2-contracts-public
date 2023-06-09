// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AmountsMath} from "./AmountsMath.sol";

/**
    @title Simple library to ease DVP liquidity access and modification
 */
library Notional {
    using AmountsMath for uint256;

    // NOTE: each one of the fields is a mapping strike -> [call_notional, put_notional]
    // TBD: use a mapping strike -> StrikeInfo
    // TBD: use a mapping of bools for the strategies, in order to avoid the need of "setup"
    struct Info {
        // initial capital
        mapping(uint256 => uint256[]) initial;
        // liquidity used by options
        mapping(uint256 => uint256[]) optioned; // TBD: rename "used"
        // payoff set aside
        mapping(uint256 => uint256[]) payoff; // TBD: rename "residualPayoff"
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

    /**
        @notice Set the initial capital for the given strike and strategy.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @param notional the initial capital.
     */
    function setInitial(Info storage self, uint256 strike, bool strategy, uint256 notional) public {
        self.initial[strike][_strategyIdx(strategy)] = notional;
    }

    /**
        @notice Get the amount of liquidity available for new options.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return available_ The available liquidity.
     */
    function available(Info storage self, uint256 strike, bool strategy) public view returns (uint256 available_) {
        return self.initial[strike][_strategyIdx(strategy)] - self.optioned[strike][_strategyIdx(strategy)];
    }

    /**
        @notice Record the increased usage of liquidity.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @param amount the used amount.
        @dev Overflow checks must be done externally.
     */
    function increaseUsage(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.optioned[strike][_strategyIdx(strategy)] += amount;
    }

    /**
        @notice Record the decreased usage of liquidity.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @param amount the notional of the option.
        @dev Underflow checks must be done externally.
     */
    function decreaseUsage(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.optioned[strike][_strategyIdx(strategy)] -= amount;
    }

    /**
        @notice Get the amount of liquidity used by options.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return optioned_ The used liquidity.
     */
    function getOptioned(Info storage self, uint256 strike, bool strategy) public view returns (uint256 optioned_) {
        return self.optioned[strike][_strategyIdx(strategy)];
    }

    /**
        @notice Record the residual payoff setted aside for the expired options not yet redeemed.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @param payoff_ the payoff set aside.
     */
    function accountPayoff(Info storage self, uint256 strike, bool strategy, uint256 payoff_) public {
        self.payoff[strike][_strategyIdx(strategy)] = payoff_;
    }

    /**
        @notice Record the redeem of part of the residual payoff setted aside for the expired options not yet redeemed.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @param amount the redeemed payoff.
     */
    function decreasePayoff(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.payoff[strike][_strategyIdx(strategy)] -= amount;
    }

    /**
        @notice Get the residual payoff setted aside for the expired options not yet redeemed.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return payoff_ the payoff set aside.
     */
    function getAccountedPayoff(Info storage self, uint256 strike, bool strategy) public view returns (uint256 payoff_) {
        return self.payoff[strike][_strategyIdx(strategy)];
    }

    /**
        @notice Get the share of residual payoff setted aside for the given expired position.
        @param strike the position strike.
        @param strategy the position strategy.
        @param amount the position notional.
        @return payoff_ the owed payoff.
     */
    function shareOfPayoff(
        Info storage self,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) public view returns (uint256 payoff_) {
        uint256 optioned = getOptioned(self, strike, strategy);
        uint256 payoff = getAccountedPayoff(self, strike, strategy);

        // ToDo: use token decimals instead of WAD
        // NOTE: amount : optioned = share : payoff
        return amount.wmul(payoff).wdiv(optioned);
    }
}
