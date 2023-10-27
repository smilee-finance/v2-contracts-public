// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";

/// @dev everything is expressed in Wad (18 decimals)
contract MarketOracle is IMarketOracle, AccessControl {
    struct OracleValue {
        uint256 value;
        uint256 lastUpdate;
    }

    OracleValue internal _iv;
    OracleValue internal _rfRate;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    event ChangedIV(uint256 value, uint256 oldValue);
    event ChangedRFR(uint256 value, uint256 oldValue);

    constructor() AccessControl() {
        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);

        _grantRole(ROLE_ADMIN, msg.sender);
        setImpliedVolatility(0.5e18); // 50 %
        setRiskFreeRate(0.03e18); // 3 %
        _revokeRole(ROLE_ADMIN, msg.sender);
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

    function setImpliedVolatility(uint256 percentage) public {
        _checkRole(ROLE_ADMIN);

        uint256 old = _iv.value;

        _iv.value = percentage;
        _iv.lastUpdate = block.timestamp;

        emit ChangedIV(percentage, old);
    }

    /// @inheritdoc IMarketOracle
    function getRiskFreeRate(address token0, address token1) external view returns (uint256 rate) {
        token0;
        token1;

        rate = _rfRate.value;
    }

    function setRiskFreeRate(uint256 percentage) public {
        _checkRole(ROLE_ADMIN);
        uint256 old = _rfRate.value;

        _rfRate.value = percentage;
        _rfRate.lastUpdate = block.timestamp;

        emit ChangedRFR(percentage, old);
    }
}
