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

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    /// @dev index is computed in _getImpliedVolatility
    mapping(bytes32 => OracleValue) internal _impliedVolatility;
    /// @dev index is the base token address
    mapping(address => OracleValue) internal _riskFreeRate;

    error OutOfAllowedRange();

    event ChangedIV(address indexed token0, address indexed token1, uint256 frequency, uint256 value, uint256 oldValue);
    event ChangedRFR(address indexed token, uint256 value, uint256 oldValue);

    constructor() AccessControl() {
        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    function _getImpliedVolatility(
        address baseToken,
        address sideToken,
        uint256 timeWindow
    ) internal view returns (OracleValue storage) {
        bytes32 index = keccak256(abi.encodePacked(baseToken, sideToken, timeWindow));
        return _impliedVolatility[index];
    }

    /// @inheritdoc IMarketOracle
    function getImpliedVolatility(
        address token0,
        address token1,
        uint256 strikePrice,
        uint256 frequency
    ) external view returns (uint256 iv) {
        // NOTE: strike ignored by the current IG-only implementation.
        strikePrice;

        OracleValue storage iv_ = _getImpliedVolatility(token0, token1, frequency);

        if (iv_.lastUpdate == 0) {
            // NOTE: it's up to the deployer to set the right values; this is just a safe last resort.
            return 0.5e18;
        }

        iv = iv_.value;
    }

    function setImpliedVolatility(
        address token0,
        address token1,
        uint256 frequency,
        uint256 value
    ) public {
        _checkRole(ROLE_ADMIN);
        if (value < 0.01e18 || value > 10e18) {
            revert OutOfAllowedRange();
        }

        OracleValue storage iv_ = _getImpliedVolatility(token0, token1, frequency);

        uint256 old = iv_.value;
        iv_.value = value;
        iv_.lastUpdate = block.timestamp;

        emit ChangedIV(token0, token1, frequency, value, old);
    }

    function getImpliedVolatilityLastUpdate(
        address token0,
        address token1,
        uint256 frequency
    ) external view returns (uint256 lastUpdate) {
        OracleValue storage iv_ = _getImpliedVolatility(token0, token1, frequency);
        lastUpdate = iv_.lastUpdate;
    }

    /// @inheritdoc IMarketOracle
    function getRiskFreeRate(address token0) external view returns (uint256 rate) {
        OracleValue storage rfr_ = _riskFreeRate[token0];

        if (rfr_.lastUpdate == 0) {
            // NOTE: it's up to the deployer to set the right values; this is just a safe last resort.
            return 0.03e18;
        }

        rate = rfr_.value;
    }

    function setRiskFreeRate(address token0, uint256 value) public {
        _checkRole(ROLE_ADMIN);
        if (value > 0.25e18) {
            revert OutOfAllowedRange();
        }

        OracleValue storage rfr_ = _riskFreeRate[token0];

        uint256 old = rfr_.value;
        rfr_.value = value;
        rfr_.lastUpdate = block.timestamp;

        emit ChangedRFR(token0, value, old);
    }

    function getRiskFreeRateLastUpdate(
        address token0
    ) external view returns (uint256 lastUpdate) {
        OracleValue storage rfr_ = _riskFreeRate[token0];
        lastUpdate = rfr_.lastUpdate;
    }
}
