// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Epoch} from "../lib/EpochController.sol";

/**
    @title A base contract for rolling epochs
 */
interface IEpochControls {

    /**
        @notice Returns the current epoch status
     */
    function getEpoch() external view returns (Epoch memory);

    // ToDo: review the dev comment
    /**
        @notice Regenerates the epoch-related processes, moving the current epoch to the next one
        @dev Need to call this also as a setup function on vault creation
    */
    function rollEpoch() external;

}
