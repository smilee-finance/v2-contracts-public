// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// ToDo: Evaluate to split IPriceOracle and IMarketOracle
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
    function priceDecimals() external view returns (uint decimals);

    /**
        @notice Return Price of token in referenceToken
        @param token Address of token
        @return price Price of token in referenceToken
     */
    function getTokenPrice(address token) external view returns (uint price);
}
