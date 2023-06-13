// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IRegistry} from "./interfaces/IRegistry.sol";

// TBD: move into the testnet directory
contract Registry is IRegistry {
    mapping(address => bool) internal _registered;

    error MissingAddress();

    /// @inheritdoc IRegistry
    function register(address addr) public {
        _registered[addr] = true;
    }

    /// @inheritdoc IRegistry
    function registerPair(address dvp, address vault) external {
        register(dvp);
        register(vault);
    }

    /// @inheritdoc IRegistry
    function isRegistered(address dvpAddr) external view returns (bool ok) {
        return _registered[dvpAddr];
    }

    /// @inheritdoc IRegistry
    function unregister(address addr) public {
        if (!_registered[addr]) {
            revert MissingAddress();
        }
        delete _registered[addr];
    }
}
