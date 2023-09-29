// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Amount} from "./Amount.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";

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

    function getIntrinsicValue(
        Amount memory amount,
        uint256 payoffPercUp,
        uint256 payoffPercDown,
        uint8 tokenDecimals
    ) internal pure returns (uint256 intrinsicValue) {
        // intrinsicValue := payoffPercUp * v0 * amountUp / (v0/2) + payoffPercDown * v0 * amountDown / (v0/2) =
        //                 = payoffPercUp * 2 * amountUp + payoffPercDown * 2 * amountDown
        intrinsicValue = payoffPercUp.wrapDecimals(tokenDecimals).wmul(2 * amount.up).add(
            payoffPercDown.wrapDecimals(tokenDecimals).wmul(2 * amount.down)
        );
        intrinsicValue = intrinsicValue.unwrapDecimals(tokenDecimals);
    }

    function getSwapPrice(
        int256 tokensToSwap,
        uint256 exchangedTokens,
        uint8 swappedTokenDecimals,
        uint8 exchangeTokenDecimals
    ) public pure returns (uint256 swapPrice) {
        exchangedTokens = AmountsMath.wrapDecimals(exchangedTokens, exchangeTokenDecimals);
        uint256 tokensToSwap_ = SignedMath.abs(tokensToSwap).wrapDecimals(swappedTokenDecimals);

        swapPrice = exchangedTokens.wdiv(tokensToSwap_);
    }

    function getUtilizationRate(uint256 used, uint256 total, uint8 tokenDecimals) public pure returns (uint256) {
        used = AmountsMath.wrapDecimals(used, tokenDecimals);
        total = AmountsMath.wrapDecimals(total, tokenDecimals);

        return used.wdiv(total);
    }
}
