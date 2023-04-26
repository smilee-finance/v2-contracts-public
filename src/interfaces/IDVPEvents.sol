// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./IDVPImmutables.sol";

/// @title Events emitted by a DVP
/// @notice Contains all events emitted by the DVP
interface IDVPEvents {
    /// @notice Emitted when option is minted for a given position
    /// @param sender The address that minted the option
    /// @param owner The owner of the option
    event Mint(address sender, address indexed owner);

    /// @notice Emitted when a position's option is destroyed
    /// @param owner The owner of the position that is being burnt
    event Burn(
        address indexed owner
    );
}
