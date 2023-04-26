// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @title DVP state that never changes
/// @notice These parameters are fixed for a DVP forever, i.e., the methods will always return the same values
interface IDVPImmutables {
    /// @notice The contract that deployed the DVP
    /// @return The contract address
    function factory() external view returns (address);

    /// @notice The base token in the pair of the DVP
    /// @return baseToken The contract address of the base token
    function baseToken() external view returns (address baseToken);

    /// @notice The side token in the pair of the DVP
    /// @return sideToken The contract address of the side token
    function sideToken() external view returns (address sideToken);

    /// @notice The amount of liquidity this option has access to
    /// @return optionSize The liquidity denominated in base token
    function optionSize() external view returns (uint256 optionSize);
}
