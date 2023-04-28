// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVPRegister} from "./IDVPRegister.sol";

contract TestnetDVPRegister is IDVPRegister {
    constructor() {}

    function isRegistered(address dvpAddr) external pure returns (bool ok) {
        dvpAddr;
        return false;
    }
}
