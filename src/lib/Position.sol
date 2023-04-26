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

    struct UpdateParams {
        uint256 epoch;
        address owner; // the address that owns the position
        uint256 strike; // strike price of the option
        uint256 strategy; // the option payoff type
        int256 amount; // the number of options to be created
    }

    /**
        @notice Returns the Info struct of a position, given uniqueness identifiers
        @param self The mapping containing all user positions
        @param owner The address of the position owner
        @param strike The entry price of the position
        @return position The position info struct of the given owners' position
     */
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        uint256 strategy,
        uint256 strike
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, strategy, strike))];
    }

    function _update(Info storage self, UpdateParams memory params) internal {
        require(params.amount > 0 || uint256(-params.amount) <= self.amount);
        if (self.epoch == 0) {
            // position is not initialized
            self.epoch = params.epoch;
            self.strike = params.strike;
            self.strategy = params.strategy;
        }

        if (params.amount < 0) {
            self.amount = self.amount - uint256(-params.amount);
        } else {
            self.amount = self.amount + uint256(params.amount);
        }
    }
}
