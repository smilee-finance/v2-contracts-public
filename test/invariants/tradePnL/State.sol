// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Properties} from "./Properties.sol";
import {console} from "forge-std/console.sol";

abstract contract State is Properties {
    EpochInfo[] internal epochs;
    BuyInfo[] internal bullTrades;
    BuyInfo[] internal bearTrades;
    BuyInfo[] internal smileeTrades;

    BuyInfo internal lastBuy;
    int256 firstDepositEpoch = -1;

    function _pushTrades(BuyInfo memory buyInfo) internal {
        if (buyInfo.amountUp > 0 && buyInfo.amountDown == 0) {
            bullTrades.push(buyInfo);
        } else if (buyInfo.amountUp == 0 && buyInfo.amountDown > 0) {
            bearTrades.push(buyInfo);
        } else {
            smileeTrades.push(buyInfo);
        }
    }

    /// Removes element at the given index from trades
    function _popTrades(uint256 index, BuyInfo memory trade, uint256 amountSold) internal {
        if (trade.amountUp > 0 && trade.amountDown == 0) {
            if (amountSold == trade.amountUp) {
                bullTrades[index] = bullTrades[bullTrades.length - 1];
                bullTrades.pop();
            } else {
                bullTrades[index].amountUp -= amountSold;
            }
        } else if (trade.amountUp == 0 && trade.amountDown > 0) {
            if (amountSold == trade.amountDown) {
                bearTrades[index] = bearTrades[bearTrades.length - 1];
                bearTrades.pop();
            } else {
                bearTrades[index].amountDown -= amountSold;
            }
        } else {
            if (amountSold == trade.amountUp) {
                smileeTrades[index] = smileeTrades[smileeTrades.length - 1];
                smileeTrades.pop();
            } else {
                smileeTrades[index].amountUp -= amountSold;
                smileeTrades[index].amountDown -= amountSold;
            }
        }
    }
}
