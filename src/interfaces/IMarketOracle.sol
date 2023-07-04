// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IMarketOracle {
    function getImpliedVolatility(
        address token0,
        address token1,
        uint256 strikePrice,
        uint256 frequency
    ) external view returns (uint256 iv);

    function getRiskFreeRate(address token0, address token1) external view returns (uint256 rate);
}
