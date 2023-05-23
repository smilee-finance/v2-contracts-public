// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IExchange {
    /**
        @notice Swaps an amount of tokenIn
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param amountIn The amount of input token to be swapped
        @return tokenOutAmount The amount of output token given by the exchange
     */
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 tokenOutAmount);

    /// ritorna il numero di tokenOut che verranno ricevuti in cambio di amountIn (di tokenIn)
    function getOutputAmount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint);

    /**
        @notice Tells the caller how many tokenIn it has to approve/provide in order to obtain the given amountOut of tokenOut
     */
    function getInputAmount(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint);

    /**
        @notice Swaps tokenIn tokens for the given amountOut of tokenOut
        @dev The client needs to approve the getInputAmount of tokenIn
     */
    function swapOut(address tokenIn, address tokenOut, uint256 amountOut) external returns (uint256 amountIn);
}
