// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IDVP} from "@project/interfaces/IDVP.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {IG} from "@project/IG.sol";
import {Vault} from "@project/Vault.sol";
import {IGAccessNFT} from "@project/periphery/IGAccessNFT.sol";
import {PositionManager} from "@project/periphery/PositionManager.sol";
import {Registry} from "@project/periphery/Registry.sol";
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

    uint256 internal _godPrivateKey;
    uint256 internal _adminPrivateKey;
    AddressProvider internal _ap;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _godPrivateKey = vm.envUint("GOD_PRIVATE_KEY");
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

    function revokeVaultAccess(uint256 tokenId) public {
        VaultAccessNFT vaultAccessNFT = VaultAccessNFT(_ap.vaultAccessNFT());

        vm.startBroadcast(_adminPrivateKey);
        vaultAccessNFT.destroyToken(tokenId);
        vm.stopBroadcast();
    }

    function grantIGAccess(address user) public {
        IGAccessNFT igAccessNFT = IGAccessNFT(_ap.dvpAccessNFT());

        vm.startBroadcast(_adminPrivateKey);
        igAccessNFT.createToken(user, type(uint256).max);
        vm.stopBroadcast();
    }

    function revokeIGAccess(uint256 tokenId) public {
        IGAccessNFT igAccessNFT = IGAccessNFT(_ap.dvpAccessNFT());

        vm.startBroadcast(_adminPrivateKey);
        igAccessNFT.destroyToken(tokenId);
        vm.stopBroadcast();
    }

    function setVaultAccess(address vaultAddr, bool value) public {
        vm.startBroadcast(_adminPrivateKey);
        Vault(vaultAddr).setPriorityAccessFlag(value);
        vm.stopBroadcast();
    }

    function setPositionManagerAccess(bool value) public {
        vm.startBroadcast(_adminPrivateKey);
        PositionManager pm = PositionManager(_ap.dvpPositionManager());
        pm.setNftAccessFlag(value);
        vm.stopBroadcast();
    }

    function grantVaultAccessWithLimit(address user, uint256 limit) public {
        VaultAccessNFT vaultAccessNFT = VaultAccessNFT(_ap.vaultAccessNFT());
        limit = limit * 10**6;

        vm.startBroadcast(_adminPrivateKey);
        vaultAccessNFT.createToken(user, limit);
        vm.stopBroadcast();
    }

    function grantRoleOnProtocol(string memory roleName, address account) public {
        bytes32 role = keccak256(abi.encodePacked(roleName));

        uint256 roleAdmin = 0;
        if (role == keccak256("ROLE_GOD") || role == keccak256("ROLE_ADMIN")) {
            roleAdmin = _godPrivateKey;
        } else {
            console.log("ROLE NAME NOT SUPPORTED");
            return;
        }

        vm.startBroadcast(roleAdmin);

        IAccessControl(address(_ap)).grantRole(role, account); // AddressProvider
        IAccessControl(_ap.priceOracle()).grantRole(role, account); // ChainlinkPriceOracle
        IAccessControl(_ap.marketOracle()).grantRole(role, account); // MarketOracle
        IAccessControl(_ap.exchangeAdapter()).grantRole(role, account); // SwapAdapterRouter
        IAccessControl(_ap.feeManager()).grantRole(role, account); // FeeManager
        IAccessControl(_ap.registry()).grantRole(role, account); // Registry
        IAccessControl(_ap.dvpPositionManager()).grantRole(role, account); // PositionManager
        IAccessControl(_ap.vaultAccessNFT()).grantRole(role, account); // VaultAccessNFT
        IAccessControl(_ap.dvpAccessNFT()).grantRole(role, account); // IGAccessNFT

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        address uniswapAdapter = _readAddress(txLogs, "UniswapAdapter");
        IAccessControl(uniswapAdapter).grantRole(role, account); // UniswapAdapter

        Registry registry = Registry(_ap.registry());
        address[] memory dvps = registry.getDVPs();
        uint256 tot = dvps.length;
        for (uint256 i = 0; i < tot; i++) {
            address dvp = dvps[i];
            address vault = IDVP(dvp).vault();
            IAccessControl(dvp).grantRole(role, account); // IG
            IAccessControl(vault).grantRole(role, account); // Vault
        }

        vm.stopBroadcast();
        console.log("Number of DVPs with granted role:", tot);
    }

    function revokeRoleOnProtocol(string memory roleName, address account) public {
        bytes32 role = keccak256(abi.encodePacked(roleName));

        uint256 roleAdmin = 0;
        if (role == keccak256("ROLE_GOD") || role == keccak256("ROLE_ADMIN")) {
            roleAdmin = _godPrivateKey;
        } else {
            console.log("ROLE NAME NOT SUPPORTED");
            return;
        }

        vm.startBroadcast(roleAdmin);

        IAccessControl(address(_ap)).revokeRole(role, account); // AddressProvider
        IAccessControl(_ap.priceOracle()).revokeRole(role, account); // ChainlinkPriceOracle
        IAccessControl(_ap.marketOracle()).revokeRole(role, account); // MarketOracle
        IAccessControl(_ap.exchangeAdapter()).revokeRole(role, account); // SwapAdapterRouter
        IAccessControl(_ap.feeManager()).revokeRole(role, account); // FeeManager
        IAccessControl(_ap.registry()).revokeRole(role, account); // Registry
        IAccessControl(_ap.dvpPositionManager()).revokeRole(role, account); // PositionManager
        IAccessControl(_ap.vaultAccessNFT()).revokeRole(role, account); // VaultAccessNFT
        IAccessControl(_ap.dvpAccessNFT()).revokeRole(role, account); // IGAccessNFT

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        address uniswapAdapter = _readAddress(txLogs, "UniswapAdapter");
        IAccessControl(uniswapAdapter).revokeRole(role, account); // UniswapAdapter

        Registry registry = Registry(_ap.registry());
        address[] memory dvps = registry.getDVPs();
        uint256 tot = dvps.length;
        for (uint256 i = 0; i < tot; i++) {
            address dvp = dvps[i];
            address vault = IDVP(dvp).vault();
            IAccessControl(dvp).revokeRole(role, account); // IG
            IAccessControl(vault).revokeRole(role, account); // Vault
        }

        vm.stopBroadcast();
        console.log("Number of DVPs with revoked role:", tot);
    }

}
