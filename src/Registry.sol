// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";

contract Registry is AccessControl, IRegistry {
    address[] internal _dvps;
    address[] internal _tokens;
    mapping(address => bool) internal _registeredDVPs;
    mapping(address => address[]) internal _DVPsBySideToken;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    error MissingAddress();

    constructor() {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IRegistry
    function register(address dvpAddr) public virtual onlyRole(ADMIN_ROLE) {
        _dvps.push(dvpAddr);
        _registeredDVPs[dvpAddr] = true;

        _indexBySideToken(dvpAddr);
    }

    /// @inheritdoc IRegistry
    function isRegistered(address addr) external view virtual returns (bool ok) {
        return _registeredDVPs[addr];
    }

    /// @inheritdoc IRegistry
    function unregister(address addr) public virtual onlyRole(ADMIN_ROLE) {
        if (!_registeredDVPs[addr]) {
            revert MissingAddress();
        }
        delete _registeredDVPs[addr];

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
    }

    // TBD: add to IRegistry interface...
    function getUnrolledDVPs() external view returns (address[] memory list, uint256 number) {
        list = new address[](_dvps.length);
        for (uint256 i = 0; i < _dvps.length; i++) {
            IDVP dvp = IDVP(_dvps[i]);
            if (dvp.timeToNextEpoch() != 0) {
                continue;
            }
            // TBD: filter out the DVPs whose vault is in a dead state.
            list[number] = _dvps[i];
            number++;
        }
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

        address[] storage list = _DVPsBySideToken[sideToken];

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

        _DVPsBySideToken[sideToken].push(dvp);
    }

    function _removeIndexBySideToken(address dvp) internal {
        address sideToken = IDVP(dvp).sideToken();
        address[] storage list = _DVPsBySideToken[sideToken];
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

    function getDVPsBySideToken(address sideToken) external view returns (address[] memory) {
        return _DVPsBySideToken[sideToken];
    }

    function getSideTokens() external view returns (address[] memory) {
        return _tokens;
    }
}
