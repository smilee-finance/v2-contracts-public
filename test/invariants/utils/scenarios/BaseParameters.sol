// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FeeManager} from "@project/FeeManager.sol";

abstract contract BaseParameters {
    bool internal USE_ORACLE_IMPL_VOL = false;

    // IG parameters
    uint256 internal VOLATILITY = 0.5e18;
    uint256 internal ACCEPTED_SLIPPAGE = 0.05e18;

    uint256 internal MIN_TIME_WARP = 1000; // see invariant IG_24_3

    // FEE MANAGER
    FeeManager.FeeParams internal FEE_PARAMS =
        FeeManager.FeeParams({
            timeToExpiryThreshold: 3600,
            minFeeBeforeTimeThreshold: 0,
            minFeeAfterTimeThreshold: 0,
            successFeeTier: 0,
            feePercentage: 0.0035e18,
            capPercentage: 0.125e18,
            maturityFeePercentage: 0.0015e18,
            maturityCapPercentage: 0.125e18
        });
}
