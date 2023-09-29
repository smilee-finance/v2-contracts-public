// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {EpochFrequency} from "../../src/lib/EpochFrequency.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {IG} from "../../src/IG.sol";
import {Vault} from "../../src/Vault.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/03_Factory.s.sol:DeployDVP --fork-url $RPC_LOCALNET [--broadcast] -vvvv
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/03_Factory.s.sol:DeployDVP --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv

        # NOTE: add the following to customize
        #       --sig 'createIGMarket(address,address,uint256)' <BASE_TOKEN_ADDRESS> <SIDE_TOKEN_ADDRESS> <EPOCH_FREQUENCY_IN_SECONDS>
 */
contract DeployDVP is EnhancedScript {
    uint256 internal _deployerPrivateKey;
    address internal _deployerAddress;
    address internal _adminMultiSigAddress;
    address internal _epochRollerAddress;
    address internal _sUSD;
    AddressProvider internal _addressProvider;
    IRegistry internal _registry;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        _adminMultiSigAddress = vm.envAddress("ADMIN_MULTI_SIG_ADDRESS");
        _epochRollerAddress = vm.envAddress("EPOCH_ROLLER_ADDRESS");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _sUSD = _readAddress(txLogs, "TestnetToken");
        _addressProvider = AddressProvider(_readAddress(txLogs, "AddressProvider"));
        _registry = IRegistry(_addressProvider.registry());
    }

    function run() external {
        string memory txLogs = _getLatestTransactionLogs("02_Token.s.sol");
        address sideToken = _readAddress(txLogs, "TestnetToken");

        createIGMarket(_sUSD, sideToken, EpochFrequency.WEEKLY);
    }

    function createIGMarket(
        address baseToken,
        address sideToken,
        uint256 epochFrequency
    )
    public
    {
        vm.startBroadcast(_deployerPrivateKey);

        address vault = _createVault(baseToken, sideToken, epochFrequency);
        address dvp = _createImpermanentGainDVP(vault);

        Vault(vault).setAllowedDVP(dvp);
        _registry.register(dvp);

        vm.stopBroadcast();

        console.log("DVP deployed at", dvp);
        console.log("Vault deployed at", vault);
    }

    function _createVault(
        address baseToken,
        address sideToken,
        uint256 epochFrequency
    )
        internal returns (address)
    {
        Vault vault = new Vault(baseToken, sideToken, epochFrequency, address(_addressProvider));

        vault.grantRole(vault.ROLE_GOD(), _adminMultiSigAddress);
        vault.grantRole(vault.ROLE_ADMIN(), _deployerAddress);
        vault.renounceRole(vault.ROLE_GOD(), _deployerAddress);

        return address(vault);
    }

    function _createImpermanentGainDVP(address vault) internal returns (address) {
        IG dvp = new IG(vault, address(_addressProvider));

        dvp.grantRole(dvp.ROLE_GOD(), _adminMultiSigAddress);
        dvp.grantRole(dvp.ROLE_ADMIN(), _deployerAddress);
        dvp.grantRole(dvp.ROLE_EPOCH_ROLLER(), _epochRollerAddress);
        dvp.renounceRole(dvp.ROLE_GOD(), _deployerAddress);

        return address(dvp);
    }
}
