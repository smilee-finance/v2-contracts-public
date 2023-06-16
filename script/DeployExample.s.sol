// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/DeployExample.s.sol --fork-url $RPC_LOCALNET [--broadcast] -vvvv
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/DeployExample.s.sol --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv
 */
contract DeployExample is Script {
    uint256 internal _deployerPrivateKey;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    // NOTE: this is the script entrypoint
    function run() external {
        // The broadcast will records the calls and contract creations made and will replay them on-chain.
        // For reference, the broadcast transaction logs will be stored in the broadcast directory.
        vm.startBroadcast(_deployerPrivateKey);
        _doSomething();
        vm.stopBroadcast();
    }

    function _doSomething() internal {
        // Deploy something:
        TestnetToken sUSD = new TestnetToken("Smilee UDS", "sUSD");
        sUSD.setController(address(0x42));
    }
}
