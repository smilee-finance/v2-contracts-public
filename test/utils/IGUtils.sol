// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {MarketOracle} from "../../src/MarketOracle.sol";
import {IG} from "../../src/IG.sol";
import {TokenUtils} from "./TokenUtils.sol";
import {Utils} from "./Utils.sol";
import {FinanceParameters} from "../../src/lib/FinanceIG.sol";

library IGUtils {
    // ToDo: Add createIg

    function rollEpoch(AddressProvider ap, IG ig, address admin, bool additionalSecond, Vm vm) external{
        MarketOracle marketOracle = MarketOracle(ap.marketOracle());
        uint256 iv = marketOracle.getImpliedVolatility(ig.baseToken(), ig.sideToken(), 0, ig.getEpoch().frequency);

        Utils.skipDay(additionalSecond, vm);

        vm.startPrank(admin);
        marketOracle.setImpliedVolatility(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, iv);
        ig.rollEpoch();
        vm.stopPrank();
    }


    function debugStateIG(IG ig) public view {
        (
            uint256 maturity,
            uint256 currentStrike,
            , /* Amount initialLiquidity */ 
            uint256 kA,
            uint256 kB,
            uint256 theta,
            int256 limSup,
            int256 limInf,
            , /* TimeLockedFinanceParameters timeLocked */
            uint256 sigmaZero,
            /* internalVolatilityParameters */
        ) = ig.financeParameters();
        console.log("----------IG STATE----------");
        console.log("maturity", maturity);
        console.log("currentStrike", currentStrike);
        // console.log("initialLiquidity", initialLiquidity);
        console.log("kA", kA);
        console.log("kB", kB);
        console.log("theta", theta);
        console.log("limSup");
        console.logInt(limSup);
        console.log("limInf");
        console.logInt(limInf);
        // console.log("timeLocked", timeLocked);
        console.log("sigmaZero", sigmaZero);
        console.log("----------------------------");
    }

    /// @dev Function used to skip coverage on this file
    function testCoverageSkip() public view {}
}
