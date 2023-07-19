// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IMarketOracle} from "../interfaces/IMarketOracle.sol";
import {AmountsMath} from "../lib/AmountsMath.sol";

/// @dev everything is expressed in Wad (18 decimals)
contract TestnetPriceOracle is IPriceOracle, IMarketOracle, Ownable {
    using AmountsMath for uint;

    address referenceToken;
    mapping(address => uint) tokenPrices;
    mapping(address => bool) priceSet;

    error AddressZero();
    error TokenNotSupported();
    error PriceZero();
    error PriceTooHigh();

    constructor(address referenceToken_) Ownable() {
        if (referenceToken_ == address(0)) {
            revert AddressZero();
        }
        referenceToken = referenceToken_;
    }

    // NOTE: the price is with 18 decimals and is expected to be in USD
    function setTokenPrice(address token, uint price) external onlyOwner {
        if (token == address(0)) {
            revert AddressZero();
        }

        // TODO fix
        if (price > type(uint256).max / 1e18) {
            revert PriceTooHigh();
        }

        tokenPrices[token] = price;
        priceSet[token] = true;
    }

    function getTokenPrice(address token) public view returns (uint) {
        if (token == address(0)) {
            revert AddressZero();
        }

        if (token == referenceToken && !priceSet[referenceToken]) {
            return 1e18;
        }

        if (!priceSet[token]) {
            revert TokenNotSupported();
        }

        return tokenPrices[token];
    }

    // @inheritdoc IPriceOracle
    function getPrice(address token0, address token1) external view returns (uint) {
        uint token0Price = getTokenPrice(token0);
        uint token1Price = getTokenPrice(token1);

        if (token1Price == 0) {
            revert PriceZero();
        }

        return token0Price.wdiv(token1Price);
    }

    // ToDo: add setter
    function getImpliedVolatility(
        address token0,
        address token1,
        uint256 strikePrice,
        uint256 frequency
    ) external pure returns (uint256 iv) {
        token0;
        token1;
        strikePrice;
        frequency;
        return 5e17; // 0.5
    }

    // ToDo: add setter
    function getRiskFreeRate(address token0, address token1) external pure returns (uint256 rate) {
        token0;
        token1;
        return 3e16; // 0.03 == 3%
    }
}
