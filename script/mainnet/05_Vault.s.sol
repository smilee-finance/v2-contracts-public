// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Vault} from "@project/Vault.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/mainnet/05_Vault.s.sol:VaultOps --rpc-url $RPC_MAINNET --broadcast -vv --sig 'pauseVault(address)' <VAULT_ADDRESS>
 */
contract VaultOps is EnhancedScript {
    uint256 internal _adminPrivateKey;
    address internal _adminAddress;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        _adminAddress = vm.envAddress("ADMIN_ADDRESS");
    }

    function run() external {}

   function pauseVault(address vaultAddr) public {
         Vault vault = Vault(vaultAddr);

        vm.startBroadcast(_adminPrivateKey);
        vault.changePauseState();
        vm.stopBroadcast();
    }

    function killVault(address vaultAddr) public {
        Vault vault = Vault(vaultAddr);

        vm.startBroadcast(_adminPrivateKey);
        vault.killVault();
        vm.stopBroadcast();
    }

}
