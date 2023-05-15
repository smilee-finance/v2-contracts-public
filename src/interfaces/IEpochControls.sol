// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @title A registry for rolling epochs
interface IEpochControls {

    error NoActiveEpoch();
    error NoNextEpoch();
    error EpochAlreadyStarted();
    error EpochDoesNotExist();
    error EpochEndBeforeLast();
    error EpochFrozen();
    error EpochNotFinished();

    /// @notice The list of currently executed epochs
    /// @return The list of epoch ends (timestamps) identifying the epochs
    function epochs() external view returns (uint256[] memory);

    /// @notice The frequency type of this object epochs
    /// @return epochFrequency the integer identifying the frequency type (see lib/EpochFrequency.sol   )
    function epochFrequency() external view returns (uint256 epochFrequency);

    /// @notice The currently active epoch identifier
    /// @return The epoch end (timestamp) of the cureent epoch
    function currentEpoch() external view returns (uint256);

    /// @notice Regenerates the epoch-related processes, moving currentEpoch to the next one
    /// @dev Need to call this also as a setup function on vault creation
    function rollEpoch() external;

    /**
        @notice Returns the number of seconds left until the next epoch.
        @return time the number of seconds left until the next epoch.
     */
    function timeToNextEpoch() view external returns (uint256 time);
}
