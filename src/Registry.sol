// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IRegistry} from "./interfaces/IRegistry.sol";

// TBD: move into the testnet directory
contract Registry is IRegistry {
    mapping(address => bool) registered;

    error MissingAddress();

    /// @inheritdoc IRegistry
    function register(address addr) public {
        registered[addr] = true;
    }

    /// @inheritdoc IRegistry
    function isRegistered(address dvpAddr) external view returns (bool ok) {
        return registered[dvpAddr];
    }

    /// @inheritdoc IRegistry
    function unregister(address addr) public {
        if (!registered[addr]) {
            revert MissingAddress();
        }
        delete registered[addr];
    }
}
