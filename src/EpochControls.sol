// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {EpochFrequency} from "./lib/EpochFrequency.sol";

abstract contract EpochControls is IEpochControls {
    uint256[] public epochs;

    /**
        @inheritdoc IEpochControls
     */
    uint256 public immutable override epochFrequency;

    /**
        @inheritdoc IEpochControls
     */
    uint256 public override currentEpoch;

    constructor(uint256 epochFrequency_) {
        EpochFrequency.validityCheck(epochFrequency_);
        epochFrequency = epochFrequency_;
        currentEpoch = 0;
    }

    /// MODIFIERS ///

    /**
        @notice Ensures that the current epoch holds a valid value
     */
    modifier epochInitialized() {
        if (!_isEpochInitialized()) {
            revert EpochNotInitialized();
        }
        _;
    }

    /**
        @notice Ensures that the current epoch is concluded
     */
    modifier epochFinished() {
        if (!_isEpochFinished(currentEpoch)) {
            revert EpochNotFinished();
        }
        _;
    }

    /**
        @notice Ensures that the current epoch is not concluded
     */
    modifier epochNotFrozen() {
        // if (_isEpochInitialized() && block.timestamp >= currentEpoch) {
        if (_isEpochFinished(currentEpoch)) {
            // NOTE: reverts also if the epoch has not been initialized
            revert EpochFrozen();
        }
        _;
    }

    /// GETTER ///

    /**
        @notice Get All The Epochs
        @return The epoch's array and its length
     */
    function getEpochs() public view returns (uint256[] memory, uint256) {
        return (epochs, epochs.length);
    }

    /// LOGIC ///

    

    /**
        @inheritdoc IEpochControls
     */
    function rollEpoch() public virtual override epochFinished() {
        _beforeRollEpoch();

        if (!_isEpochInitialized()) {
            // ToDo: review as we probably want a more specific/precise reference timestamp!
            currentEpoch = block.timestamp;
        }
        // ToDo: review as the custom timestamps are not done properly...
        uint256 nextEpoch = EpochFrequency.nextExpiry(currentEpoch, epochFrequency);

        // If next epoch expiry is in the past (should not happen...) go to next of the next
        while (block.timestamp > nextEpoch) {
            // TBD: recursively call rollEpoch for each missed epoch that has not been rolled ?
            // ---- should not be needed as every relevant operation should be freezed by using the epochNotFrozen modifier...
            nextEpoch = EpochFrequency.nextExpiry(nextEpoch, epochFrequency);
        }

        currentEpoch = nextEpoch;
        epochs.push(currentEpoch);

        _afterRollEpoch();
    }

    /**
        @notice Hook that is called before rolling the epoch.
     */
    function _beforeRollEpoch() internal virtual {}

    /**
        @notice Hook that is called after rolling the epoch.
     */
    function _afterRollEpoch() internal virtual {}

    /**
        @inheritdoc IEpochControls
     */
    function timeToNextEpoch() public view returns (uint256) {
        if (block.timestamp > currentEpoch) {
            return 0;
        }
        return currentEpoch - block.timestamp;
    }

    /**
        @notice Get number of past and current epochs
        @return number The number of past and current epochs
     */
    function getNumberOfEpochs() external view returns(uint256 number) {
        number = epochs.length;
    }

    /**
        @notice Check if an epoch should be considered ended
        @param epoch The epoch to check
        @return True if epoch is finished, false otherwise
        @dev it is expected to receive epochs that are <= currentEpoch
     */
    function _isEpochFinished(uint256 epoch) internal view returns (bool) {
        return block.timestamp > epoch;
    }

    /**
        @notice Check if has been rolled the first epoch
        @return True if the first epoch has been rolled, false otherwise
     */
    function _isEpochInitialized() internal view returns (bool) {
        return currentEpoch > 0;
    }

    /**
        @dev Second last timestamp
     */
    function _lastRolledEpoch() public view epochInitialized returns (uint256 lastEpoch) {
        if (epochs.length == 1) {
            return 0;
        }
        lastEpoch = epochs[epochs.length - 2];
    }
}
