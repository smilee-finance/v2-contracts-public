// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";
import {IDVP} from "../../src/interfaces/IDVP.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {Registry} from "../../src/periphery/Registry.sol";
import {DVP} from "../../src/DVP.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/mainnet/04_Epoch.s.sol:RollEpoch --rpc-url $RPC_MAINNET --broadcast -vv

        # NOTE: add the following to customize
        #       --sig 'rollEpoch(address)' <DVP_ADDRESS>
 */
contract RollEpoch is EnhancedScript {
    uint256 internal _adminPrivateKey;
    uint256 internal _epochRollerPrivateKey;
    Registry internal _registry;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        _epochRollerPrivateKey = vm.envUint("EPOCH_ROLLER_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        AddressProvider addressProvider = AddressProvider(_readAddress(txLogs, "AddressProvider"));
        _registry = Registry(addressProvider.registry());
    }

    function run() external {
        (address[] memory list, uint256 number) = _registry.getUnrolledDVPs();
        for (uint256 i = 0; i < number; i++) {
            rollEpoch(list[i]);
        }
    }

    function rollEpoch(address dvp) public
    {
        vm.startBroadcast(_epochRollerPrivateKey);
        IDVP(dvp).rollEpoch();
        vm.stopBroadcast();
    }

    function grantRoller(address dvpAddr, address account) public {
        DVP dvp = DVP(dvpAddr);

        vm.startBroadcast(_adminPrivateKey);
        dvp.grantRole(dvp.ROLE_EPOCH_ROLLER(), account);
        vm.stopBroadcast();
    }

    function revokeRoller(address dvpAddr, address account) public {
        DVP dvp = DVP(dvpAddr);

        vm.startBroadcast(_adminPrivateKey);
        dvp.revokeRole(dvp.ROLE_EPOCH_ROLLER(), account);
        vm.stopBroadcast();
    }
}
