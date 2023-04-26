// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

/// @title library to manage Smilee positions
library Position {
    // info stored for each user's position
    struct Info {
        uint256 amount; // the number of options owned by this position
        uint256 strategy; // the strategy held by this position (if its up / down IG, ...)
        uint256 entryPrice; // the entry price of the position, for now is also the strike price
        uint256 epoch; // the timestamp corresponding to the maturity of this position epoch
    }

    /// @notice Returns the Info struct of a position, given uniqueness identifiers
    /// @param self The mapping containing all user positions
    /// @param owner The address of the position owner
    /// @param entryPrice The entry price of the position
    /// @return position The position info struct of the given owners' position
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        uint256 strategy,
        uint256 entryPrice
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, strategy, entryPrice))];
    }

    function update(Info storage self, int256 amount) internal {
        require(amount > 0 || uint256(amount) < self.amount);
        if (amount < 0) {
            self.amount = self.amount - uint256(amount);
        } else {
            self.amount = self.amount + uint256(amount);
        }
    }
}
