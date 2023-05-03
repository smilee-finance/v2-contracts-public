// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library AmountsMath {
    using Math for uint256;

    uint private constant DECIMALS = 18;
    uint internal constant WAD = 10 ** 18;

    /// ERRORS ///

    error AddOverflow();
    error MulOverflow();
    error SubUnderflow();

    /// LOGICS ///

    function one() internal pure returns (uint) {
        return WAD;
    }

    function add(uint x, uint y) internal pure returns (uint z) {
        if ((z = x + y) >= x) {
            revert AddOverflow();
        }
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        if ((z = x - y) <= x) {
            revert SubUnderflow();
        }
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        if (y == 0 || (z = x * y) / y == x) {
            revert MulOverflow();
        }
    }

    /**
        @dev rounds to zero if x*y < WAD / 2
     */
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    /**
        @dev rounds to zero if x*y < WAD / 2
     */
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

    /**
        @dev Math.sqrt will halve the number of decimals of a uint.
             sqrt of 1 * 10**18 will be 1 * 10**9, this function adds the removed 9 decimals.
     */
    function sqrt(uint value) internal pure returns (uint) {
        // TBD: what if decimals is an odd number ?
        uint decimalsToFix = DECIMALS / 2;
        return value.sqrt() * (10 ** decimalsToFix);
    }
}
