// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IQuoter} from "@uniswap/v3-periphery/interfaces/IQuoter.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import {Path} from "./lib/Path.sol";
import {IExchange} from "./interfaces/IExchange.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";

contract UniswapExchange is IExchange, Ownable {
    using Path for bytes;

    IPriceOracle internal _priceOracle;
    ISwapRouter internal immutable _swapRouter;
    IUniswapV3Factory internal immutable _factory;

    address internal immutable _baseToken;

    // Fees for LP Single
    uint24 constant _FEE = 500; // 0.05% // Got from Uniswap
    uint256 constant _SLIPPAGE = 500; // 5%
    // TBD: Is SQRTPRICELIMITX96 really 0?
    uint160 private constant _SQRTPRICELIMITX96 = 0;

    struct SwapPath {
        bool exists;
        bytes path; // Bytes of the path, structured in abi.encodePacked(TOKEN1, POOL_FEE, TOKEN2, POOL_FEE_1,....)
    }

    // bytes32 => Hash of tokenIn and tokenOut concatenated
    mapping(bytes32 => SwapPath) private _swapPaths;

    error AddressZero();
    error PathNotValid();
    error PathLengthNotValid();
    error PoolDoesNotExist();

    constructor(address swapRouter, address baseToken, address factory, address priceOracle) Ownable() {
        _swapRouter = ISwapRouter(swapRouter);
        _baseToken = baseToken;
        _factory = IUniswapV3Factory(factory);
        _priceOracle = IPriceOracle(priceOracle);
    }

    function setPriceOracle(address priceOracle) public onlyOwner {
        _zeroAddressCheck(priceOracle);
        _priceOracle = IPriceOracle(priceOracle);
    }

    /**
        Check if the path is valid and insert it into the map of the paths
        @param path A path to insert into a map
        @param tokenIn The start token address of the path 
        @param tokenOut The end token address of the path 
     */
    function setSwapPath(bytes memory path, address tokenIn, address tokenOut) public onlyOwner {
        if (_checkPath(path, tokenIn, tokenOut)) {
            SwapPath memory swapPath = SwapPath(true, path);
            _swapPaths[_encodePath(tokenIn, tokenOut)] = swapPath;
        } else {
            revert PathNotValid();
        }
    }

    /// @inheritdoc IExchange
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) public returns (uint256 tokenOutAmount) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(_swapRouter), amountIn);

        uint256 price = _priceOracle.getPrice(tokenIn, tokenOut);
        uint256 amountMinimumOut = (price * amountIn) / 10 ** ERC20(tokenIn).decimals();
        amountMinimumOut = (amountMinimumOut * (10000 - _SLIPPAGE)) / 10000;

        if (_existsPath(tokenIn, tokenOut)) {
            tokenOutAmount = _swapInMulti(_getPath(tokenIn, tokenOut), amountIn, amountMinimumOut);
        } else {
            tokenOutAmount = _swapInSingle(tokenIn, tokenOut, amountIn, amountMinimumOut);
        }
    }

    /// @inheritdoc IExchange
    function swapOut(address tokenIn, address tokenOut, uint256 amountOut) public returns (uint256 amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        uint256 price = _priceOracle.getPrice(tokenOut, tokenIn);
        uint256 amountMaximumIn = (price * amountOut) / 10 ** ERC20(tokenOut).decimals();
        amountMaximumIn = (amountMaximumIn * (10000 + _SLIPPAGE)) / 10000;

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountMaximumIn);
        TransferHelper.safeApprove(tokenIn, address(_swapRouter), amountMaximumIn);

        if (_existsPath(tokenIn, tokenOut)) {
            amountIn = _swapOutMulti(_getPath(tokenIn, tokenOut), amountOut, amountMaximumIn);
        } else {
            amountIn = _swapOutSingle(tokenIn, tokenOut, amountOut, amountMaximumIn);
        }

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < amountMaximumIn) {
            uint256 amountToReturn = amountMaximumIn - amountIn;
            TransferHelper.safeApprove(tokenIn, address(_swapRouter), 0);
            TransferHelper.safeTransfer(tokenIn, msg.sender, amountToReturn);
        }
    }

    /// @inheritdoc IExchange
    function getOutputAmount(address tokenIn, address tokenOut, uint256 amountIn) public view override returns (uint) {
        return (_priceOracle.getPrice(tokenIn, tokenOut) * amountIn) / 10 ** ERC20(tokenIn).decimals();
    }

    /// @inheritdoc IExchange
    function getInputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) public view override returns (uint amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        uint256 price = _priceOracle.getPrice(tokenOut, tokenIn);
        amountIn = (price * amountOut) / 10 ** ERC20(tokenOut).decimals();
    }

    /// @notice Swap in a pair using the naive pool
    function _swapInSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountMinimumOut
    ) private returns (uint256 tokenOutAmount) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            tokenIn,
            tokenOut,
            _FEE,
            msg.sender,
            block.timestamp + 60,
            amountIn,
            amountMinimumOut,
            _SQRTPRICELIMITX96
        );

        tokenOutAmount = _swapRouter.exactInputSingle(params);
    }

    /// @notice Swap in a pair using the path of tokenIn tokenOut
    function _swapInMulti(
        bytes memory path,
        uint256 amountIn,
        uint256 amountMinimumOut
    ) private returns (uint256 tokenOutAmount) {
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams(
            path,
            msg.sender,
            block.timestamp + 60,
            amountIn,
            amountMinimumOut
        );

        tokenOutAmount = _swapRouter.exactInput(params);
    }

    /// @notice Swap in a pair using the naive pool
    function _swapOutSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountMaximumIn
    ) public returns (uint256 amountIn) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
            tokenIn,
            tokenOut,
            _FEE,
            msg.sender,
            block.timestamp,
            amountOut,
            amountMaximumIn,
            _SQRTPRICELIMITX96
        );

        amountIn = _swapRouter.exactOutputSingle(params);
    }

    /// /@notice Swap out a pair using the reversed path of tokenIn tokenOut
    function _swapOutMulti(
        bytes memory path,
        uint256 amountOut,
        uint256 amountMaximumIn
    ) public returns (uint256 amountIn) {
        path = _reversePath(path);
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams(
            path,
            msg.sender,
            block.timestamp,
            amountOut,
            amountMaximumIn
        );

        amountIn = _swapRouter.exactOutput(params);
    }

    function _getPool(address token0, address token1, uint24 fee) private view returns (IUniswapV3Pool pool) {
        address addressPool = _factory.getPool(token0, token1, fee);
        if (addressPool == address(0)) {
            revert PoolDoesNotExist();
        }
        pool = IUniswapV3Pool(addressPool);
    }

    /// @notice Checks if the tokenIn and tokenOut in the swapPath matches the validTokenIn and validTokenOut specified.
    function _checkPath(
        bytes memory swapPath,
        address validTokenIn,
        address validTokenOut
    ) internal view returns (bool isValidPath) {
        address tokenIn;
        address tokenOut;
        uint24 fee;

        if (swapPath.length < 43 || swapPath.length > 66) {
            revert PathLengthNotValid();
        }

        // Decode the first pool in path
        (tokenIn, tokenOut, fee) = swapPath.decodeFirstPool();

        _getPool(tokenIn, tokenOut, fee);

        while (swapPath.hasMultiplePools()) {
            // Remove the first pool from path
            swapPath = swapPath.skipToken();
            // Check the next pool and update tokenOut
            (, tokenOut, fee) = swapPath.decodeFirstPool();

            _getPool(tokenIn, tokenOut, fee);
        }

        return tokenIn == validTokenIn && tokenOut == validTokenOut;
    }

    function _existsPath(address tokenIn, address tokenOut) private view returns (bool) {
        return _swapPaths[_encodePath(tokenIn, tokenOut)].exists;
    }

    function _getPath(address tokenIn, address tokenOut) private view returns (bytes memory) {
        return _swapPaths[_encodePath(tokenIn, tokenOut)].path;
    }

    /**
        @notice Encode path for key of swapPath map.
        @param tokenIn The address of tokenIn of the path
        @param tokenOut The address of tokenOut of the path
        @return pathKey The hashed path key
     */
    function _encodePath(address tokenIn, address tokenOut) private pure returns (bytes32 pathKey) {
        pathKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    /**
        @notice Reverse Path to be used for swap-out MultiHop
        @param path A path to reverse
     */
    function _reversePath(bytes memory path) internal view returns (bytes memory) {
        address tokenA;
        address tokenB;
        uint24 fee;

        uint256 numPoolsPath = path.numPools();
        bytes[] memory singlePaths = new bytes[](numPoolsPath);

        // path := <token_0, fee_01, token_1, fee_12, token_2, ...>
        for (uint i = 0; i < numPoolsPath; i++) {
            (tokenA, tokenB, fee) = path.decodeFirstPool();
            singlePaths[i] = abi.encodePacked(tokenB, fee, tokenA);
            path = path.skipToken();
        }

        bytes memory reversedPath;
        bytes memory fullyReversedPath;
        // Get last element and create the first reversedPath
        (tokenA, tokenB, fee) = singlePaths[numPoolsPath - 1].decodeFirstPool();
        reversedPath = bytes.concat(bytes20(tokenA), bytes3(fee), bytes20(tokenB));
        fullyReversedPath = bytes.concat(fullyReversedPath, reversedPath);

        for (uint i = numPoolsPath - 1; i > 0; i--) {
            (, tokenB, fee) = singlePaths[i - 1].decodeFirstPool();
            // TokenA is just inserted as tokenB in the last sub path
            reversedPath = bytes.concat(bytes3(fee), bytes20(tokenB));
            fullyReversedPath = bytes.concat(fullyReversedPath, reversedPath);
        }

        return fullyReversedPath;
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
