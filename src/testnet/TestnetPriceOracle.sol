// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IMarketOracle} from "../interfaces/IMarketOracle.sol";
import {AmountsMath} from "../lib/AmountsMath.sol";

struct OracleValue {
    uint256 value;
    uint256 lastUpdate;
}

/// @dev everything is expressed in Wad (18 decimals)
contract TestnetPriceOracle is IPriceOracle, IMarketOracle, Ownable {
    using AmountsMath for uint256;

    // IPriceOracle data:
    // @inheritdoc IPriceOracle
    address public referenceToken;
    mapping(address => OracleValue) internal _prices;

    // IMarketOracle data:
    OracleValue internal _iv;
    OracleValue internal _rfRate;

    error AddressZero();
    error TokenNotSupported();
    error PriceZero();
    error PriceTooHigh();

    constructor(address referenceToken_) Ownable() {
        referenceToken = referenceToken_;
        setTokenPrice(referenceToken, 1e18); // 1

        _iv.value = 0.5e18;      // 50 %
        _iv.lastUpdate = block.timestamp;
        _rfRate.value = 0.03e18; //  3 %
        _rfRate.lastUpdate = block.timestamp;
    }

    // ------------------------------------------------------------------------
    // IPriceOracle
    // ------------------------------------------------------------------------

    // NOTE: the price is with 18 decimals and is expected to be in referenceToken
    function setTokenPrice(address token, uint256 price) public onlyOwner {
        if (token == address(0)) {
            revert AddressZero();
        }

        // ToDo: review
        if (price > type(uint256).max / 1e18) {
            revert PriceTooHigh();
        }

        OracleValue storage price_ = _prices[token];
        price_.value = price;
        price_.lastUpdate = block.timestamp;
    }

    // @inheritdoc IPriceOracle
    function getTokenPrice(address token) public view returns (uint256) {
        if (token == address(0)) {
            revert AddressZero();
        }

        if (!_priceIsSet(token)) {
            revert TokenNotSupported();
        }

        OracleValue memory price = _prices[token];
        // TBD: revert if price is too old
        return price.value;
    }

    function _priceIsSet(address token) internal view returns (bool) {
        return _prices[token].lastUpdate > 0;
    }

    // @inheritdoc IPriceOracle
    function getPrice(address token0, address token1) external view returns (uint256) {
        uint256 token0Price = getTokenPrice(token0);
        uint256 token1Price = getTokenPrice(token1);

        if (token1Price == 0) {
            // TBD: improve error
            revert PriceZero();
        }

        return token0Price.wdiv(token1Price);
    }

    // ------------------------------------------------------------------------
    // IMarketOracle
    // ------------------------------------------------------------------------

    // @inheritdoc IMarketOracle
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

    function setImpliedVolatility(uint256 percentage) external onlyOwner {
        _iv.value = percentage;
        _iv.lastUpdate = block.timestamp;
    }

    // @inheritdoc IMarketOracle
    function getRiskFreeRate(
        address token0,
        address token1
    ) external view returns (uint256 rate) {
        token0;
        token1;

        rate = _rfRate.value;
    }

    function setRiskFreeRate(uint256 percentage) external onlyOwner {
        _rfRate.value = percentage;
        _rfRate.lastUpdate = block.timestamp;
    }
}
