// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IExchange {
    /**
        @notice Swaps an amount of token
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param amountIn The amount of input token to be swapped
        @return tokenOutAmount The amount of output token given by the exchange
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 tokenOutAmount);

    function getSwapAmount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint);
}
