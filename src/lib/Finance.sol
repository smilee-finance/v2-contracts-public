// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {ud, convert} from "@prb/math/UD60x18.sol";
import {Amount, AmountHelper} from "./Amount.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";

/// @title Implementation of core financial computations for Smilee protocol
library Finance {
    using AmountHelper for Amount;

    function computeResidualPayoffs(
        Amount memory residualAmount,
        uint256 percentageUp,
        uint256 percentageDown,
        uint8 baseTokenDecimals
    ) public pure returns (uint256 payoffUp_, uint256 payoffDown_) {
        payoffUp_ = 0;
        payoffDown_ = 0;

        (uint256 residualAmountUp, uint256 residualAmountDown) = residualAmount.getRaw();

        if (residualAmountUp > 0) {
            residualAmountUp = AmountsMath.wrapDecimals(residualAmountUp, baseTokenDecimals);
            payoffUp_ = 2 * ud(residualAmountUp).mul(ud(percentageUp)).unwrap();
            payoffUp_ = AmountsMath.unwrapDecimals(payoffUp_, baseTokenDecimals);
        }

        if (residualAmountDown > 0) {
            residualAmountDown = AmountsMath.wrapDecimals(residualAmountDown, baseTokenDecimals);
            payoffDown_ = 2 * ud(residualAmountDown).mul(ud(percentageDown)).unwrap();
            payoffDown_ = AmountsMath.unwrapDecimals(payoffDown_, baseTokenDecimals);
        }
    }

    function getSwapPrice(
        int256 tokensToSwap,
        uint256 exchangedTokens,
        uint8 swappedTokenDecimals,
        uint8 exchangeTokenDecimals
    ) public pure returns (uint256 swapPrice) {
        exchangedTokens = AmountsMath.wrapDecimals(exchangedTokens, exchangeTokenDecimals);
        uint256 tokensToSwap_ = AmountsMath.wrapDecimals(SignedMath.abs(tokensToSwap), swappedTokenDecimals);

        swapPrice = ud(exchangedTokens).div(ud(tokensToSwap_)).unwrap();
    }

    function getUtilizationRate(uint256 used, uint256 total, uint8 tokenDecimals) public pure returns (uint256) {
        used = AmountsMath.wrapDecimals(used, tokenDecimals);
        total = AmountsMath.wrapDecimals(total, tokenDecimals);

        if (total == 0) {
            return 0;
        }

        return ud(used).div(ud(total)).unwrap();
    }

    /**
     * @notice Check slippage between premium and expected premium
     * @param premium Premium computed including the fees
     * @param expectedPremium External previewed premium computed including the fees
     * @param maxSlippage The slippage percentage value
     * @param tradeIsBuy true if buy, false otherwise
     * @return ok true if the slippage is on range, false otherwise
     */
    function checkSlippage(
        uint256 premium,
        uint256 expectedPremium,
        uint256 maxSlippage,
        bool tradeIsBuy
    ) public pure returns (bool ok) {
        uint256 slippage = ud(expectedPremium).mul(ud(maxSlippage)).unwrap();

        if (tradeIsBuy && (premium > expectedPremium + slippage)) {
            return false;
        }
        if (!tradeIsBuy && (premium < expectedPremium - slippage)) {
            return false;
        }

        return true;
    }
}
