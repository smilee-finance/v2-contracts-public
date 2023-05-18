// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vault} from "../../src/Vault.sol";

contract MockedVault is Vault {
    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_,
        address addressProvider_
    ) Vault(baseToken_, sideToken_, epochFrequency_, addressProvider_) {}
}