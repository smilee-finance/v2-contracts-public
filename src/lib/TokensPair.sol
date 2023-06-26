// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library TokensPair {
    struct Pair {
        address baseToken;
        address sideToken;
    }

    error AddressZero();
    error SameToken();
    error InvalidToken(address token);

    function getBalances(Pair memory pair, address wallet) public view returns (uint baseTokenBalance, uint sideTokenBalance) {
        baseTokenBalance = IERC20(pair.baseToken).balanceOf(wallet);
        sideTokenBalance = IERC20(pair.sideToken).balanceOf(wallet);
    }

    function getDecimals(Pair memory pair) public view returns (uint baseTokenDecimals, uint sideTokenDecimals) {
        baseTokenDecimals = ERC20(pair.baseToken).decimals();
        sideTokenDecimals = ERC20(pair.sideToken).decimals();
    }

    function validate(Pair memory pair) public view {
        if (pair.baseToken == address(0) || pair.sideToken == address(0)) {
            revert AddressZero();
        }
        if (pair.baseToken == pair.sideToken) {
            revert SameToken();
        }
        try IERC20(pair.baseToken).balanceOf(address(this)) returns (uint) {
            // no-op
        } catch {
            revert InvalidToken(pair.baseToken);
        }
        try IERC20(pair.sideToken).balanceOf(address(this)) returns (uint) {
            // no-op
        } catch {
            revert InvalidToken(pair.sideToken);
        }
    }
}
