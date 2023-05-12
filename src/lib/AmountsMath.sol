// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library AmountsMath {
    using Math for uint256;

    uint private constant DECIMALS = 18;
    uint private constant WAD = 10 ** 18;

    /// ERRORS ///

    error AddOverflow();
    error MulOverflow();
    error SubUnderflow();

    /// LOGICS ///

    function wrap(uint x) internal pure returns (uint z) {
        return mul(x, WAD);
    }

    function add(uint x, uint y) public pure returns (uint z) {
        if (!((z = x + y) >= x)) {
            revert AddOverflow();
        }
    }

    function sub(uint x, uint y) public pure returns (uint z) {
        if (!((z = x - y) <= x)) {
            revert SubUnderflow();
        }
    }

    function mul(uint x, uint y) public pure returns (uint z) {
        if (!(y == 0 || (z = x * y) / y == x)) {
            revert MulOverflow();
        }
    }

    //rounds to zero if x*y < WAD / 2
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    //rounds to zero if x*y < WAD / 2
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
}
