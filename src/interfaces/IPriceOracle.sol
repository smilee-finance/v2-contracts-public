// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev everything is expressed in Wad (18 decimals)
interface IPriceOracle {
    /**
     * @notice Return token0 price in token1
     * @param  token0 Address of token 0
     * @param  token1 Address of token 1
     * @return price Ratio with 18 decimals
     */
    function getPrice(address token0, address token1) external view returns (uint256 price);

    /**
        @notice Return Price of token in referenceToken
        @param token Address of token
        @return price Price of token in referenceToken
     */
    function getTokenPrice(address token) external view returns (uint price);
}
