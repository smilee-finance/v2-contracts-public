// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Epoch} from "../lib/EpochController.sol";

/**
    @title A base contract for rolling epochs
 */
interface IEpochControls {
    error EpochFrozen();
    error EpochNotInitialized();
    error EpochNotFinished();

    /**
        @notice Returns the current epoch status
     */
    function getEpoch() external view returns (Epoch memory);

    /**
        @notice Regenerates the epoch-related processes, moving the current epoch to the next one
        @dev Need to call this also as a setup function on vault creation
    */
    function rollEpoch() external;

    /**
        @notice Pause/Unpause 
     */
    function changePauseState() external;

    /**
        @notice Allow to check if the contract is paused.
        @return paused The pause state.
     */
    function isPaused() external view returns(bool paused);

}
