// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AmountsMath} from "./AmountsMath.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

/// @title Implementation of core financial computations for Smilee protocol
library FinanceIGPayoff {
    using AmountsMath for uint256;

    /**
        @notice Computes concentrated liquidity impermanent gain percentage when current price falls in liquidity range
        @param sdivk Current side token price over strike price
        @param teta Theta coefficient
        @return inRangePayoffPerc The impermanent gain
     */
    function igPayoffInRange(uint256 sdivk, uint256 teta) public pure returns (uint256 inRangePayoffPerc) {
        return (AmountsMath.wrap(1) + sdivk - 2 * FixedPointMathLib.sqrt(sdivk)).wdiv(teta);
    }

    /**
        @notice Computes concentrated liquidity impermanent gain percentage when current price falls out of liquidity range
        @param sdivk Current side token price over strike price
        @param teta Theta coefficient
        @param k Ref. strike
        @param kbound Upper or lower bound of the range
        @return outRangePayoffPerc The impermanent gain
     */
    function igPayoffOutRange(
        uint256 sdivk,
        uint256 teta,
        uint256 k,
        uint256 kbound
    ) public pure returns (uint256 outRangePayoffPerc) {
        uint256 one = AmountsMath.wrap(1);
        uint256 kDivKboundRtd = FixedPointMathLib.sqrt(k.wdiv(kbound));
        uint256 kboundDivKRtd = FixedPointMathLib.sqrt(kbound.wdiv(k));

        bool c2Pos = kDivKboundRtd >= one;
        uint256 c2Abs = sdivk.wmul(c2Pos ? kDivKboundRtd - one : one - kDivKboundRtd);
        uint256 num;
        if (c2Pos) {
            num = one - c2Abs - kboundDivKRtd;
        } else {
            num = one + c2Abs - kboundDivKRtd;
        }
        return num.wdiv(teta);
    }

    /**
        @notice Computes payoff percentage for impermanent gain up / down strategies
        @param s Current side token price
        @param k Ref. strike
        @return igPOBull The percentage payoff for bull strategy
        @return igPOBear The percentage payoff for bear strategy
     */
    function igPayoffPerc(
        uint256 s,
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 teta
    ) external pure returns (uint256 igPOBull, uint256 igPOBear) {
        igPOBull = s <= k ? 0 : s > kb ? igPayoffOutRange(s.wdiv(k), teta, k, kb) : igPayoffInRange(s.wdiv(k), teta);
        igPOBear = s >= k ? 0 : s < ka ? igPayoffOutRange(s.wdiv(k), teta, k, ka) : igPayoffInRange(s.wdiv(k), teta);
    }

}
