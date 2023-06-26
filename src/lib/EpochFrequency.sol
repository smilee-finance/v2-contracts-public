// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

/// @title Simple library to manage DVPs epoch rolls.
library EpochFrequency {
    /// @notice Friday 2023-04-21 08:00 UTC
    uint256 public constant REF_TS = 1682064000;

    /// Enum values ///

    uint256 public constant DAILY = 0;
    uint256 public constant WEEKLY = 1;
    uint256 public constant TRD_FRI_MONTH = 2;

    /// Errors ///

    error UnsupportedFrequency();
    error MissingNextEpoch();

    /// Logic ///

    function validityCheck(uint256 epochFrequency) external pure {
        if (epochFrequency != DAILY && epochFrequency != WEEKLY && epochFrequency != TRD_FRI_MONTH) {
            revert UnsupportedFrequency();
        }
    }

    /// @notice Get the next timestamp in the given frequency sequence wrt the given ts
    /// @param ts The reference timestamp
    /// @param frequency The frequency of the sequence, chosen from the available ones
    function nextExpiry(uint256 ts, uint256 frequency) public pure returns (uint256 expiry) {
        if (frequency == DAILY) {
            return _nextTimeSpanExpiry(ts, 1 days);
        }
        if (frequency == WEEKLY) {
            return _nextTimeSpanExpiry(ts, 7 days);
        }
        if (frequency == TRD_FRI_MONTH) {
            return _nextCustomExpiry(ts, frequency);
        }

        revert UnsupportedFrequency();
    }

    /**
        @notice ... ToDo
        @param ts ... ToDo
        @param timeSpan the number of seconds in the timespan.
        @return nextExpiry_ the timestamp for the next epoch expiry.
     */
    function _nextTimeSpanExpiry(uint256 ts, uint256 timeSpan) private pure returns (uint256 nextExpiry_) {
        if (ts < REF_TS) {
            return REF_TS;
        }

        return REF_TS + _upDiv(ts - REF_TS, timeSpan) * timeSpan;
    }

    /// @notice Rounds up n / d adding 1 in case n / d = 0
    /// @notice This gives the next timestamp index even when remainder is 0
    function _upDiv(uint n, uint d) private pure returns (uint256) {
        return n / d + 1;
    }

    function _customTimestamps(uint256 frequency) private pure returns (uint256[2] memory tss) {
        if (frequency == TRD_FRI_MONTH) {
            // 3rd friday for next months
            return [
                uint256(1684483200), // Friday 2023-05-19 08:00 UTC
                uint256(1687075200) // Friday 2023-06-18 08:00 UTC
            ];
        }
        revert UnsupportedFrequency();
    }

    function _nextCustomExpiry(uint256 ts, uint256 periodType) private pure returns (uint256) {
        if (ts < REF_TS) {
            return REF_TS;
        }

        uint256[2] memory tss = _customTimestamps(periodType);
        for (uint256 i = 0; i < 2; i++) {
            if (ts < tss[i]) {
                return tss[i];
            }
        }
        revert MissingNextEpoch();
    }
}
