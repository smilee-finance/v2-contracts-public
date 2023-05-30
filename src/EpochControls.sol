// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {EpochFrequency} from "./lib/EpochFrequency.sol";

abstract contract EpochControls is IEpochControls {
    uint256[] private _epochs;

    /**
        @inheritdoc IEpochControls
     */
    uint256 public immutable override epochFrequency;

    /**
        @inheritdoc IEpochControls
     */
    uint256 public override currentEpoch = 0;

    constructor(uint256 epochFrequency_) {
        EpochFrequency.validityCheck(epochFrequency_);
        epochFrequency = epochFrequency_;
    }

    /// MODIFIERS ///
    /**
        @notice Ensures the current epoch holds a valid value
     */
    modifier epochInitialized() {
        if (!isEpochInitialized()) {
            //TODO: Change name
            revert EpochNotActive();
        }
        _;
    }

    /**
        @notice Ensures the given epoch is concluded
     */
    modifier epochFinished(uint256 epoch) {
        // if currentEpoch == 0 consider it finished
        if (!isEpochFinished(epoch)) {
            revert EpochNotFinished();
        }
        _;
    }

    modifier epochNotFrozen() {
        if (isEpochInitialized() && block.timestamp >= currentEpoch) {
            revert EpochFrozen();
        }
        _;
    }

    /// LOGIC ///

    /**
        @inheritdoc IEpochControls
     */
    function epochs() public view override returns (uint256[] memory) {
        return _epochs;
    }

    /**
        @inheritdoc IEpochControls
     */
    function rollEpoch() public virtual override epochFinished(currentEpoch) {
        _beforeRollEpoch();

        uint256 nextEpoch = EpochFrequency.nextExpiry(block.timestamp, epochFrequency);

        // If next epoch expiry is in the past (should not happen...) go to next of the next
        while (block.timestamp > nextEpoch) {
            nextEpoch = EpochFrequency.nextExpiry(nextEpoch, epochFrequency);
        }

        currentEpoch = nextEpoch;
        _epochs.push(currentEpoch);

        _afterRollEpoch();
    }

    function _beforeRollEpoch() internal virtual {}
    function _afterRollEpoch() internal virtual {}

    /**
        @inheritdoc IEpochControls
     */
    function timeToNextEpoch() public view returns (uint256) {
        return currentEpoch - block.timestamp;
    }

    /**
        @notice Check if an epoch is already rolled
        @param epoch The epoch to check
        @return True if epoch is finished, false otherwise
     */
    function isEpochFinished(uint256 epoch) internal view returns (bool) {
        if(!isEpochInitialized()) {
            return true;
        }
        return block.timestamp > epoch;
    }

    /**
        @notice Check if has been rolled the first epoch
        @return True if the first epoch has been rolled, false otherwise
     */
    function isEpochInitialized() internal view returns (bool) {
        return currentEpoch > 0;
    }

    /**
        @dev Second last timestamp
     */
    function _lastRolledEpoch() internal view returns (uint256 lastEpoch) {
        lastEpoch = _epochs[_epochs.length - 2];
    }
}
