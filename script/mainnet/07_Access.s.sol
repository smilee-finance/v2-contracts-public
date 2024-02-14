// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {IGAccessNFT} from "@project/periphery/IGAccessNFT.sol";
import {VaultAccessNFT} from "@project/periphery/VaultAccessNFT.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/mainnet/07_Access.s.sol:AccessTokenOps --rpc-url $RPC_MAINNET --broadcast -vv --sig 'grantVaultAccess(address)' <WALLET>
 */
contract AccessTokenOps is EnhancedScript {

    uint256 internal _adminPrivateKey;
    AddressProvider internal _ap;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _ap = AddressProvider(_readAddress(txLogs, "AddressProvider"));
    }

    function run() external view {
        console.log("Please run a specific task");
    }

    function grantVaultAccess(address user) public {
        VaultAccessNFT vaultAccessNFT = VaultAccessNFT(_ap.vaultAccessNFT());

        vm.startBroadcast(_adminPrivateKey);
        vaultAccessNFT.createToken(user, type(uint256).max);
        vm.stopBroadcast();
    }

    function grantIGAccess(address user) public {
        IGAccessNFT igAccessNFT = IGAccessNFT(_ap.dvpAccessNFT());

        vm.startBroadcast(_adminPrivateKey);
        igAccessNFT.createToken(user, type(uint256).max);
        vm.stopBroadcast();
    }

}
