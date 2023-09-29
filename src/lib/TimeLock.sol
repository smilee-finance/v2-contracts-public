// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

struct TimeLockedAddress {
    address safe;
    address proposed;
    uint256 validAfter;
}

library TimeLock {
    error TimeLocked();

    function set(TimeLockedAddress storage tl, address value, uint256 delay) public {
        if (block.timestamp < tl.validAfter && tl.validAfter > 0) {
            revert TimeLocked();
        }
        tl.safe = tl.proposed;
        tl.proposed = value;
        tl.validAfter = block.timestamp + delay;
    }

    function get(TimeLockedAddress memory tl) public view returns (address) {
        if (block.timestamp < tl.validAfter) {
            return tl.safe;
        } else {
            return tl.proposed;
        }
    }
}
