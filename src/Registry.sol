// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";

// TBD: move into the testnet directory
// ToDo: do something that can ease the managerment of the bot who triggers the rolling of the epochs (on the DVPs).
contract Registry is AccessControl, IRegistry {
    mapping(address => bool) internal _registered;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    error MissingAddress();

    constructor() {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IRegistry
    function register(address addr) public onlyRole(ADMIN_ROLE) {
        _registered[addr] = true;
    }

    /// @inheritdoc IRegistry
    function registerPair(address dvp, address vault) external onlyRole(ADMIN_ROLE) {
        register(dvp);
        register(vault);
    }

    /// @inheritdoc IRegistry
    function isRegistered(address dvpAddr) external view returns (bool ok) {
        return _registered[dvpAddr];
    }

    /// @inheritdoc IRegistry
    function unregister(address addr) public onlyRole(ADMIN_ROLE) {
        if (!_registered[addr]) {
            revert MissingAddress();
        }
        delete _registered[addr];
    }
}
