// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AmountsMath} from "./AmountsMath.sol";
import {OptionStrategy} from "./OptionStrategy.sol";

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
        mapping(uint256 => uint256[]) used;
        // payoff set aside
        mapping(uint256 => uint256[]) payoff; // TBD: rename "residualPayoff"
    }

    struct Amount {
        uint256 up;
        uint256 down;
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
        self.used[strike] = new uint256[](2);
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
        @notice Get the amount of liquidity used by options.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return optioned_ The used liquidity.
     */
    function getInitial(Info storage self, uint256 strike, bool strategy) public view returns (uint256 optioned_) {
        return self.initial[strike][_strategyIdx(strategy)];
    }

    /**
        @notice Get the amount of liquidity available for new options.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @return available_ The available liquidity.
     */
    function available(Info storage self, uint256 strike, bool strategy) public view returns (uint256 available_) {
        return self.initial[strike][_strategyIdx(strategy)] - self.used[strike][_strategyIdx(strategy)];
    }

    function aggregatedInfo(
        Info storage self,
        uint256 strike
    ) public view returns (uint256 put, uint256 call, uint256 putAvail, uint256 callAvail) {
        return (
            self.initial[strike][_strategyIdx(false)],
            self.initial[strike][_strategyIdx(true)],
            self.initial[strike][_strategyIdx(false)] - self.used[strike][_strategyIdx(false)],
            self.initial[strike][_strategyIdx(true)] - self.used[strike][_strategyIdx(true)]
        );
    }

    /**
        @notice Record the increased usage of liquidity.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @param amount the used amount.
        @dev Overflow checks must be done externally.
     */
    function increaseUsage(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.used[strike][_strategyIdx(strategy)] += amount;
    }

    /**
        @notice Record the decreased usage of liquidity.
        @param strike the reference strike.
        @param strategy the reference strategy.
        @param amount the notional of the option.
        @dev Underflow checks must be done externally.
     */
    function decreaseUsage(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.used[strike][_strategyIdx(strategy)] -= amount;
    }

    /**
        @notice Get the amount of liquidity used by options.
        @param strike the reference strike.
        @return optionedCall_ The used liquidity.
        @return optionedPut_ The used liquidity.
     */
    function getUsed(Info storage self, uint256 strike) public view returns (uint256 optionedCall_, uint256 optionedPut_) {
        optionedCall_ = self.used[strike][_strategyIdx(OptionStrategy.CALL)];
        optionedPut_ = self.used[strike][_strategyIdx(OptionStrategy.PUT)];
    }

    /**
        @notice Record the residual payoff setted aside for the expired options not yet redeemed.
        @param strike the reference strike.
        @param payoffCall_ the payoff set aside for the call strategy.
        @param payoffPut_ the payoff set aside for the put strategy.
     */
    function accountPayoffs(Info storage self, uint256 strike, uint256 payoffCall_, uint256 payoffPut_) public {
        // TBD: revert if already done
        self.payoff[strike][_strategyIdx(OptionStrategy.CALL)] = payoffCall_;
        self.payoff[strike][_strategyIdx(OptionStrategy.PUT)] = payoffPut_;
    }

    /**
        @notice Record the redeem of part of the residual payoff setted aside for the expired options not yet redeemed
        @param strike The reference strike
        @param strategy The reference strategy
        @param amount The redeemed payoff
     */
    function decreasePayoff(Info storage self, uint256 strike, bool strategy, uint256 amount) public {
        self.payoff[strike][_strategyIdx(strategy)] -= amount;
    }

    /**
        @notice Get the residual payoff setted aside for the expired options not yet redeemed
        @param strike The reference strike
        @return payoffUp_ The payoff set aside for the call strategy
        @return payoffDown_ The payoff set aside for the put strategy
     */
    function getAccountedPayoffs(
        Info storage self,
        uint256 strike
    ) public view returns (uint256 payoffUp_, uint256 payoffDown_) {
        payoffUp_ = self.payoff[strike][_strategyIdx(OptionStrategy.CALL)];
        payoffDown_ = self.payoff[strike][_strategyIdx(OptionStrategy.PUT)];
    }

    /**
        @notice Get the share of residual payoff setted aside for the given expired position
        @param strike The position strike
        @param amountCall The position notional
        @param amountPut The position notional
        @param decimals The notional's token number of decimals
        @return payoffCall_ The owed payoff
        @return payoffPut_ The owed payoff
        @dev It relies on the calls of decreaseUsage and decreasePayoff after each position is decreased
     */
    function shareOfPayoff(
        Info storage self,
        uint256 strike,
        uint256 amountCall,
        uint256 amountPut,
        uint8 decimals
    ) public view returns (uint256 payoffCall_, uint256 payoffPut_) {
        (uint256 usedCall_, uint256 usedPut_) = getUsed(self, strike);
        (uint256 accountedPayoffCall_, uint256 accountedPayoffPut_) = getAccountedPayoffs(self, strike);

        if (amountCall > 0) {
            amountCall = AmountsMath.wrapDecimals(amountCall, decimals);
            usedCall_ = AmountsMath.wrapDecimals(usedCall_, decimals);
            accountedPayoffCall_ = AmountsMath.wrapDecimals(accountedPayoffCall_, decimals);

            // amount : used = share : payoff
            payoffCall_ = amountCall.wmul(accountedPayoffCall_).wdiv(usedCall_);
            payoffCall_ = AmountsMath.unwrapDecimals(payoffCall_, decimals);
        }

        if (amountPut > 0) {
            amountPut = AmountsMath.wrapDecimals(amountPut, decimals);
            usedPut_ = AmountsMath.wrapDecimals(usedPut_, decimals);
            accountedPayoffPut_ = AmountsMath.wrapDecimals(accountedPayoffPut_, decimals);

            payoffPut_ = amountPut.wmul(accountedPayoffPut_).wdiv(usedPut_);
            payoffPut_ = AmountsMath.unwrapDecimals(payoffPut_, decimals);
        }
    }

    /**
        @notice Get the overall used and total liquidity for a given strike
        @return used The overall used liquidity
        @return total The overall liquidity
     */
    function utilizationRateFactors(
        Info storage self,
        uint256 strike
    ) public view returns (uint256 used, uint256 total) {
        (uint256 usedCall_, uint256 usedPut_) = getUsed(self, strike);
        used = usedCall_ + usedPut_;
        total += getInitial(self, strike, OptionStrategy.CALL);
        total += getInitial(self, strike, OptionStrategy.PUT);
    }

    /**
        @notice Get the utilization rate that will result after a given trade
        @param amount The trade notional for CALL and PUT strategies
        @param tradeIsBuy True for a buy trade, false for sell
        @return utilizationRate The post-trade utilization rate
     */
    function postTradeUtilizationRate(
        Info storage self,
        uint256 strike,
        uint256 amount,
        bool tradeIsBuy
    ) public view returns (uint256 utilizationRate) {
        (uint256 used, uint256 total) = utilizationRateFactors(self, strike);
        if (total == 0) {
            return 0;
        }

        if (tradeIsBuy) {
            return (used.add(amount)).wdiv(total);
        } else {
            return (used.sub(amount)).wdiv(total);
        }
    }
}
