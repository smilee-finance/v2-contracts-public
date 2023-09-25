// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";
import {AmountsMath} from "../../src/lib/AmountsMath.sol";

/**
    @title Mock oracle to test different situations (see SwapProviderRouter.t.sol)
    @dev Every operation is unchecked since it's only an helper contract for making tests
 */
contract MockPriceOracle is IPriceOracle {
    using AmountsMath for uint256;

    uint256 constant _DECIMALS = 18;

    mapping(address => uint256) private _prices;

    constructor() {}

    function setPrice(address token, uint256 price) external {
        _prices[token] = price;
    }

    /// @inheritdoc IPriceOracle
    function getTokenPrice(address token) external view returns (uint price) {
        return _prices[token];
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address token0, address token1) external view returns (uint) {
        uint price0 = _prices[token0];
        uint price1 = _prices[token1];
        return price0.wdiv(price1);
    }
}
