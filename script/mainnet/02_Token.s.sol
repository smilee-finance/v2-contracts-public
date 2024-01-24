// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {ChainlinkPriceOracle} from "../../src/providers/chainlink/ChainlinkPriceOracle.sol";
import {SwapAdapterRouter} from "../../src/providers/SwapAdapterRouter.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/02_Token.s.sol:TokenOps --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv --sig 'deployToken(string memory)' <SYMBOL>
 */
contract TokenOps is EnhancedScript {

    uint256 internal _deployerPrivateKey;
    AddressProvider internal _ap;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _ap = AddressProvider(_readAddress(txLogs, "AddressProvider"));
    }

    function run() external {
    }

    function setChainlinkPriceFeedForToken(address token, address chainlinkFeedAddress) public {
        ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(_ap.priceOracle());

        vm.startBroadcast(_deployerPrivateKey);
        priceOracle.setPriceFeed(token, chainlinkFeedAddress);
        vm.stopBroadcast();
    }

    function setSwapAdapterForToken(address tokenIn, address tokenOut, address swapAdapter) public {
        SwapAdapterRouter swapAdapterRouter = SwapAdapterRouter(_ap.exchangeAdapter());

        vm.startBroadcast(_deployerPrivateKey);
        swapAdapterRouter.setAdapter(tokenIn, tokenOut, swapAdapter);
        vm.stopBroadcast();
    }
}
