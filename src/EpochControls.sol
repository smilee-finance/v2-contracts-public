// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {EpochFrequency} from "./lib/EpochFrequency.sol";

abstract contract EpochControls is IEpochControls {
    uint256[] private _epochs;

    /// @inheritdoc IEpochControls
    uint256 public immutable override epochFrequency;

    /// @inheritdoc IEpochControls
    uint256 public override currentEpoch = 0;

    constructor(uint256 epochFrequency_) {
        EpochFrequency.validityCheck(epochFrequency_);
        epochFrequency = epochFrequency_;
    }

    /// Draft modifiers ///

    /// @notice Ensure the vault is active and current timestamp is in the active epoch
    modifier epochActive() {
        if (currentEpoch == 0) {
            revert NoActiveEpoch();
        }
        _;
    }

    modifier epochFinished(uint256 epoch) {
        // if currentEpoch == 0 consider it finished
        if (currentEpoch > 0 && block.timestamp <= epoch) {
            revert EpochNotFinished();
        }
        _;
    }

    modifier epochNotFrozen(uint256 epoch) {
        if(currentEpoch > 0 && epoch <= block.timestamp) {
            revert EpochFrozen();
        }
        _;
    }

    /// implementation ///

    /// @inheritdoc IEpochControls
    function epochs() public view override returns (uint256[] memory) {
        return _epochs;
    }

    function getLastRolledEpoch() internal view returns(uint256 lastEpoch) {
        lastEpoch = _epochs[_epochs.length - 2];
    } 

    /// @inheritdoc IEpochControls
    function rollEpoch() public virtual override epochFinished(currentEpoch) {
        uint256 nextEpoch = EpochFrequency.nextExpiry(block.timestamp, epochFrequency);

        // If next epoch expiry is in the past (should not happen...) go to next of the next
        while (block.timestamp > nextEpoch) {
            nextEpoch = EpochFrequency.nextExpiry(nextEpoch, epochFrequency);
        }

        currentEpoch = nextEpoch;
        _epochs.push(currentEpoch);
    }

    /// @inheritdoc IEpochControls
    function timeToNextEpoch() view public returns (uint256) {
        return currentEpoch - block.timestamp;
    }
}
