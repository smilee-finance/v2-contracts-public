// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVPRegister} from "./interfaces/testnet/IDVPRegister.sol";

contract DVPRegister is IDVPRegister {
    mapping(address => bool) registered;

    // ToDo: limit msg.sender
    function register(address addr) public {
        registered[addr] = true;
    }

    function isRegistered(address dvpAddr) external view returns (bool ok) {
        return registered[dvpAddr];
    }
}
