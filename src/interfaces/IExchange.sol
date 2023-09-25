// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IExchange {
    /**
        @notice Swaps the given amount of tokenIn tokens in exchange for some tokenOut tokens.
        @param tokenIn The address of the input token.
        @param tokenOut The address of the output token.
        @param amountIn The amount of input token to be provided.
        @return amountOut The amount of output token given by the exchange.
        @dev The client choose how much tokenIn it wants to provide.
        @dev The client needs to approve the amountIn of tokenIn.
     */
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);

    /**
        @notice Preview how much tokenOut will be given back in exchange of an amount of tokenIn.
        @param tokenIn The address of the input token.
        @param tokenOut The address of the output token.
        @param amountIn The amount of input token to be provided.
        @return amountOut The amount of output tokens that will be given back in exchange of `amountIn`.
        @dev Allows to preview the amount of tokenOut that will be swapped by `swapIn`.
     */
    function getOutputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /**
        @notice Preview how much tokenIn will be taken in exchange for an amount of tokenOut.
        @param tokenIn The address of the input token.
        @param tokenOut The address of the output token.
        @param amountOut The amount of output token to be provided.
        @return tokenInAmount The amount of input tokens that will be taken in exchange of `amountOut`.
        @dev Allows to preview the amount of tokenIn that will be swapped by `swapOut`.
     */
    function getInputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256 tokenInAmount);

    /**
        @notice Swaps some tokenIn tokens in exchange for the given amount of tokenOut tokens.
        @param tokenIn The address of the input token.
        @param tokenOut The address of the output token.
        @param amountOut The amount of output token to be obtained.
        @return amountIn The amount of input token given by in exchange.
        @dev The client choose how much tokenOut it wants to obtain.
        @dev The client needs to approve the getInputAmount of tokenIn.
     */
    function swapOut(address tokenIn, address tokenOut, uint256 amountOut) external returns (uint256 amountIn);
}
