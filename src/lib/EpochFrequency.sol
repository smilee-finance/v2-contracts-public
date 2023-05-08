// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

/// @title Simple library to manage DVPs epoch rolls.
library EpochFrequency {
    /// @notice Friday 2023-04-21 08:00 UTC
    uint256 public constant REF_TS = 1682064000;
    /// @notice Number of seconds in a day
    uint256 public constant DAY_S = 1 days;
    /// @notice Number of seconds in a week
    uint256 public constant WEEK_S = 7 days;

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
        if (ts < REF_TS) {
            return REF_TS;
        }

        if (frequency == DAILY) return _nextDailyExpiry(ts);
        if (frequency == WEEKLY) return _nextWeeklyExpiry(ts);
        return _nextCustomExpiry(ts, frequency);
    }

    /// @notice Rounds up n / d adding 1 in case n / d = 0
    /// @notice This gives the next timestamp index even when remainder is 0
    function _upDiv(uint n, uint d) public pure returns (uint256) {
        return n / d + 1;
    }

    function _nextDailyExpiry(uint256 ts) public pure returns (uint256) {
        return REF_TS + _upDiv(ts - REF_TS, DAY_S) * DAY_S;
    }

    function _nextWeeklyExpiry(uint256 ts) public pure returns (uint256) {
        return REF_TS + _upDiv(ts - REF_TS, WEEK_S) * WEEK_S;
    }

    function _customTimestamps(uint256 frequency) public pure returns (uint256[2] memory tss) {
        if (frequency == TRD_FRI_MONTH) {
            // 3rd friday for next months
            return [
                uint256(1684483200), // Friday 2023-05-19 08:00 UTC
                uint256(1687075200) // Friday 2023-06-18 08:00 UTC
            ];
        }
        revert UnsupportedFrequency();
    }

    function _nextCustomExpiry(uint256 ts, uint256 periodType) public pure returns (uint256) {
        uint256[2] memory tss = _customTimestamps(periodType);
        for (uint256 i = 0; i < 2; i++) {
            if (ts < tss[i]) return tss[i];
        }
        revert MissingNextEpoch();
    }
}
