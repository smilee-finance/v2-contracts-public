// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.15;

// import {ERC20} from "@OpenZeppelin/contracts/token/ERC20/ERC20.sol";
// import {IPriceOracle} from "../swap/IPriceOracle.sol";
// import {ISwapAdapter} from "../swap/ISwapAdapter.sol";
// import {TestnetToken} from "../testnet/TestnetToken.sol";
// import {AmountsMath} from "../lib/AmountsMath.sol";
// import {AdminAccess} from "../lib/AdminAccess.sol";

// contract TestnetSwapAdapter is ISwapAdapter, AdminAccess {
//     using AmountsMath for uint256;

//     IPriceOracle internal priceOracle;

//     constructor(address _priceOracle) AdminAccess(msg.sender) {
//         priceOracle = IPriceOracle(_priceOracle);
//     }

//     function changePriceOracle(address oracle) external onlyAdmin {
//         priceOracle = IPriceOracle(oracle);
//     }

//     function getSwapAmount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint) {
//         return getAmountOut(tokenIn, tokenOut, amountIn);
//     }

//     function getAmountOut(address tokenIn, address TokenOut, uint amountIn) internal view returns (uint) {
//         uint tokenInDecimals = ERC20(tokenIn).decimals();
//         uint TokenOutDecimals = ERC20(TokenOut).decimals();
//         uint TokenOutPrice = priceOracle.getPrice(tokenIn, TokenOut);

//         return amountIn.wmul(TokenOutPrice).wdiv(10**tokenInDecimals).wmul(10**TokenOutDecimals);
//     }

//     // @inheritdoc ISwapAdapter
//     function swap(
//         address tokenIn,
//         address tokenOut,
//         uint256 amountIn
//     ) external returns (uint256 amountOut) {
//         ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
//         TestnetToken(tokenIn).burn(address(this), amountIn);
//         amountOut = getAmountOut(tokenIn, tokenOut, amountIn);
//         TestnetToken(tokenOut).mint(msg.sender, amountOut);
//     }
// }
