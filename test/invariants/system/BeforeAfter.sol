// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {VaultLib} from "@project/lib/VaultLib.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";

abstract contract BeforeAfter is Setup {
    struct Vars {
        uint256 value;
    }

    VaultLib.VaultState internal _initialVaultState;
    VaultLib.VaultState internal _endingVaultState;

    Vars internal _before;
    Vars internal _after;

    function __before() internal {}

    function __after() internal {}
}
