// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IPriceOracle {
    /**
     * @notice Return token0 price in token1
     * @param  token0 Address of token 0
     * @param  token1 Address of token 1
     * @return price Ratio with 18 decimals
     */
    function getPrice(address token0, address token1) external view returns (uint256 price);

    /**
     * @notice Return the number of decimals for the prices
     * @return decimals Number of decimals for the prices
     */
    function priceDecimals() external pure returns (uint decimals);

    /**
        @notice Return Price of token in referenceToken
        @param token Address of token
        @return price Price of token in referenceToken
     */
    function getTokenPrice(address token) external view returns (uint price);

    function getImpliedVolatility(address token0, address token1, uint256 strikePrice, uint256 frequency) external returns (uint256 iv);

    function getRiskFreeRate(address token0, address token1) external returns (uint256 rate);
}
