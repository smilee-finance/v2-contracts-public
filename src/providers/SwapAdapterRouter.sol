// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IExchange} from "../interfaces/IExchange.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";

/**
    @title A simple contract delegated to exchange selection for token pairs swap

    This contract is meant to reference a Chainlink oracle and check the swaps against
    the oracle prices, accepting a maximum slippage that can be set for every pair.
 */
contract SwapAdapterRouter is IExchange, Ownable {
    using SafeERC20 for IERC20Metadata;

    // mapping from hash(tokenIn.address + tokenOut.address) to the exchange to use
    mapping(bytes32 => address) private _adapters;
    // maximum accepted slippage during a swap for each swap pair, denominated in wad (1e18 = 100%)
    mapping(bytes32 => uint256) private _slippage;
    // address of the Chainlink dollar price oracle
    IPriceOracle private _priceOracle;

    error AddressZero();
    error Slippage();
    error SwapZero();

    constructor(address priceOracle_) Ownable() {
        _zeroAddressCheck(priceOracle_);
        _priceOracle = IPriceOracle(priceOracle_);
    }

    /**
        @notice Returns the address to use as dollar price oracle
        @return priceOracle The address of the price oracle
     */
    function getPriceOracle() external view returns (address priceOracle) {
        return address(_priceOracle);
    }

    /**
        @notice Returns the adapter to use for a pair of tokens
        @param tokenIn The address of the input token of the swap
        @param tokenOut The address of the output token of the swap
        @return adapter The address of the adapter to use for the swap
     */
    function getAdapter(address tokenIn, address tokenOut) external view returns (address adapter) {
        return _adapters[_encodePath(tokenIn, tokenOut)];
    }

    /**
        @notice Returns the slippage parameter for a given tokens pair swap
        @param tokenIn The address of the input token of the swap
        @param tokenOut The address of the output token of the swap
        @return slippage The maximum accepted slippage for the swap
     */
    function getSlippage(address tokenIn, address tokenOut) external view returns (uint256 slippage) {
        return _slippage[_encodePath(tokenIn, tokenOut)];
    }

    /**
        @notice Sets an address to use as dollar price oracle
        @param priceOracle_ The address of the price oracle
     */
    function setPriceOracle(address priceOracle_) external onlyOwner {
        _zeroAddressCheck(priceOracle_);
        _priceOracle = IPriceOracle(priceOracle_);
    }

    /**
        @notice Sets a adapter to use for a pair of tokens
        @param tokenIn The address of the input token of the swap
        @param tokenOut The address of the output token of the swap
        @param adapter The address of the adapter to use for the swap
     */
    function setAdapter(address tokenIn, address tokenOut, address adapter) external onlyOwner {
        _zeroAddressCheck(adapter);
        _adapters[_encodePath(tokenIn, tokenOut)] = adapter;
    }

    /**
        @notice Sets a slippage parameter for a given tokens pair swap
        @param tokenIn The address of the input token of the swap
        @param tokenOut The address of the output token of the swap
        @param slippage The maximum accepted slippage for the swap
     */
    function setSlippage(address tokenIn, address tokenOut, uint256 slippage) external onlyOwner {
        _slippage[_encodePath(tokenIn, tokenOut)] = slippage;
    }

    /**
        @inheritdoc IExchange
        @dev implementation return amountOutMin because we also consider slippage to be consistent with getInputAmount impl.
     */
    function getOutputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint amountOut) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        (amountOut, ) = _slippedValueOut(tokenIn, tokenOut, amountIn);
    }

    /**
        @inheritdoc IExchange
        @dev implementation return amountInMax because this is the amount that need to be approved
     */
    function getInputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view override returns (uint amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        (amountIn, ) = _slippedValueIn(tokenIn, tokenOut, amountOut);
    }

    /// @inheritdoc ISwapAdapter
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        address adapter = _adapters[_encodePath(tokenIn, tokenOut)];
        _zeroAddressCheck(adapter);

        (uint256 amountOutMin, uint256 amountOutMax) = _slippedValueOut(tokenIn, tokenOut, amountIn);

        // TBD - delegate call to adapter
        IERC20Metadata(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20Metadata(tokenIn).safeApprove(adapter, amountIn);
        amountOut = ISwapAdapter(adapter).swapIn(tokenIn, tokenOut, amountIn);

        if (amountOut == 0) {
            revert SwapZero();
        }

        if (amountOut < amountOutMin || amountOut > amountOutMax) {
            revert Slippage();
        }

        IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountOut);
    }

    /// @inheritdoc ISwapAdapter
    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 preApprovedAmountIn
    ) external returns (uint256 amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        address adapter = _adapters[_encodePath(tokenIn, tokenOut)];
        _zeroAddressCheck(adapter);

        (uint256 amountInMax, uint256 amountInMin) = _slippedValueIn(tokenIn, tokenOut, amountOut);

        // TBD - delegate call to adapter
        IERC20Metadata(tokenIn).safeTransferFrom(msg.sender, address(this), preApprovedAmountIn);
        IERC20Metadata(tokenIn).safeApprove(adapter, preApprovedAmountIn);
        amountIn = ISwapAdapter(adapter).swapOut(tokenIn, tokenOut, amountOut, preApprovedAmountIn);

        if (amountIn < amountInMin || amountIn > amountInMax) {
            revert Slippage();
        }

        IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountOut);

        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender
        // Also reset approval in any case
        IERC20Metadata(tokenIn).safeApprove(adapter, 0);
        if (amountIn < preApprovedAmountIn) {
            IERC20Metadata(tokenIn).safeTransfer(msg.sender, preApprovedAmountIn - amountIn);
        }
    }

    /**
        @notice Reverts if a given address is the zero address
        @param a The address to check
     */
    function _zeroAddressCheck(address a) private pure {
        if (a == address(0)) {
            revert AddressZero();
        }
    }

    /**
        @notice Produces a unique key to address the pair <tokenIn, tokenOut>
        @param tokenIn The address of tokenIn
        @param tokenOut The address of tokenOut
        @return pathKey The hash of the pair
     */
    function _encodePath(address tokenIn, address tokenOut) private pure returns (bytes32 pathKey) {
        pathKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    /**
        @notice Gets the minimum output amount given an input amount and a price
        @param tokenIn The input token address
        @param tokenOut The output token address
        @param amountIn The input amount, denominated in input token
        @return amountOutMin The minimum output amount, denominated in output token
        @return amountOutMax The maximum output amount, denominated in input token
     */
    function _slippedValueOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (uint256 amountOutMin, uint256 amountOutMax) {
        uint256 price = _priceOracle.getPrice(tokenIn, tokenOut);
        uint256 amountOut = (price * amountIn) / 10 ** IERC20Metadata(tokenIn).decimals();
        amountOutMin = (amountOut * (1e18 - _slippage[_encodePath(tokenIn, tokenOut)])) / 1e18;
        amountOutMax = (amountOut * (1e18 + _slippage[_encodePath(tokenIn, tokenOut)])) / 1e18;
    }

    /**
        @notice Gets the maximum input amount given an output amount and a price
        @param tokenIn The input token address
        @param tokenOut The output token address
        @param amountOut The output amount, denominated in output token
        @return amountInMax The maximum input amount, denominated in input token
        @return amountInMin The minimum input amount, denominated in input token
     */
    function _slippedValueIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) private view returns (uint256 amountInMax, uint256 amountInMin) {
        uint256 price = _priceOracle.getPrice(tokenOut, tokenIn);
        uint256 amountIn = (price * amountOut) / 10 ** IERC20Metadata(tokenOut).decimals();
        amountInMax = (amountIn * (1e18 + _slippage[_encodePath(tokenIn, tokenOut)])) / 1e18;
        amountInMin = (amountIn * (1e18 - _slippage[_encodePath(tokenIn, tokenOut)])) / 1e18;
    }
}
