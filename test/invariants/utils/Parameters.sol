// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FeeManager} from "@project/FeeManager.sol";

abstract contract Parameters {
    uint256 internal INITIAL_VAULT_DEPOSIT = 1000000000e18;
    uint256 internal MIN_VAULT_DEPOSIT = 1;
    uint256 internal MAX_VAULT_DEPOSIT = 1000000000e18;

    bool internal TOKEN_PRICE_CAN_CHANGE = true;
    uint256 internal MIN_TOKEN_PRICE = 0.01e18;
    uint256 internal MAX_TOKEN_PRICE = 1000e18;

    uint256 internal MIN_OPTION_BUY = 1;
    uint256 internal MAX_OPTION_BUY = 100; // bullAvailNotional
    uint256 internal MIN_OPTION_SELL = 0;
    uint256 internal MAX_OPTION_SELL = 100; // bearAvailNotional

    uint256 internal _VOLATILITY = 0.5e18;

    uint256 internal SLIPPAGE = 0.03e18;

    // FEE MANAGER
    FeeManager.FeeParams internal FEE_PARAMS =
        FeeManager.FeeParams({
            timeToExpiryThreshold: 3600,
            minFeeBeforeTimeThreshold: 0,
            minFeeAfterTimeThreshold: 0,
            successFeeTier: 0,
            vaultSellMinFee: 0,
            feePercentage: 0.0035e18,
            capPercentage: 0.125e18,
            maturityFeePercentage: 0.0015e18,
            maturityCapPercentage: 0.125e18
        });
}
