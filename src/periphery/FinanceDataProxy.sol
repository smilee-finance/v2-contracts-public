// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IFinanceIGData} from "@project/interfaces/IFinanceIGData.sol";
import {IPriceOracle} from "@project/interfaces/IPriceOracle.sol";
import {FinanceIGDelta} from "@project/lib/FinanceIGDelta.sol";
import {FinanceParameters} from "@project/lib/FinanceIG.sol";
import {AddressProvider} from "@project/AddressProvider.sol";

contract FinanceDataProxy {
    AddressProvider private _ap;

    constructor(address ap_) {
        _ap = AddressProvider(ap_);
    }

    /**
       Get delta hedge percentages of bull and bear for a trade. 
       @notice Made for monitoring purpose. 
       @param ig The IG involved in a trade.
       @return igDBull 
       @return igDBear 
     */
    function getDeltaHedgePercentages(address ig) external view returns (int256 igDBull, int256 igDBear) {
        IFinanceIGData igData = IFinanceIGData(ig);
        FinanceParameters memory financeParameters = igData.financeParameters();
        IPriceOracle po = IPriceOracle(_ap.priceOracle());
        FinanceIGDelta.Parameters memory params = FinanceIGDelta.Parameters(
            financeParameters.currentStrike,
            financeParameters.kA,
            financeParameters.kB,
            po.getPrice(igData.sideToken(), igData.baseToken()),
            financeParameters.theta
        );
        return FinanceIGDelta.deltaHedgePercentages(params);
    }
}
