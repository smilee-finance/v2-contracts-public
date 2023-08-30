// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {AmountsMath} from "./AmountsMath.sol";

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
        UD60x18 sdivkx18 = ud(sdivk);
        UD60x18 tetax18 = ud(teta);

        UD60x18 res = (convert(1).add(sdivkx18).sub((convert(2).mul(sdivkx18.sqrt())))).div(tetax18);
        inRangePayoffPerc = res.unwrap();
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
        uint256 kDivKboundRtd = ud(k.wdiv(kbound)).sqrt().unwrap();
        uint256 kboundDivKRtd = ud(kbound.wdiv(k)).sqrt().unwrap();

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
