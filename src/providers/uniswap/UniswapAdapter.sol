// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {ISwapAdapter} from "../../interfaces/ISwapAdapter.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Path} from "./lib/Path.sol";

/**
    @title UniswapAdapter
    @notice A simple adapter to connect with uniswap pools.

    By default tries to swap <tokenIn, tokenOut> on the direct pool with 0.05% fees.
    If a custom path is set for the the pair <tokenIn, tokenOut> uses that one.
    A custom path can be set only if it contains multiple pools.
 */
contract UniswapAdapter is ISwapAdapter, Ownable {
    using Path for bytes;

    uint256 constant _MIN_PATH_LEN = 43;
    uint256 constant _MAX_PATH_LEN = 66;
    uint256 constant _TIME_DELAY = 30;

    // Fees for LP Single
    uint24 constant _DEFAULT_FEE = 500; // 0.05% (hundredths of basis points)
    // TBD: Is SQRTPRICELIMITX96 really 0?
    uint160 private constant _SQRTPRICELIMITX96 = 0;

    // Ref. to the Uniswap router to make swaps
    ISwapRouter internal immutable _swapRouter;
    // Ref. to the Uniswap factory to find pools
    IUniswapV3Factory internal immutable _factory;

    struct SwapPath {
        bool exists;
        bytes data; // Bytes of the path, structured in abi.encodePacked(TOKEN1, POOL_FEE, TOKEN2, POOL_FEE_1,....)
        bytes reverseData; // Bytes of the reverse path for swapOut multihop (https://docs.uniswap.org/contracts/v3/guides/swaps/multihop-swaps)
    }

    // bytes32 => Hash of tokenIn and tokenOut concatenated
    mapping(bytes32 => SwapPath) private _swapPaths;

    error AddressZero();
    error PathNotValid();
    error PathNotSet();
    error PathLengthNotValid();
    error PoolDoesNotExist();
    error NotImplemented();

    constructor(address swapRouter, address factory) Ownable() {
        _swapRouter = ISwapRouter(swapRouter);
        _factory = IUniswapV3Factory(factory);
    }

    /**
        @notice Checks if the path is valid and inserts it into the map
        @param path Path data to insert into a map
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
     */
    function setPath(bytes memory path, address tokenIn, address tokenOut) public onlyOwner {
        if (_checkPath(path, tokenIn, tokenOut)) {
            bytes memory reversePath = _reversePath(path);
            SwapPath memory swapPath = SwapPath(true, path, reversePath);
            _swapPaths[_encodePair(tokenIn, tokenOut)] = swapPath;
        } else {
            revert PathNotValid();
        }
    }

    /**
        @notice Returns the path used by the contract to swap the given pair
        @dev May revert if no path is set and default pool does not exist
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param reversed True if you want to see the reversed path
        @return path The custom path set for the pair or the default path if it exists
     */
    function getPath(address tokenIn, address tokenOut, bool reversed) public view returns (bytes memory path) {
        if (_swapPaths[_encodePair(tokenIn, tokenOut)].exists) {
            if (reversed) {
                return _swapPaths[_encodePair(tokenIn, tokenOut)].reverseData;
            }
            return _swapPaths[_encodePair(tokenIn, tokenOut)].data;
        } else {
            // return default path
            path = reversed ? abi.encodePacked(tokenOut, _DEFAULT_FEE, tokenIn) : path = abi.encodePacked(
                tokenIn,
                _DEFAULT_FEE,
                tokenOut
            );
            _checkPath(path, tokenOut, tokenIn);
            return path;
        }
    }

    /// @inheritdoc ISwapAdapter
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) public returns (uint256 tokenOutAmount) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(_swapRouter), amountIn);

        SwapPath storage path = _swapPaths[_encodePair(tokenIn, tokenOut)];
        tokenOutAmount = path.exists ? _swapInPath(path.data, amountIn) : _swapInSingle(tokenIn, tokenOut, amountIn);
    }

    /// @inheritdoc ISwapAdapter
    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 preApprovedInput
    ) public returns (uint256 amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), preApprovedInput);
        TransferHelper.safeApprove(tokenIn, address(_swapRouter), preApprovedInput);

        SwapPath storage path = _swapPaths[_encodePair(tokenIn, tokenOut)];
        amountIn = path.exists
            ? _swapOutPath(path.reverseData, amountOut, preApprovedInput)
            : _swapOutSingle(tokenIn, tokenOut, amountOut, preApprovedInput);

        // refund difference to caller
        if (amountIn < preApprovedInput) {
            uint256 amountToReturn = preApprovedInput - amountIn;
            TransferHelper.safeApprove(tokenIn, address(_swapRouter), 0);
            TransferHelper.safeTransfer(tokenIn, msg.sender, amountToReturn);
        }
    }

    /// @dev Swap tokens given the input amount using the direct pool with default fee
    function _swapInSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private returns (uint256 tokenOutAmount) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            tokenIn,
            tokenOut,
            _DEFAULT_FEE,
            msg.sender,
            block.timestamp + _TIME_DELAY,
            amountIn,
            0,
            _SQRTPRICELIMITX96
        );

        tokenOutAmount = _swapRouter.exactInputSingle(params);
    }

    /// @dev Swap tokens given the input amount using the saved path
    function _swapInPath(bytes memory path, uint256 amountIn) private returns (uint256 tokenOutAmount) {
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams(
            path,
            msg.sender,
            block.timestamp + _TIME_DELAY,
            amountIn,
            0
        );

        tokenOutAmount = _swapRouter.exactInput(params);
    }

    /// @dev Swap tokens given the output amount using the direct pool with default fee
    function _swapOutSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountMaximumIn
    ) private returns (uint256 amountIn) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
            tokenIn,
            tokenOut,
            _DEFAULT_FEE,
            msg.sender,
            block.timestamp + _TIME_DELAY,
            amountOut,
            amountMaximumIn,
            _SQRTPRICELIMITX96
        );

        amountIn = _swapRouter.exactOutputSingle(params);
    }

    /// @dev Swap tokens given the output amount using the saved path
    function _swapOutPath(
        bytes memory path,
        uint256 amountOut,
        uint256 amountMaximumIn
    ) private returns (uint256 amountIn) {
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams(
            path,
            msg.sender,
            block.timestamp + _TIME_DELAY,
            amountOut,
            amountMaximumIn
        );

        amountIn = _swapRouter.exactOutput(params);
    }

    /// @dev Returns the IUniswapV3Pool with given parameters, reverts if it does not exist
    function _getPool(address token0, address token1, uint24 fee) private view returns (IUniswapV3Pool pool) {
        address poolAddr = _factory.getPool(token0, token1, fee);
        if (poolAddr == address(0)) {
            revert PoolDoesNotExist();
        }
        pool = IUniswapV3Pool(poolAddr);
    }

    /// @dev Checks if the tokenIn and tokenOut in the swapPath matches the validTokenIn and validTokenOut specified
    function _checkPath(
        bytes memory path,
        address validTokenIn,
        address validTokenOut
    ) private view returns (bool isValidPath) {
        address tokenIn;
        address tokenOut;
        uint24 fee;

        if (path.length < _MIN_PATH_LEN || path.length > _MAX_PATH_LEN) {
            revert PathLengthNotValid();
        }

        // Decode the first pool in path
        (tokenIn, tokenOut, fee) = path.decodeFirstPool();

        _getPool(tokenIn, tokenOut, fee);

        while (path.hasMultiplePools()) {
            // Remove the first pool from path
            path = path.skipToken();
            // Check the next pool and update tokenOut
            (, tokenOut, fee) = path.decodeFirstPool();

            _getPool(tokenIn, tokenOut, fee);
        }

        return tokenIn == validTokenIn && tokenOut == validTokenOut;
    }

    /// @dev Encodes the pair of token addresses into a unique bytes32 key
    function _encodePair(address tokenIn, address tokenOut) private pure returns (bytes32 key) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    /// @dev Reverses the given path (see multi hop swap-out)
    function _reversePath(bytes memory path) private pure returns (bytes memory) {
        address tokenA;
        address tokenB;
        uint24 fee;

        uint256 numPoolsPath = path.numPools();
        bytes[] memory singlePaths = new bytes[](numPoolsPath);

        // path := <token_0, fee_01, token_1, fee_12, token_2, ...>
        for (uint256 i = 0; i < numPoolsPath; i++) {
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

        for (uint256 i = numPoolsPath - 1; i > 0; i--) {
            (, tokenB, fee) = singlePaths[i - 1].decodeFirstPool();
            // TokenA is just inserted as tokenB in the last sub path
            reversedPath = bytes.concat(bytes3(fee), bytes20(tokenB));
            fullyReversedPath = bytes.concat(fullyReversedPath, reversedPath);
        }

        return fullyReversedPath;
    }

    /// @dev Reverts if the given address is not set.
    function _zeroAddressCheck(address token) private pure {
        if (token == address(0)) {
            revert AddressZero();
        }
    }
}