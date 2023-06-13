// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IExchange} from "../src/interfaces/IExchange.sol";
import {UniswapExchange} from "../src/providers/uniswap/UniswapExchange.sol";
import {UniswapPriceOracle} from "../src/providers/uniswap/UniswapPriceOracle.sol";

/**
 * @title UniwapEchangeTest
 * @notice The test suite must be runned forking arbitrum mainnet
 * TBD: Evaluate to use always the same block number during the fork
 */
contract UniswapExchangeTest is Test {
    UniswapExchange _uniswap;
    UniswapPriceOracle _priceOracle;

    IERC20 _tokenWBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20 _tokenWETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 _tokenUSDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    // The balance of the holders may change on each run of the test suite. 
    address constant _WETH_HOLDER = 0xC6d973B31BB135CaBa83cf0574c0347BD763ECc5;
    address constant _WBTC_HOLDER = 0x3B7424D5CC87dc2B670F4c99540f7380de3D5880;

    uint256 internal constant _SLIPPAGE_PERC = 10000; // 100%
    uint256 internal constant _SLIPPAGE = 500; // 5%

    constructor() {
        uint256 forkId = vm.createFork("https://arb-mainnet.g.alchemy.com/v2/KpB5mO_nzL6eYfzzx9bcBHq8oO8mjcx4");
        vm.selectFork(forkId);
        // ToDo: select block to fork

        _priceOracle = new UniswapPriceOracle(address(_tokenUSDC), 0x1F98431c8aD98523631AE4a59f267346ea31F984);

        _uniswap = new UniswapExchange(
            0xE592427A0AEce92De3Edee1F18E0157C05861564,
            address(_tokenUSDC),
            0x1F98431c8aD98523631AE4a59f267346ea31F984,
            address(_priceOracle)
        );

        // Set path WBTC - USDC: WBTC - WETH - USDC
        bytes memory path = abi.encodePacked(address(_tokenWBTC), uint24(500), address(_tokenWETH), uint24(500), address(_tokenUSDC));
        _uniswap.setSwapPath(path, address(_tokenWBTC), address(_tokenUSDC));
    }

    function testSwapInWBTCToWETH() public {
        _swapInTest(_tokenWBTC, _tokenWETH, _WBTC_HOLDER, 1 * 10 ** 8); // 1 WBTC
    }

    function testSwapOutWBTCToWETH() public {
        _swapOutTest(_tokenWBTC, _tokenWETH, _WBTC_HOLDER, 1 * 10 ** 18); // 1 WETH
    }

    function testSwapInWETHToWBTC() public {
        _swapInTest(_tokenWETH, _tokenWBTC, _WETH_HOLDER, 1 * 10 ** 18); // 1 ETH
    }

    function testSwapOutWETHToWBTC() public {
        _swapOutTest(_tokenWETH, _tokenWBTC, _WETH_HOLDER, 1 * 10 ** 8); // 1 WBTC
    }

    function testSwapInWETHtoUSDC() public {
        _swapInTest(_tokenWETH, _tokenUSDC, _WETH_HOLDER, 0.1 ether);
    }

    function testSwapOutWETHtoUSDC() public {
        _swapOutTest(_tokenWETH, _tokenUSDC, _WETH_HOLDER, 1000 * 10 ** 6); // 1000 USDC
    }

    function testSwapInWBTCtoUSDC() public {
        _swapInTest(_tokenWBTC, _tokenUSDC, _WBTC_HOLDER, 1 * 10 ** 8);
    }

    function testSwapOutWBTCtoUSDC() public {
        _swapOutTest(_tokenWBTC, _tokenUSDC, _WBTC_HOLDER, 1000 * 10 ** 6); // 1000 USDC
    }

    function _swapInTest(IERC20 tokenIn, IERC20 tokenOut, address tokenInHolder, uint256 amountTokenIntoSwap) private {
        uint256 tokenInBalanceBeforeSwap = tokenIn.balanceOf(tokenInHolder);
        uint256 tokenOutBalanceBeforeSwap = tokenOut.balanceOf(tokenInHolder);

        uint256 tokenOutSwappedAmount = _uniswap.getOutputAmount(
            address(tokenIn),
            address(tokenOut),
            amountTokenIntoSwap
        );

        vm.startPrank(tokenInHolder);
        tokenIn.approve(address(_uniswap), tokenIn.balanceOf(tokenInHolder));
        _uniswap.swapIn(address(tokenIn), address(tokenOut), amountTokenIntoSwap);
        vm.stopPrank();

        uint256 tokenInBalanceAfterSwap = tokenIn.balanceOf(tokenInHolder);
        uint256 tokenOutBalanceAfterSwap = tokenOut.balanceOf(tokenInHolder);

        uint256 tokenInSlippageDelta = ((amountTokenIntoSwap * (_SLIPPAGE_PERC + _SLIPPAGE)) / _SLIPPAGE_PERC) -
            amountTokenIntoSwap;
        uint256 tokenOutSlippageDelta = ((tokenOutSwappedAmount * (_SLIPPAGE_PERC + _SLIPPAGE)) / _SLIPPAGE_PERC) -
            tokenOutSwappedAmount;

        assertApproxEqAbs(
            tokenInBalanceAfterSwap,
            tokenInBalanceBeforeSwap - amountTokenIntoSwap,
            tokenInSlippageDelta
        );
        assertApproxEqAbs(
            tokenOutBalanceAfterSwap,
            tokenOutBalanceBeforeSwap + tokenOutSwappedAmount,
            tokenOutSlippageDelta
        );
    }

    function _swapOutTest(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address tokenInHolder,
        uint256 amountOutTokenOutWanted
    ) private {
        uint256 tokenInBalanceBeforeSwap = tokenIn.balanceOf(tokenInHolder);
        uint256 tokenOutBalanceBeforeSwap = tokenOut.balanceOf(tokenInHolder);

        uint256 tokenInToSwap = _uniswap.getInputAmount(address(tokenIn), address(tokenOut), amountOutTokenOutWanted);

        vm.startPrank(tokenInHolder);
        tokenIn.approve(address(_uniswap), tokenIn.balanceOf(tokenInHolder));
        _uniswap.swapOut(address(tokenIn), address(tokenOut), amountOutTokenOutWanted);
        vm.stopPrank();

        uint256 tokenInBalanceAfterSwap = tokenIn.balanceOf(tokenInHolder);
        uint256 tokenOutBalanceAfterSwap = tokenOut.balanceOf(tokenInHolder);

        uint256 tokenInSlippageDelta = ((tokenInToSwap * (_SLIPPAGE_PERC + _SLIPPAGE)) / _SLIPPAGE_PERC) -
            tokenInToSwap;
        uint256 tokenOutSlippageDelta = ((amountOutTokenOutWanted * (_SLIPPAGE_PERC + _SLIPPAGE)) / _SLIPPAGE_PERC) -
            amountOutTokenOutWanted;

        assertApproxEqAbs(tokenInBalanceAfterSwap, tokenInBalanceBeforeSwap - tokenInToSwap, tokenInSlippageDelta);
        assertApproxEqAbs(
            tokenOutBalanceAfterSwap,
            tokenOutBalanceBeforeSwap + amountOutTokenOutWanted,
            tokenOutSlippageDelta
        );
    }
}
