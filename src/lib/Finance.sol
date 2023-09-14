// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {AmountsMath} from "./AmountsMath.sol";

/// @title Implementation of core financial computations for Smilee protocol
library Finance {
    using AmountsMath for uint256;

    function computeResidualPayoffs(
        uint256 residualAmountUp,
        uint256 percentageUp,
        uint256 residualAmountDown,
        uint256 percentageDown,
        uint8 baseTokenDecimals
    ) public pure returns (uint256 payoffUp_, uint256 payoffDown_) {
        payoffUp_ = 0;
        payoffDown_ = 0;

        if (residualAmountUp > 0) {
            residualAmountUp = AmountsMath.wrapDecimals(residualAmountUp, baseTokenDecimals);
            payoffUp_ = residualAmountUp.wmul(percentageUp);
            payoffUp_ = AmountsMath.unwrapDecimals(payoffUp_, baseTokenDecimals);
        }

        if (residualAmountDown > 0) {
            residualAmountDown = AmountsMath.wrapDecimals(residualAmountDown, baseTokenDecimals);
            payoffDown_ = residualAmountDown.wmul(percentageDown);
            payoffDown_ = AmountsMath.unwrapDecimals(payoffDown_, baseTokenDecimals);
        }
    }
}
