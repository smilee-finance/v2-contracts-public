// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";

/// @dev everything is expressed in Wad (18 decimals)
contract MarketOracle is IMarketOracle, Ownable {

    struct OracleValue {
        uint256 value;
        uint256 lastUpdate;
    }

    // ToDo: review
    OracleValue internal _iv;
    OracleValue internal _rfRate;

    event ChangedIV(uint256 value, uint256 oldValue);
    event ChangedRFR(uint256 value, uint256 oldValue);

    constructor() Ownable() {
        // TBD: review as we change the storage
        setImpliedVolatility(0.5e18); // 50 %
        setRiskFreeRate(0.03e18);     //  3 %
    }

    /// @inheritdoc IMarketOracle
    function getImpliedVolatility(
        address token0,
        address token1,
        uint256 strikePrice,
        uint256 frequency
    ) external view returns (uint256 iv) {
        token0;
        token1;
        strikePrice;
        frequency;

        iv = _iv.value;
    }

    function setImpliedVolatility(uint256 percentage) public onlyOwner {
        uint256 old = _iv.value;

        _iv.value = percentage;
        _iv.lastUpdate = block.timestamp;

        emit ChangedIV(percentage, old);
    }

    // ToDo: change as the rate may be negative
    // TBD: only accept the stable coin token
    /// @inheritdoc IMarketOracle
    function getRiskFreeRate(
        address token0,
        address token1
    ) external view returns (uint256 rate) {
        token0;
        token1;

        rate = _rfRate.value;
    }

    function setRiskFreeRate(uint256 percentage) public onlyOwner {
        uint256 old = _rfRate.value;

        _rfRate.value = percentage;
        _rfRate.lastUpdate = block.timestamp;

        emit ChangedRFR(percentage, old);
    }
}
