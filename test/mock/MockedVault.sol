// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vault} from "../../src/Vault.sol";

/**
    @notice a mocked vault to ease the testing of DVPs

    Such vault should allow the test to simulate the presence of enough liquidity for the DVP operations.
 */
contract MockedVault is Vault {
    bool internal _fakeLockedValue;
    uint256 internal _lockedValue;

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_,
        address addressProvider_
    ) Vault(baseToken_, sideToken_, epochFrequency_, addressProvider_) {}

    function setLockedValue(uint256 value) public {
        _lockedValue = value;
        _fakeLockedValue = true;
    }

    function useRealLockedValue() public {
        _fakeLockedValue = false;
    }

    function getLockedValue() view public override returns (uint256) {
        if (_fakeLockedValue) {
            return _lockedValue;
        }
        return super.getLockedValue();
    }

    // ToDo: replace moveAsset
    function setBalances(uint256 baseTokenAmount, uint256 sideTokenAmount) public {
        // TBD vault state
    }
}
