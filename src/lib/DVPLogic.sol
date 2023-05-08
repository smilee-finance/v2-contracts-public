// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

library DVPLogic {
    struct DVPCreateParams {
        address baseToken;
        address sideToken;
    }

    /// Errors ///

    error AddressZero();

    /// Logic ///

    function valid(DVPCreateParams memory params) public pure {
        if (params.baseToken == address(0x0)) revert AddressZero();
        if (params.sideToken == address(0x0)) revert AddressZero();
    }
}
