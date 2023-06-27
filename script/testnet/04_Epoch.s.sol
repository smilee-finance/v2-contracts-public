// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";
import {IDVP} from "../../src/interfaces/IDVP.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {TestnetRegistry} from "../../src/testnet/TestnetRegistry.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/04_Epoch.s.sol:RollEpoch --fork-url $RPC_LOCALNET [--broadcast] -vvvv
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/04_Epoch.s.sol:RollEpoch --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv

        # NOTE: add the following to customize
        #       --sig 'rollEpoch(address)' <DVP_ADDRESS>
 */
contract RollEpoch is EnhancedScript {
    uint256 internal _deployerPrivateKey;
    TestnetRegistry internal _registry;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        AddressProvider addressProvider = AddressProvider(_readAddress(txLogs, "AddressProvider"));
        _registry = TestnetRegistry(addressProvider.registry());
    }

    function run() external {
        (address[] memory list, uint256 number) = _registry.getUnrolledDVPs();
        for (uint256 i = 0; i < number; i++) {
            rollEpoch(list[i]);
        }
    }

    function rollEpoch(address dvp) public
    {
        vm.startBroadcast(_deployerPrivateKey);
        IDVP(dvp).rollEpoch();
        vm.stopBroadcast();
    }
}
