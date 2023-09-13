// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {EpochFrequency} from "./EpochFrequency.sol";

struct Epoch {
    uint256 current;
    uint256 previous;
    uint256 frequency;
    uint256 numberOfRolledEpochs;
}

library EpochController {

    error EpochFrozen();
    error EpochNotInitialized();
    error EpochNotFinished();

    function init(Epoch storage epoch, uint256 epochFrequency) public {
        epoch.current = 0;
        epoch.previous = 0;
        EpochFrequency.validityCheck(epochFrequency);
        epoch.frequency = epochFrequency;
        epoch.numberOfRolledEpochs = 0;
    }

    function checkNotFrozen(Epoch memory epoch) public view {
        if (isFinished(epoch)) {
            // NOTE: reverts also if the epoch has not been initialized
            revert EpochFrozen();
        }
    }

    function roll(Epoch storage epoch) public {
        // Ensures that the current epoch is concluded
        if (!isFinished(epoch)) {
            revert EpochNotFinished();
        }

        // _beforeRollEpoch();

        if (!isInitialized(epoch)) {
            // ToDo: review as we probably want a more specific/precise reference timestamp!
            epoch.current = block.timestamp;
        }
        // ToDo: review as the custom timestamps are not done properly...
        uint256 nextEpoch = EpochFrequency.nextExpiry(epoch.current, epoch.frequency);

        // If next epoch expiry is in the past (should not happen...) go to next of the next
        while (block.timestamp > nextEpoch) {
            // TBD: recursively call rollEpoch for each missed epoch that has not been rolled ?
            // ---- should not be needed as every relevant operation should be freezed by using the epochNotFrozen modifier...
            nextEpoch = EpochFrequency.nextExpiry(nextEpoch, epoch.frequency);
        }

        epoch.previous = epoch.current;
        epoch.current = nextEpoch;
        epoch.numberOfRolledEpochs++;

        // _afterRollEpoch();
    }

    function timeToNextEpoch(Epoch memory epoch) public view returns (uint256) {
        if (block.timestamp > epoch.current) {
            return 0;
        }
        return epoch.current - block.timestamp;
    }

    /**
        @notice Check if an epoch should be considered ended
        @param epoch The epoch to check
        @return True if epoch is finished, false otherwise
        @dev it is expected to receive epochs that are <= currentEpoch
     */
    function isFinished(Epoch memory epoch) public view returns (bool) {
        return block.timestamp > epoch.current;
    }

    /**
        @notice Check if has been rolled the first epoch
        @return True if the first epoch has been rolled, false otherwise
     */
    function isInitialized(Epoch memory epoch) public pure returns (bool) {
        return epoch.current > 0;
    }

    /**
        @dev Second last timestamp
     */
    function lastRolled(Epoch memory epoch) public pure returns (uint256 lastEpoch) {
        if (!isInitialized(epoch)) {
            revert EpochNotInitialized();
        }
        lastEpoch = epoch.previous;
    }

}
