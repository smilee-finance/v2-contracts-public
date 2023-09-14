// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {Epoch, EpochController} from "./lib/EpochController.sol";

abstract contract EpochControls is IEpochControls, Pausable, Ownable {
    using EpochController for Epoch;

    Epoch private _epoch;

    event EpochRolled(uint256 indexed currentEpoch, uint256 previousEpoch);

    constructor(uint256 epochFrequency_) Pausable() Ownable() {
        _epoch.init(epochFrequency_);
    }

    /// @inheritdoc IEpochControls
    function getEpoch() public view returns (Epoch memory) {
        return _epoch;
    }

    /// @inheritdoc IEpochControls
    function rollEpoch() external virtual override {
        _requireNotPaused();

        _beforeRollEpoch();
        _epoch.roll();
        _afterRollEpoch();

        emit EpochRolled(_epoch.current, _epoch.previous);
    }

    /**
        @notice Hook that is called before rolling the epoch.
     */
    function _beforeRollEpoch() internal virtual {}

    /**
        @notice Hook that is called after rolling the epoch.
     */
    function _afterRollEpoch() internal virtual {}

    /// @inheritdoc IEpochControls
    function changePauseState() external override {
        _checkOwner();

        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    // ToDo: try to remove as `paused` is already public
    /// @inheritdoc IEpochControls
    function isPaused() public view override returns(bool paused_) {
        return paused();
    }

}
