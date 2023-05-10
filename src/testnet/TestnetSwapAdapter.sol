// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IExchange} from "../interfaces/IExchange.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {AmountsMath} from "../lib/AmountsMath.sol";
import {TestnetToken} from "../testnet/TestnetToken.sol";

contract TestnetSwapAdapter is IExchange, Ownable {
    using AmountsMath for uint256;

    IPriceOracle internal priceOracle;

    constructor(address _priceOracle) Ownable() {
        priceOracle = IPriceOracle(_priceOracle);
    }

    function changePriceOracle(address oracle) external onlyOwner {
        priceOracle = IPriceOracle(oracle);
    }

    function getSwapAmount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint) {
        return _getAmountOut(tokenIn, tokenOut, amountIn);
    }

    function _getAmountOut(address tokenIn, address TokenOut, uint amountIn) internal view returns (uint) {
        uint tokenInDecimals = ERC20(tokenIn).decimals();
        uint TokenOutDecimals = ERC20(TokenOut).decimals();
        uint TokenOutPrice = priceOracle.getPrice(tokenIn, TokenOut);

        return amountIn.wmul(TokenOutPrice).wdiv(10**tokenInDecimals).wmul(10**TokenOutDecimals);
    }

    // @inheritdoc IExchange
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        TestnetToken(tokenIn).burn(address(this), amountIn);
        amountOut = _getAmountOut(tokenIn, tokenOut, amountIn);
        TestnetToken(tokenOut).mint(msg.sender, amountOut);
    }
}
