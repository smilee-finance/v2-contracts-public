// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ISwapRouter} from "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import {IQuoter} from "@uniswap/v3-periphery/interfaces/IQuoter.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import {IExchange} from "./interfaces/IExchange.sol";

contract UniswapExchange is IExchange {
    ISwapRouter internal immutable _swapRouter;
    IQuoter internal immutable _quoter;

    // Fees for LP
    uint4 private constant _fee = 3000; // 0.3%
    uint160 private constant _sqrtPriceLimitX96 = 0;

    error AddressZero();

    constructor(address swapRouter, address quoter) {
        _swapRouter = ISwapRouter(swapRouter);
        _quoter = IQuoter(quoter);
    }

    /// @inheritdoc IExchange
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) public returns (uint256 tokenOutAmount) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            tokenIn,
            tokenOut,
            _fee,
            msg.sender,
            block.timestamp + 60,
            amountIn,
            amountIn,
            _sqrtPriceLimitX96
        );

        tokenOutAmount = _swapRouter.exactInputSingle(params);
    }

    /// @inheritdoc IExchange
    function getOutputAmount(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        return _quoter.quoteExactOutputSingle(tokenIn, tokenOut, _fee, amountIn, _sqrtPriceLimitX96);
    }

    /// @inheritdoc IExchange
    function getInputAmount(address tokenIn, address tokenOut, uint256 amountOut) public view returns (uint) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        return _quoter.quoteExactInputSingle(tokenIn, tokenOut, _fee, amountIn, _sqrtPriceLimitX96);
    }

    /// @inheritdoc IExchange
    function swapOut(address tokenIn, address tokenOut, uint256 amountOut) public returns (uint256 amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
            tokenIn,
            tokenOut,
            _fee,
            msg.sender,
            block.timestamp + 60,
            amountIn,
            amountIn,
            _sqrtPriceLimitX96
        );

        amountIn = _swapRouter.exactOutputSingle(params);
    }

    function _zeroAddressCheck(address token) private view {
        if (token == address(0)) {
            revert AddressZero();
        }
    }
}
