// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {Epoch, EpochController} from "./lib/EpochController.sol";

contract Registry is AccessControl, IRegistry {
    using EpochController for Epoch;

    address[] internal _dvps;
    address[] internal _tokens;
    mapping(address => bool) internal _registeredDvps;
    mapping(address => address[]) internal _dvpsBySideToken;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    event Registered(address dvp);
    event Unregistered(address dvp);

    error MissingAddress();

    constructor() {
        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    /// @inheritdoc IRegistry
    function register(address dvp) public virtual onlyRole(ROLE_ADMIN) {
        _dvps.push(dvp);
        _registeredDvps[dvp] = true;

        _indexBySideToken(dvp);

        emit Registered(dvp);
    }

    /// @inheritdoc IRegistry
    function isRegistered(address dvp) external view virtual returns (bool) {
        return _registeredDvps[dvp];
    }

    /// @inheritdoc IRegistry
    function isRegisteredVault(address vault) external view virtual override returns (bool registered) {
        for (uint256 i = 0; i < _dvps.length; i++) {
            if (_registeredDvps[_dvps[i]]) {
                if (IDVP(_dvps[i]).vault() == vault) {
                    return true;
                }
            }
        }
        return false;
    }

    /// @inheritdoc IRegistry
    function unregister(address addr) public virtual onlyRole(ROLE_ADMIN) {
        if (!_registeredDvps[addr]) {
            revert MissingAddress();
        }
        delete _registeredDvps[addr];

        uint256 index;
        for (uint256 i = 0; i < _dvps.length; i++) {
            if (_dvps[i] == addr) {
                index = i;
                break;
            }
        }
        uint256 last = _dvps.length - 1;
        _dvps[index] = _dvps[last];
        _dvps.pop();

        _removeIndexBySideToken(addr);

        emit Unregistered(addr);
    }

    /// @inheritdoc IRegistry
    function getUnrolledDVPs() external view returns (address[] memory list, uint256 number) {
        list = new address[](_dvps.length);
        for (uint256 i = 0; i < _dvps.length; i++) {
            IDVP dvp = IDVP(_dvps[i]);
            Epoch memory epoch = dvp.getEpoch();
            if (epoch.timeToNextEpoch() != 0 || Pausable(_dvps[i]).paused()) {
                continue;
            }
            list[number] = _dvps[i];
            number++;
        }
    }

    function getSideTokens() external view returns (address[] memory) {
        return _tokens;
    }

    function getDvpsBySideToken(address sideToken) external view returns (address[] memory) {
        return _dvpsBySideToken[sideToken];
    }

    function _indexBySideToken(address dvp) internal {
        address sideToken = IDVP(dvp).sideToken();

        bool found = false;
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == sideToken) {
                found = true;
                break;
            }
        }

        if (!found) {
            _tokens.push(sideToken);
        }

        address[] storage list = _dvpsBySideToken[sideToken];

        found = false;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == dvp) {
                found = true;
                break;
            }
        }
        if (found) {
            return;
        }

        _dvpsBySideToken[sideToken].push(dvp);
    }

    function _removeIndexBySideToken(address dvp) internal {
        address sideToken = IDVP(dvp).sideToken();
        address[] storage list = _dvpsBySideToken[sideToken];
        bool found = false;
        uint256 index;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == dvp) {
                index = i;
                found = true;
                break;
            }
        }
        if (!found) {
            return;
        }
        uint256 last = list.length - 1;
        list[index] = list[last];
        list.pop();

        if (list.length == 0) {
            found = false;
            for (uint256 i = 0; i < _tokens.length; i++) {
                if (_tokens[i] == sideToken) {
                    index = i;
                    break;
                }
            }
            last = _tokens.length - 1;
            _tokens[index] = _tokens[last];
            _tokens.pop();
        }
    }
}
