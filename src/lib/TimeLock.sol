// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

struct TimeLockedAddress {
    address safe;
    address proposed;
    uint256 validAfter;
}

struct TimeLockedUInt {
    uint256 safe;
    uint256 proposed;
    uint256 validAfter;
}

struct TimeLockedBool {
    bool safe;
    bool proposed;
    uint256 validAfter;
}

library TimeLock {

    //-------------------------------------------------------------------------
    // Address
    //-------------------------------------------------------------------------

    function set(TimeLockedAddress storage tl, address value, uint256 delay) public {
        if (tl.validAfter == 0) {
            // The very first call is expected to be safe for immediate usage
            // NOTE: its security is linked to the deployment script
            tl.safe = value;
        }
        if (tl.validAfter > 0 && block.timestamp > tl.validAfter) {
            tl.safe = tl.proposed;
        }
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

    //-------------------------------------------------------------------------
    // UInt256
    //-------------------------------------------------------------------------

    function set(TimeLockedUInt storage tl, uint256 value, uint256 delay) public {
        if (tl.validAfter == 0) {
            // The very first call is expected to be safe for immediate usage
            // NOTE: its security is linked to the deployment script
            tl.safe = value;
        }
        if (tl.validAfter > 0 && block.timestamp > tl.validAfter) {
            tl.safe = tl.proposed;
        }
        tl.proposed = value;
        tl.validAfter = block.timestamp + delay;
    }

    function get(TimeLockedUInt memory tl) public view returns (uint256) {
        if (block.timestamp < tl.validAfter) {
            return tl.safe;
        } else {
            return tl.proposed;
        }
    }

    //-------------------------------------------------------------------------
    // Bool
    //-------------------------------------------------------------------------

    function set(TimeLockedBool storage tl, bool value, uint256 delay) public {
        if (tl.validAfter == 0) {
            // The very first call is expected to be safe for immediate usage
            // NOTE: its security is linked to the deployment script
            tl.safe = value;
        }
        if (tl.validAfter > 0 && block.timestamp > tl.validAfter) {
            tl.safe = tl.proposed;
        }
        tl.proposed = value;
        tl.validAfter = block.timestamp + delay;
    }

    function get(TimeLockedBool memory tl) public view returns (bool) {
        if (block.timestamp < tl.validAfter) {
            return tl.safe;
        } else {
            return tl.proposed;
        }
    }
}
