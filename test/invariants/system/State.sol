// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Properties} from "./Properties.sol";
import {console} from "forge-std/console.sol";

abstract contract State is Properties {
    EpochInfo[] internal epochs;
    BuyInfo[] internal bullTrades;
    BuyInfo[] internal bearTrades;
    BuyInfo[] internal smileeTrades;
    WithdrawInfo[] internal withdrawals;
    DepositInfo[] internal _depositInfo;

    struct BuyState {
        bytes8 buyType;
        uint256 amount;
        uint256 tokenPrice;
        uint256 premium;
        uint256 strike;
        uint256 riskFreeRate;
        uint256 premiumOperationK;
        uint256 premiumOperationKaKb;
    }

    function _pushTrades(BuyInfo memory buyInfo) internal {
        console.log("buyInfo.amountUp", buyInfo.amountUp);
        console.log("buyInfo.amountDown", buyInfo.amountDown);
        if (buyInfo.amountUp > 0 && buyInfo.amountDown == 0) {
            bullTrades.push(buyInfo);
        } else if (buyInfo.amountUp == 0 && buyInfo.amountDown > 0) {
            bearTrades.push(buyInfo);
        } else {
            smileeTrades.push(buyInfo);
        }
    }

    /// Removes element at the given index from trades
    function _popTrades(uint256 index, BuyInfo memory trade) internal {
        if (trade.amountUp > 0 && trade.amountDown == 0) {
            bullTrades[index] = bullTrades[bullTrades.length - 1];
            bullTrades.pop();
        } else if (trade.amountUp == 0 && trade.amountDown > 0) {
            bearTrades[index] = bearTrades[bearTrades.length - 1];
            bearTrades.pop();
        } else {
            smileeTrades[index] = smileeTrades[smileeTrades.length - 1];
            smileeTrades.pop();
        }
    }

    /// Removes element at the given index from deposit info
    function _popDepositInfo(uint256 index) internal {
        _depositInfo[index] = _depositInfo[_depositInfo.length - 1];
        _depositInfo.pop();
    }

    /// Removes element at the given index from withdrawals
    function _popWithdrawals(uint256 index) internal {
        withdrawals[index] = withdrawals[withdrawals.length - 1];
        withdrawals.pop();
    }
}
