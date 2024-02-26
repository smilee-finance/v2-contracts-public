// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FeeManager} from "@project/FeeManager.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {BaseParameters} from "./BaseParameters.sol";

abstract contract Parameters is BaseParameters {
    bool internal FLAG_SLIPPAGE = false;

    // Token parameters
    uint8 internal BASE_TOKEN_DECIMALS = 18;
    uint8 internal SIDE_TOKEN_DECIMALS = 18;
    uint256 internal INITIAL_TOKEN_PRICE = 1e18;
    uint256 internal MIN_TOKEN_PRICE = 0.01e18;
    uint256 internal MAX_TOKEN_PRICE = 500e18;

    // Vault parameters
    uint256 internal INITIAL_VAULT_DEPOSIT = 0;
    uint256 internal MIN_VAULT_DEPOSIT = 2_000e18;
    uint256 internal EPOCH_FREQUENCY = EpochFrequency.DAILY;

    // IG parameters
    uint256 internal MIN_OPTION_BUY = 1_000e18; // MAX is bullAvailNotional or bearAvailNotional
}
