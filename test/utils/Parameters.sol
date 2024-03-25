// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

library Parameters {
    uint8 public constant BASE_TOKEN_DECIMALS = 18;
    uint8 public constant SIDE_TOKEN_DECIMALS = 18;
    uint256 public constant BT_UNIT = 10 ** BASE_TOKEN_DECIMALS;
    uint256 public constant ST_UNIT = 10 ** SIDE_TOKEN_DECIMALS;
}
