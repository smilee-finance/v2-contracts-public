// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {AmountsMath} from "../lib/AmountsMath.sol";

contract TestnetPriceOracle is IPriceOracle, Ownable {
    using AmountsMath for uint;

    address referenceToken;
    mapping(address => uint) tokenPrices;
    mapping(address => bool) priceSet;

    error TokenNotSupported();

    constructor(address _referenceToken) Ownable() {
        referenceToken = _referenceToken;
    }

    // @inheritdoc IPriceOracle
    function priceDecimals() public pure returns (uint decimals) {
        decimals = 18;
    }

    // NOTE: the price is with 18 decimals and is expected to be in USD
    function setTokenPrice(address token, uint price) external onlyOwner {
        if (token == address(0)) {
            revert TokenNotSupported();
        }
        // if (token == referenceToken) {
        //     revert TokenNotSupported();
        // }

        tokenPrices[token] = price;
        priceSet[token] = true;
    }

    function getTokenPrice(address token) public view returns (uint) {
        if (token == address(0)) {
            revert TokenNotSupported();
        }

        if (token == referenceToken && !priceSet[referenceToken]) {
            return 10**priceDecimals();
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
            // TBD: revert
            return type(uint).max;
        }

        return token0Price.wdiv(token1Price);
    }

}
