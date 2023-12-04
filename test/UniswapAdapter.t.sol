// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {IExchange} from "@project/interfaces/IExchange.sol";
import {UniswapAdapter} from "@project/providers/uniswap/UniswapAdapter.sol";

/**
    @title UniswapAdapterTest
    @dev The test suite must be runned forking arbitrum mainnet, so remember to
    set the RPC env variable
 */
contract UniswapAdapterTest is Test {
    UniswapAdapter _uniswap;
    address _admin;

    address constant _UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant _UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    IQuoterV2 _quoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    IERC20 constant _WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20 constant _WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 constant _USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    address constant _WETH_HOLDER = 0x940a7ed683A60220dE573AB702Ec8F789ef0A402;
    address constant _WBTC_HOLDER = 0x3B7424D5CC87dc2B670F4c99540f7380de3D5880;

    constructor() {
        uint256 forkId = vm.createFork(vm.rpcUrl("arbitrum_mainnet"), 100768497);
        vm.selectFork(forkId);

        _admin = address(0x1);
        vm.startPrank(_admin);
        _uniswap = new UniswapAdapter(_UNIV3_ROUTER, _UNIV3_FACTORY);
        _uniswap.grantRole(_uniswap.ROLE_ADMIN(), _admin);

        // Set single pool path for <WETH, USDC> to WETH -> USDC [0.3%]
        bytes memory wethUsdcPath = abi.encodePacked(address(_WETH), uint24(3000), address(_USDC));
        _uniswap.setPath(wethUsdcPath, address(_WETH), address(_USDC));

        // Set multi-pool path for <WBTC, USDC> to WBTC -> WETH [0.05%]-> USDC [0.05%]
        bytes memory wbtcUsdcPath = abi.encodePacked(
            address(_WBTC),
            uint24(500),
            address(_WETH),
            uint24(500),
            address(_USDC)
        );
        _uniswap.setPath(wbtcUsdcPath, address(_WBTC), address(_USDC));

        vm.stopPrank();
    }

    /// @dev Uses default pool (0.05%)
    function testSwapInWbtcWeth() public {
        _swapInTest(_WBTC, _WETH, _WBTC_HOLDER, 1e8); // 1 WBTC
    }

    /// @dev Uses default pool (0.05%)
    function testSwapInWethWbtc() public {
        _swapInTest(_WETH, _WBTC, _WETH_HOLDER, 1e18); // 1 ETH
    }

    /// @dev Uses custom path (single pool 0.3%)
    function testSwapInWethUsdc() public {
        _swapInTest(_WETH, _USDC, _WETH_HOLDER, 0.1e18);
    }

    /// @dev Uses custom path (multi pool WBTC 0.05% WETH 0.05% USDC)
    function testSwapInWbtcUsdc() public {
        _swapInTest(_WBTC, _USDC, _WBTC_HOLDER, 1e8);
    }

    /// @dev Uses default pool (0.05%)
    function testSwapOutWbtcWeth() public {
        _swapOutTest(_WBTC, _WETH, _WBTC_HOLDER, 1e18); // 1 WETH
    }

    /// @dev Uses default pool (0.05%)
    function testSwapOutWethWbtc() public {
        _swapOutTest(_WETH, _WBTC, _WETH_HOLDER, 1e8); // 1 WBTC
    }

    /// @dev Uses custom path (single pool 0.3%)
    function testSwapOutWethUsdc() public {
        _swapOutTest(_WETH, _USDC, _WETH_HOLDER, 1_000e6); // 1000 USDC
    }

    /// @dev Uses custom path (multi pool WBTC 0.05% WETH 0.05% USDC)
    function testSwapOutWbtcUsdc() public {
        _swapOutTest(_WBTC, _USDC, _WBTC_HOLDER, 1_000e6); // 1000 USDC
    }

    function _swapInTest(IERC20 tokenIn, IERC20 tokenOut, address holder, uint256 amountIn) private {
        uint256 tokenInBalanceBefore = tokenIn.balanceOf(holder);
        uint256 tokenOutBalanceBefore = tokenOut.balanceOf(holder);

        uint256 expectedAmountOut = _quoteInput(address(tokenIn), address(tokenOut), amountIn);
        // uint256 expectedAmountOut2 = _uniswap.getOutputAmount(address(tokenIn), address(tokenOut), amountIn);

        vm.startPrank(holder);
        tokenIn.approve(address(_uniswap), tokenIn.balanceOf(holder));
        _uniswap.swapIn(address(tokenIn), address(tokenOut), amountIn);
        vm.stopPrank();

        uint256 tokenInBalanceAfter = tokenIn.balanceOf(holder);
        uint256 tokenOutBalanceAfter = tokenOut.balanceOf(holder);

        assertEq(tokenInBalanceAfter, tokenInBalanceBefore - amountIn);
        assertEq(tokenOutBalanceAfter, tokenOutBalanceBefore + expectedAmountOut);
    }

    function _swapOutTest(IERC20 tokenIn, IERC20 tokenOut, address holder, uint256 amountOut) private {
        uint256 tokenInBalanceBefore = tokenIn.balanceOf(holder);
        uint256 tokenOutBalanceBefore = tokenOut.balanceOf(holder);

        uint256 expectedAmountIn = _quoteOutput(address(tokenIn), address(tokenOut), amountOut);
        // uint256 expectedAmountIn2 = _uniswap.getInputAmount(address(tokenIn), address(tokenOut), amountOut);

        vm.startPrank(holder);
        tokenIn.approve(address(_uniswap), tokenIn.balanceOf(holder));
        _uniswap.swapOut(address(tokenIn), address(tokenOut), amountOut, expectedAmountIn);
        vm.stopPrank();

        uint256 tokenInBalanceAfter = tokenIn.balanceOf(holder);
        uint256 tokenOutBalanceAfter = tokenOut.balanceOf(holder);

        assertEq(tokenInBalanceAfter, tokenInBalanceBefore - expectedAmountIn);
        assertEq(tokenOutBalanceAfter, tokenOutBalanceBefore + amountOut);
    }

    function _quoteInput(address tokenIn, address tokenOut, uint256 amountIn) private returns (uint256 amountOut) {
        bytes memory path = _uniswap.getPath(tokenIn, tokenOut, false);
        (amountOut, , , ) = _quoter.quoteExactInput(path, amountIn);
    }

    function _quoteOutput(address tokenIn, address tokenOut, uint256 amountOut) private returns (uint256 amountIn) {
        bytes memory path = _uniswap.getPath(tokenIn, tokenOut, true);
        (amountIn, , , ) = _quoter.quoteExactOutput(path, amountOut);
    }
}
