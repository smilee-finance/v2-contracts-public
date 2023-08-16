// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IExchange} from "../interfaces/IExchange.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IToken} from "../interfaces/IToken.sol";
import {AmountsMath} from "../lib/AmountsMath.sol";
import {TestnetToken} from "../testnet/TestnetToken.sol";

contract TestnetSwapAdapter is IExchange, Ownable {
    using AmountsMath for uint256;

    IPriceOracle internal _priceOracle;

    error PriceZero();

    constructor(address priceOracle) Ownable() {
        _priceOracle = IPriceOracle(priceOracle);
    }

    function changePriceOracle(address oracle) external onlyOwner {
        _priceOracle = IPriceOracle(oracle);
    }

    function getOutputAmount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint) {
        return _getAmountOut(tokenIn, tokenOut, amountIn);
    }

    function _getAmountOut(address tokenIn, address tokenOut, uint amountIn) internal view returns (uint) {
        uint tokenOutPrice = _priceOracle.getPrice(tokenIn, tokenOut);
        amountIn = AmountsMath.wrapDecimals(amountIn, IToken(tokenIn).decimals());
        return AmountsMath.unwrapDecimals(amountIn.wmul(tokenOutPrice), IToken(tokenOut).decimals());
    }

    // @inheritdoc IExchange
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        IToken(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        TestnetToken(tokenIn).burn(address(this), amountIn);
        amountOut = _getAmountOut(tokenIn, tokenOut, amountIn);
        TestnetToken(tokenOut).mint(msg.sender, amountOut);
    }

    // @inheritdoc IExchange
    function getInputAmount(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint) {
        return _getAmountIn(tokenIn, tokenOut, amountOut);
    }

    function _getAmountIn(address tokenIn, address tokenOut, uint amountOut) internal view returns (uint) {
        uint tokenInPrice = _priceOracle.getPrice(tokenOut, tokenIn);

        if (tokenInPrice == 0) {
            // Otherwise could mint output tokens for free (no input needed).
            // It would be correct but we don't want to contemplate the 0 price case.
            revert PriceZero();
        }

        amountOut = AmountsMath.wrapDecimals(amountOut, IToken(tokenOut).decimals());
        return AmountsMath.unwrapDecimals(amountOut.wmul(tokenInPrice), IToken(tokenIn).decimals());
    }

    // @inheritdoc IExchange
    function swapOut(address tokenIn, address tokenOut, uint256 amountOut) external returns (uint256 amountIn) {
        amountIn = _getAmountIn(tokenIn, tokenOut, amountOut);
        IToken(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        TestnetToken(tokenIn).burn(address(this), amountIn);
        TestnetToken(tokenOut).mint(msg.sender, amountOut);
    }
}
