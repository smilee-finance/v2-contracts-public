// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// ToDo: Evaluate to split IPriceOracle and IMarketOracle
interface IMarketOracle {
    function getImpliedVolatility(
        address token0,
        address token1,
        uint256 strikePrice,
        uint256 frequency
    ) external returns (uint256 iv);

    function getRiskFreeRate(address token0, address token1) external returns (uint256 rate);
}
