// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";

contract UniswapPriceOracle is IPriceOracle {
    using AmountsMath for uint;

    IUniswapV3Factory _factory;
    address _referenceToken;

    uint24 constant _FEE = 500; // 0.05%

    error AddressZero();
    error TokenNotSupported();
    error PriceZero();
    error PriceTooHigh();

    constructor(address referenceToken, address factory) {
        _zeroAddressCheck(referenceToken);

        _referenceToken = referenceToken;
        _factory = IUniswapV3Factory(factory);
    }

    // @inheritdoc IPriceOracle
    function priceDecimals() public view override returns (uint decimals) {
        decimals = ERC20(_referenceToken).decimals();
    }

    // @inheritdoc IPriceOracle
    function getTokenPrice(address token) public view returns (uint) {
        _zeroAddressCheck(token);

        if (token == _referenceToken) {
            return 10 ** priceDecimals();
        }

        return _calculatePriceFromLiquidity(token, _referenceToken);
    }

    // @inheritdoc IPriceOracle
    function getPrice(address token0, address token1) external view returns (uint256) {
        return _calculatePriceFromLiquidity(token0, token1);
    }

    /// @notice Return token0 price in token1
    function _calculatePriceFromLiquidity(address token0, address token1) private view returns (uint256) {
        IUniswapV3Pool pool = _getPool(token0, token1);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint8 poolToken0Decimal = ERC20(pool.token0()).decimals();
        uint8 poolToken1Decimal = ERC20(pool.token1()).decimals();

        uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);

        price = price.wmul(10 ** poolToken0Decimal).wdiv(1 << 192);

        if (token0 == pool.token0()) {
            return price;
        } else {
            return 10 ** (poolToken0Decimal + poolToken1Decimal) / price;
        }
    }

    function _getPool(address token0, address token1) private view returns (IUniswapV3Pool pool) {
        pool = IUniswapV3Pool(_factory.getPool(token0, token1, _FEE));
    }

    /**
        @notice Revert if token is the zero address.
        @param token Address to check
     */
    function _zeroAddressCheck(address token) private pure {
        if (token == address(0)) {
            revert AddressZero();
        }
    }
}
