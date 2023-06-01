// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExchange} from "../src/interfaces/IExchange.sol";
import {UniswapExchange} from "../src/UniswapExchange.sol";

contract UniswapExchangeTest is Test {
    
    IExchange uniswap;

    constructor() {
        uniswap = new UniswapExchange();
    }
}