// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

/**
    @title library to manage Smilee positions
 */
library Position {
    // Stored info for each user's position
    struct Info {
        // The number of options owned by this position
        uint256 amount;
        // the strategy held by this position (if its up / down IG, ...)
        bool strategy;
        // the strike price of the position
        uint256 strike;
        // the timestamp corresponding to the maturity of this position epoch
        uint256 epoch;
    }

    /**
        @notice Returns the unique ID of a position (for a given epoch)
        @param owner The address of the position owner
        @param strategy The position strategy
        @param strike The strike price of the position
        @return id The position id
     */
    function getID(address owner, bool strategy, uint256 strike) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, strategy, strike));
    }

    /**
        @notice Checks if the position exists.
        @param self The position to update.
        @dev a position exists if its epoch is set.
     */
    function exists(Info storage self) public view returns (bool) {
        return self.epoch != 0;
    }
}
