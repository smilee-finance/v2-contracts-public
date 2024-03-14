// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {ChainlinkPriceOracle} from "@project/providers/chainlink/ChainlinkPriceOracle.sol";
import {SwapAdapterRouter} from "@project/providers/SwapAdapterRouter.sol";
import {UniswapAdapter} from "@project/providers/uniswap/UniswapAdapter.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/mainnet/02_Token.s.sol:TokenOps --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv --sig 'deployToken(string memory)' <SYMBOL>
 */
contract TokenOps is EnhancedScript {

    uint256 internal _adminPrivateKey;
    AddressProvider internal _ap;
    UniswapAdapter internal _uniswapAdapter;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _ap = AddressProvider(_readAddress(txLogs, "AddressProvider"));
        _uniswapAdapter = UniswapAdapter(_readAddress(txLogs, "UniswapAdapter"));
    }

    function run() external view {
        console.log("Please run a specific task");
    }

    function setChainlinkPriceFeedForToken(address token, address chainlinkFeedAddress) public {
        ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(_ap.priceOracle());

        vm.startBroadcast(_adminPrivateKey);
        priceOracle.setPriceFeed(token, chainlinkFeedAddress);
        vm.stopBroadcast();
    }

    function setChainlinkPriceFeedMaxDelay(address token, uint256 maxDelay) public {
        ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(_ap.priceOracle());

        vm.startBroadcast(_adminPrivateKey);
        priceOracle.setPriceFeedMaxDelay(token, maxDelay);
        vm.stopBroadcast();
    }

    function setSwapAdapterForTokens(address tokenIn, address tokenOut, address swapAdapter) public {
        SwapAdapterRouter swapAdapterRouter = SwapAdapterRouter(_ap.exchangeAdapter());

        vm.startBroadcast(_adminPrivateKey);
        swapAdapterRouter.setAdapter(tokenIn, tokenOut, swapAdapter);
        swapAdapterRouter.setAdapter(tokenOut, tokenIn, swapAdapter);
        vm.stopBroadcast();
    }

    function useUniswapAdapterWithTokens(address token0, address token1) public {
        SwapAdapterRouter swapAdapterRouter = SwapAdapterRouter(_ap.exchangeAdapter());

        vm.startBroadcast(_adminPrivateKey);
        swapAdapterRouter.setAdapter(token0, token1, address(_uniswapAdapter));
        swapAdapterRouter.setAdapter(token1, token0, address(_uniswapAdapter));
        vm.stopBroadcast();
    }

    function setSwapAcceptedSlippageForTokens(address tokenIn, address tokenOut, uint256 value) public {
        SwapAdapterRouter swapAdapterRouter = SwapAdapterRouter(_ap.exchangeAdapter());

        vm.startBroadcast(_adminPrivateKey);
        swapAdapterRouter.setSlippage(tokenIn, tokenOut, value);
        swapAdapterRouter.setSlippage(tokenOut, tokenIn, value);
        vm.stopBroadcast();
    }

    function setUniswapPath(address tokenIn, address tokenOut, bytes memory path) public {
        UniswapAdapter uniswapAdapter = UniswapAdapter(SwapAdapterRouter(_ap.exchangeAdapter()).getAdapter(tokenIn, tokenOut));

        vm.startBroadcast(_adminPrivateKey);
        uniswapAdapter.setPath(path, tokenIn, tokenOut);
        vm.stopBroadcast();
    }

    function printUniswapPath(address tokenIn, address tokenOut, uint24 fee) public {
        // 10000 is 1%
        //  3000 is 0.3%
        //   500 is 0.05%
        bytes memory path = abi.encodePacked(tokenIn, fee, tokenOut);

        vm.startBroadcast(_adminPrivateKey);
        console.log("path is");
        console.logBytes(path);
        vm.stopBroadcast();
    }

    function printUniswapPathWithHop(address tokenIn, uint24 feeMiddleIn, address tokenMiddle, uint24 feeMiddleOut, address tokenOut) public {
        // 10000 is 1%
        //  3000 is 0.3%
        //   500 is 0.05%
        bytes memory path = abi.encodePacked(tokenIn, feeMiddleIn, tokenMiddle, feeMiddleOut, tokenOut);

        vm.startBroadcast(_adminPrivateKey);
        console.log("path is");
        console.logBytes(path);
        vm.stopBroadcast();
    }

    function setTokenRiskFreeRate(address token, uint256 value) public {
        MarketOracle marketOracle = MarketOracle(_ap.marketOracle());

        vm.startBroadcast(_adminPrivateKey);
        marketOracle.setRiskFreeRate(token, value);
        vm.stopBroadcast();
    }

    function setImpliedVolatility(address token0, address token1, uint256 frequency, uint256 value) public {
        MarketOracle marketOracle = MarketOracle(_ap.marketOracle());

        vm.startBroadcast(_adminPrivateKey);
        marketOracle.setImpliedVolatility(token0, token1, frequency, value);
        vm.stopBroadcast();
    }

    // // ARBITRUM MAINNET:
    // function runConfiguration() public {
    //     setChainlinkPriceFeedForToken(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);
    //     setChainlinkPriceFeedForToken(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    //     setChainlinkPriceFeedForToken(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6);
    //     setChainlinkPriceFeedForToken(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a, 0xDB98056FecFff59D032aB628337A4887110df3dB);
    //     setChainlinkPriceFeedForToken(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57);

    //     useUniswapAdapterWithTokens(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    //     useUniswapAdapterWithTokens(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x912CE59144191C1204E64559FE8253a0e49E6548);
    //     useUniswapAdapterWithTokens(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    //     useUniswapAdapterWithTokens(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    //     // USDC / WETH:
    //     bytes memory path = hex"82af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e5831";
    //     setUniswapPath(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 0xaf88d065e77c8cC2239327C5EDb3A432268e5831, path);
    //     path = hex"af88d065e77c8cc2239327c5edb3a432268e58310001f482af49447d8a07e3bd95bd0d56f35241523fbab1";
    //     setUniswapPath(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, path);
    //     // USDC / ARB:
    //     path = hex"912ce59144191c1204e64559fe8253a0e49e65480001f482af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e5831";
    //     setUniswapPath(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xaf88d065e77c8cC2239327C5EDb3A432268e5831, path);
    //     path = hex"af88d065e77c8cc2239327c5edb3a432268e58310001f482af49447d8a07e3bd95bd0d56f35241523fbab10001f4912ce59144191c1204e64559fe8253a0e49e6548";
    //     setUniswapPath(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x912CE59144191C1204E64559FE8253a0e49E6548, path);
    //     // USDC / GMX:
    //     path = hex"fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a000bb882af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e5831";
    //     setUniswapPath(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a, 0xaf88d065e77c8cC2239327C5EDb3A432268e5831, path);
    //     path = hex"af88d065e77c8cc2239327c5edb3a432268e58310001f482af49447d8a07e3bd95bd0d56f35241523fbab1000bb8fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a";
    //     setUniswapPath(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a, path);
    //     // USDC / WBTC:
    //     path = hex"2f2a2543b76a4166549f7aab2e75bef0aefc5b0f0001f482af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e5831";
    //     setUniswapPath(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, 0xaf88d065e77c8cC2239327C5EDb3A432268e5831, path);
    //     path = hex"af88d065e77c8cc2239327c5edb3a432268e58310001f482af49447d8a07e3bd95bd0d56f35241523fbab10001f42f2a2543b76a4166549f7aab2e75bef0aefc5b0f";
    //     setUniswapPath(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, path);

    //     setSwapAcceptedSlippageForTokens(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 0.015e18); // WETH
    //     setSwapAcceptedSlippageForTokens(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x912CE59144191C1204E64559FE8253a0e49E6548, 0.02e18);  // ARB
    //     setSwapAcceptedSlippageForTokens(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a, 0.025e18); // GMX
    //     setSwapAcceptedSlippageForTokens(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, 0.015e18); // WBTC
    // }
}
