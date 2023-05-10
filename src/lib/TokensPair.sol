// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library TokensPair {
    struct Pair {
        address baseToken;
        address sideToken;
    }

    function getBalances(Pair memory pair, address wallet) internal view returns (uint baseTokenBalance, uint sideTokenBalance) {
        baseTokenBalance = IERC20(pair.baseToken).balanceOf(wallet);
        sideTokenBalance = IERC20(pair.sideToken).balanceOf(wallet);
    }

    function getDecimals(Pair memory pair) internal view returns (uint baseTokenDecimals, uint sideTokenDecimals) {
        baseTokenDecimals = ERC20(pair.baseToken).decimals();
        sideTokenDecimals = ERC20(pair.sideToken).decimals();
    }
}
