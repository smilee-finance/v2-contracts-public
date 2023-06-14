// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Registry} from "../Registry.sol";

contract TestnetRegistry is Registry {
    address internal _swapper;
    address internal _positionManager;

    function registerDVP(address addr) external onlyRole(ADMIN_ROLE) {
        _registeredDVPs[addr] = true;
    }

    function registerVault(address addr) external onlyRole(ADMIN_ROLE) {
        _registeredVaults[addr] = true;
    }

    function registerSwapper(address addr) external onlyRole(ADMIN_ROLE) {
        _swapper = addr;
    }

    function registerPositionManager(address addr) external onlyRole(ADMIN_ROLE) {
        _positionManager = addr;
    }

    function isRegistered(address addr) external view virtual override returns (bool ok) {
        return _registeredDVPs[addr] || _registeredVaults[addr] || _swapper == addr || _positionManager == addr;
    }
}
