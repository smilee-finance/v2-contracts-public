// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVP} from "../interfaces/IDVP.sol";
import {Registry} from "../Registry.sol";

contract TestnetRegistry is Registry {
    mapping(address => bool) internal _registeredVaults;

    function register(address dvpAddr) public virtual override onlyRole(ADMIN_ROLE) {
        super.register(dvpAddr);
        _registeredVaults[IDVP(dvpAddr).vault()] = true;
    }

    function registerDVP(address addr) external onlyRole(ADMIN_ROLE) {
        _registeredDvps[addr] = true;
    }

    function registerVault(address addr) external onlyRole(ADMIN_ROLE) {
        _registeredVaults[addr] = true;
    }

    function isRegistered(address addr) external view virtual override returns (bool ok) {
        return _registeredDvps[addr];
    }

    function isRegisteredVault(address addr) external view virtual override returns (bool ok) {
        return _registeredVaults[addr];
    }

    function unregister(address addr) public virtual override onlyRole(ADMIN_ROLE) {
        super.unregister(addr);
        delete _registeredVaults[IDVP(addr).vault()];
    }
}
