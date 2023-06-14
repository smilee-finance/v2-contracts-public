// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";

// ToDo: do something that can ease the management of the bot who triggers the rolling of the epochs (on the DVPs).
contract Registry is AccessControl, IRegistry {
    mapping(address => bool) internal _registeredDVPs;
    mapping(address => bool) internal _registeredVaults;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    error MissingAddress();

    constructor() {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IRegistry
    function register(address dvpAddr) public onlyRole(ADMIN_ROLE) {
        _registeredDVPs[dvpAddr] = true;
        _registeredVaults[IDVP(dvpAddr).vault()] = true;
    }

    /// @inheritdoc IRegistry
    function isRegistered(address addr) external view virtual returns (bool ok) {
        return _registeredDVPs[addr] || _registeredVaults[addr];
    }

    /// @inheritdoc IRegistry
    function unregister(address addr) public onlyRole(ADMIN_ROLE) {
        if (!_registeredDVPs[addr]) {
            revert MissingAddress();
        }
        delete _registeredDVPs[addr];
        delete _registeredVaults[IDVP(addr).vault()];
    }
}
