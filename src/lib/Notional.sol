// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Amount, AmountHelper} from "./Amount.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {OptionStrategy} from "./OptionStrategy.sol";

// TBD: rename
/**
    @title Simple library to ease DVP liquidity access and modification
 */
library Notional {
    using AmountsMath for uint256;
    using AmountHelper for Amount;

    // NOTE: each one of the fields is a mapping strike -> [call_notional, put_notional]
    // TBD: use a mapping strike -> StrikeInfo
    // TBD: use a mapping of bools for the strategies, in order to avoid the need of "setup"
    struct Info {
        // initial capital
        mapping(uint256 => Amount) initial;
        // liquidity used by options
        mapping(uint256 => Amount) used;
        // payoff set aside
        mapping(uint256 => Amount) payoff; // TBD: rename "residualPayoff"
    }

    /**
        @notice Set the initial capital for the given strike and strategy.
        @param strike the reference strike.
        @param notional the initial capital.
     */
    function setInitial(Info storage self, uint256 strike, Amount memory notional) public {
        self.initial[strike] = notional;
    }

    /**
        @notice Get the amount of liquidity used by options.
        @param strike the reference strike.
        @return amount The used liquidity.
     */
    function getInitial(Info storage self, uint256 strike) public view returns (Amount memory amount) {
        amount = self.initial[strike];
    }

    /**
        @notice Get the amount of liquidity available for new options.
        @param strike the reference strike.
        @return available_ The available liquidity.
     */
    function available(Info storage self, uint256 strike) public view returns (Amount memory available_) {
        Amount memory initial = self.initial[strike];
        Amount memory used = self.used[strike];

        available_.up = initial.up - used.up;
        available_.down = initial.down - used.down;
    }

    /**
        @notice Record the increased usage of liquidity.
        @param strike the reference strike.
        @param amount the new used amount.
        @dev Overflow checks must be done externally.
     */
    function increaseUsage(Info storage self, uint256 strike, Amount memory amount) public {
        self.used[strike].increase(amount);
    }

    /**
        @notice Record the decreased usage of liquidity.
        @param strike the reference strike.
        @param amount the notional of the option.
        @dev Underflow checks must be done externally.
     */
    function decreaseUsage(Info storage self, uint256 strike, Amount memory amount) public {
        self.used[strike].decrease(amount);
    }

    /**
        @notice Get the amount of liquidity used by options.
        @param strike the reference strike.
        @return optionedCall_ The used liquidity.
        @return optionedPut_ The used liquidity.
     */
    function getUsed(Info storage self, uint256 strike) public view returns (uint256 optionedCall_, uint256 optionedPut_) {
        return self.used[strike].getRaw();
    }

    /**
        @notice Record the residual payoff setted aside for the expired options not yet redeemed.
        @param strike the reference strike.
        @param payoffCall_ the payoff set aside for the call strategy.
        @param payoffPut_ the payoff set aside for the put strategy.
     */
    function accountPayoffs(Info storage self, uint256 strike, uint256 payoffCall_, uint256 payoffPut_) public {
        // TBD: revert if already done
        self.payoff[strike].setRaw(payoffCall_, payoffPut_);
    }

    /**
        @notice Record the redeem of part of the residual payoff setted aside for the expired options not yet redeemed
        @param strike The reference strike
        @param amount The redeemed payoff
     */
    function decreasePayoff(Info storage self, uint256 strike, Amount memory amount) public {
        self.payoff[strike].decrease(amount);
    }

    /**
        @notice Get the residual payoff setted aside for the expired options not yet redeemed
        @param strike The reference strike
        @return amount The payoff set aside
     */
    function getAccountedPayoff(
        Info storage self,
        uint256 strike
    ) public view returns (Amount memory amount) {
        amount = self.payoff[strike];
    }

    /**
        @notice Get the share of residual payoff setted aside for the given expired position
        @param strike The position strike
        @param amount_ The position notional
        @param decimals The notional's token number of decimals
        @return payoff_ The owed payoff
        @dev It relies on the calls of decreaseUsage and decreasePayoff after each position is decreased
     */
    function shareOfPayoff(
        Info storage self,
        uint256 strike,
        Amount memory amount_,
        uint8 decimals
    ) public view returns (Amount memory payoff_) {
        (uint256 usedCall_, uint256 usedPut_) = getUsed(self, strike);
        Amount memory accountedPayoff_ = getAccountedPayoff(self, strike);

        if (amount_.up > 0) {
            amount_.up = AmountsMath.wrapDecimals(amount_.up, decimals);
            usedCall_ = AmountsMath.wrapDecimals(usedCall_, decimals);
            accountedPayoff_.up = AmountsMath.wrapDecimals(accountedPayoff_.up, decimals);

            // amount : used = share : payoff
            payoff_.up = amount_.up.wmul(accountedPayoff_.up).wdiv(usedCall_);
            payoff_.up = AmountsMath.unwrapDecimals(payoff_.up, decimals);
        }

        if (amount_.down > 0) {
            amount_.down = AmountsMath.wrapDecimals(amount_.down, decimals);
            usedPut_ = AmountsMath.wrapDecimals(usedPut_, decimals);
            accountedPayoff_.down = AmountsMath.wrapDecimals(accountedPayoff_.down, decimals);

            payoff_.down = amount_.down.wmul(accountedPayoff_.down).wdiv(usedPut_);
            payoff_.down = AmountsMath.unwrapDecimals(payoff_.down, decimals);
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
        used = self.used[strike].getTotal();
        total = self.initial[strike].getTotal();
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
        Amount memory amount,
        bool tradeIsBuy,
        uint8 tokenDecimals
    ) public view returns (uint256 utilizationRate) {
        (uint256 used, uint256 total) = utilizationRateFactors(self, strike);
        if (total == 0) {
            return 0;
        }

        uint256 totalAmount = amount.getTotal();
        totalAmount = AmountsMath.wrapDecimals(totalAmount, tokenDecimals);

        if (tradeIsBuy) {
            return (used.add(totalAmount)).wdiv(total);
        } else {
            return (used.sub(totalAmount)).wdiv(total);
        }
    }
}
