// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

/**
    @title library to manage Smilee positions
 */
library Position {
    // info stored for each user's position
    struct Info {
        uint256 amount; // the number of options owned by this position
        uint256 strategy; // the strategy held by this position (if its up / down IG, ...)
        uint256 strike; // the strike price of the position
        uint256 epoch; // the timestamp corresponding to the maturity of this position epoch
    }

    error CantBurnMoreThanMinted();

    /**
        @notice Returns the unique ID of a position (for a given epoch)
        @param owner The address of the position owner
        @param strategy The position strategy
        @param strike The strike price of the position
        @return id The position id
     */
    function getID(address owner, uint256 strategy, uint256 strike) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, strategy, strike));
    }

    /**
        @notice Updates the amount of options for a given position
        @param self The position to update
        @param delta The increment/decrement of options for the given position
     */
    function updateAmount(Info storage self, int256 delta) internal {
        if (delta < 0 && uint256(-delta) > self.amount) {
            revert CantBurnMoreThanMinted();
        }

        if (delta < 0) {
            self.amount = self.amount - uint256(-delta);
        } else {
            self.amount = self.amount + uint256(delta);
        }
    }
}
