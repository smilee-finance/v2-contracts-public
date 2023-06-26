// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";
import {IDVP} from "../../src/interfaces/IDVP.sol";
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
 */
contract DeployDVP is EnhancedScript {
    uint256 internal _deployerPrivateKey;
    address internal _sUSD;
    address internal _sETH;
    AddressProvider internal _addressProvider;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _sUSD = _readAddress(txLogs, "TestnetToken");
        _addressProvider = AddressProvider(_readAddress(txLogs, "AddressProvider"));

        txLogs = _getLatestTransactionLogs("02_Token.s.sol");
        _sETH = _readAddress(txLogs, "TestnetToken");
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
        address dvpAddr = createIGMarket(_sUSD, _sETH, EpochFrequency.WEEKLY);
        console.log("DVP: ", dvpAddr);
        address vaultAddr = IDVP(dvpAddr).vault();
        console.log("Vault: ", vaultAddr);
    }

    /**
     * Create Impermanent Gain (IG) DVP associating vault to it.
     * @param baseToken Base Token
     * @param sideToken Side Token
     * @param epochFrequency Epoch Frequency used for rollup and for handling epochs
     * @dev (see interfaces/IDVPImmutables.sol)
     * @return address The address of the created DVP
     */
    function createIGMarket(
        address baseToken,
        address sideToken,
        uint256 epochFrequency
    )
    public returns (address)
    {
        address vault = _createVault(baseToken, sideToken, epochFrequency);
        address dvp = _createImpermanentGainDVP(vault);

        Vault(vault).setAllowedDVP(dvp);

        IRegistry registry = IRegistry(_addressProvider.registry());
        registry.register(dvp);

        return dvp;
    }

    /**
     * Create Vault given baseToken and sideToken
     * @param baseToken Base Token
     * @param sideToken Side Token
     * @param epochFrequency Epoch Frequency used for rollup and for handling epochs
     * @dev (see interfaces/IDVPImmutables.sol)
     * @return address The address of the created Vault
     */
    function _createVault(
        address baseToken,
        address sideToken,
        uint256 epochFrequency
    )
        internal returns (address)
    {
        Vault vault = new Vault(baseToken, sideToken, epochFrequency, address(_addressProvider));
        return address(vault);
    }

    function _createImpermanentGainDVP(address vault) internal returns (address) {
        IG dvp = new IG(vault, address(_addressProvider));
        return address(dvp);
    }
}
