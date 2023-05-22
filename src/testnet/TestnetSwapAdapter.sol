// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IExchange} from "../interfaces/IExchange.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {AmountsMath} from "../lib/AmountsMath.sol";
import {TestnetToken} from "../testnet/TestnetToken.sol";

contract TestnetSwapAdapter is IExchange, Ownable {
    using AmountsMath for uint256;

    IPriceOracle internal priceOracle;

    error PriceZero();

    constructor(address _priceOracle) Ownable() {
        priceOracle = IPriceOracle(_priceOracle);
    }

    function changePriceOracle(address oracle) external onlyOwner {
        priceOracle = IPriceOracle(oracle);
    }

    function getOutputAmount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint) {
        return _getAmountOut(tokenIn, tokenOut, amountIn);
    }

    function _getAmountOut(address tokenIn, address tokenOut, uint amountIn) internal view returns (uint) {
        uint tokenOutPrice = priceOracle.getPrice(tokenIn, tokenOut);
        uint tokenInDecimals = ERC20(tokenIn).decimals();
        uint tokenOutDecimals = ERC20(tokenOut).decimals();

        return amountIn.wmul(tokenOutPrice).wdiv(10 ** tokenInDecimals).wmul(10 ** tokenOutDecimals);
    }

    // @inheritdoc IExchange
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        TestnetToken(tokenIn).burn(address(this), amountIn);
        amountOut = _getAmountOut(tokenIn, tokenOut, amountIn);
        TestnetToken(tokenOut).mint(msg.sender, amountOut);
    }

    // @inheritdoc IExchange
    function getInputAmount(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint) {
        return _getAmountIn(tokenIn, tokenOut, amountOut);
    }

    function _getAmountIn(address tokenIn, address tokenOut, uint amountOut) internal view returns (uint) {
        uint tokenInPrice = priceOracle.getPrice(tokenOut, tokenIn);

        if (tokenInPrice == 0) {
            // Otherwise could mint output tokens for free (no input needed).
            // It would be correct but we don't want to contemplate the 0 price case.
            revert PriceZero();
        }

        uint tokenInDecimals = ERC20(tokenIn).decimals();
        uint tokenOutDecimals = ERC20(tokenOut).decimals();

        return amountOut.wmul(tokenInPrice).wdiv(10 ** tokenOutDecimals).wmul(10 ** tokenInDecimals);
    }

    // @inheritdoc IExchange
    function swapOut(address tokenIn, address tokenOut, uint256 amountOut) external returns (uint256 amountIn) {
        amountIn = _getAmountIn(tokenIn, tokenOut, amountOut);
        ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        TestnetToken(tokenIn).burn(address(this), amountIn);
        TestnetToken(tokenOut).mint(msg.sender, amountOut);
    }
}
