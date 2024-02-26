// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FeeManager} from "@project/FeeManager.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {BaseParameters} from "./BaseParameters.sol";

abstract contract Parameters is BaseParameters {
    bool internal FLAG_SLIPPAGE = false;

    // Token parameters
    uint8 internal BASE_TOKEN_DECIMALS = 6;
    uint8 internal SIDE_TOKEN_DECIMALS = 8;
    uint256 internal INITIAL_TOKEN_PRICE = 1e18;
    uint256 internal MIN_TOKEN_PRICE = INITIAL_TOKEN_PRICE / 10 ** 3;
    uint256 internal MAX_TOKEN_PRICE = INITIAL_TOKEN_PRICE * 10 ** 3;

    // Vault parameters
    uint256 internal INITIAL_VAULT_DEPOSIT = 2_000 * 10 ** BASE_TOKEN_DECIMALS;
    uint256 internal MIN_VAULT_DEPOSIT = 0.0001e6;
    uint256 internal EPOCH_FREQUENCY = EpochFrequency.DAILY;

    // IG parameters
    uint256 internal MIN_OPTION_BUY = 0.001e6; // MAX is bullAvailNotional or bearAvailNotional
}
