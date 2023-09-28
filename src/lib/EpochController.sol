// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {EpochFrequency} from "./EpochFrequency.sol";

// TBD: move to IEpochControls
struct Epoch {
    uint256 current;
    uint256 previous;
    uint256 frequency;
    uint256 numberOfRolledEpochs;
}

// TBD: split into EpochController (storage) and EpochHelper (memory)
library EpochController {

    error EpochNotFinished();

    function init(Epoch storage epoch, uint256 epochFrequency) public {
        if (epoch.current > 0) {
            return;
        }

        epoch.current = 0;
        epoch.previous = 0;
        EpochFrequency.validityCheck(epochFrequency);
        epoch.frequency = epochFrequency;
        epoch.numberOfRolledEpochs = 0;

        // TBD: it may be done in the calling contract (in order to leverage hooks)
        roll(epoch);
    }

    function roll(Epoch storage epoch) public {
        // Ensures that the current epoch is concluded
        if (!isFinished(epoch)) {
            revert EpochNotFinished();
        }

        epoch.previous = epoch.current;

        if (!isInitialized(epoch)) {
            // TBD: accept an initial reference expiry in `init` ?
            // NOTE: beware of `nextExpiry` gas usage on first rolled epoch
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

        epoch.current = nextEpoch;
        epoch.numberOfRolledEpochs++;
    }

    /**
        @notice Check if has been rolled the first epoch
        @return True if the first epoch has been rolled, false otherwise
     */
    function isInitialized(Epoch memory epoch) public pure returns (bool) {
        return epoch.current > 0;
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

    function timeToNextEpoch(Epoch memory epoch) public view returns (uint256) {
        if (block.timestamp > epoch.current) {
            return 0;
        }

        return epoch.current - block.timestamp;
    }

}
