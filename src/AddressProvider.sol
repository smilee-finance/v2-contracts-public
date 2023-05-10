// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// TBD: merge with Registry.sol
contract AddressProvider is Ownable {

    address public exchangeAdapter;
    address public priceOracle;

    constructor() Ownable() {}

    function setExchangeAdapter(address exchangeAdapter_) public onlyOwner {
        exchangeAdapter = exchangeAdapter_;
    }

    function setPriceOracle(address priceOracle_) public onlyOwner {
        priceOracle = priceOracle_;
    }
}
