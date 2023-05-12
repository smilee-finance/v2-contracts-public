// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {AmountsMath} from "./AmountsMath.sol";

library SignedMath {
    using AmountsMath for uint256;

    uint256 private constant MAX_INT = 57896044618658097711785492504343953926634992332820282019728792003956564819967;

    error Overflow(string name, uint256 val);

    /// @dev Utility to square a signed value
    function pow2(int256 n) public pure returns (uint256 res) {
        res = abs(n);
        res = res.wmul(res);
    }

    /// @dev Utility to negate an unsigned value
    function neg(uint256 n) public pure returns (int256 z) {
        if ((z = int256(n)) > type(int256).max) {
            revert Overflow("_neg_n", n);
        }

        z = -z;
    }

    /// @dev Utility to sum an int and a uint into a uint, returning the abs value of the sum and the sign
    function sum(int256 a, uint256 b) public pure returns (uint256 q, bool p) {
        if (b > MAX_INT) {
            revert Overflow("_sum_b", b);
        }

        int256 s = a + int256(b);
        q = abs(s);
        p = s >= 0;
    }

    /// @dev Returns the absolute unsigned value of a signed value, taken from OpenZeppelin SignedMath.sol
    function abs(int256 n) public pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }

    /// @dev Reverses an absolute unsigned value into an integer
    function revabs(uint256 n, bool p) internal pure returns (int256) {
        if (n > MAX_INT) {
            revert Overflow("_revabs_n", n);
        }
        return p ? int256(n) : -int256(n);
    }
}
