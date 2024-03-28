// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {IGAccessNFT} from "@project/periphery/IGAccessNFT.sol";
import {PositionManager} from "@project/periphery/PositionManager.sol";
import {Registry} from "@project/periphery/Registry.sol";
import {VaultProxy} from "@project/periphery/VaultProxy.sol";
import {VaultAccessNFT} from "@project/periphery/VaultAccessNFT.sol";
import {SwapAdapterRouter} from "@project/providers/SwapAdapterRouter.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/01_CoreFoundations.s.sol:DeployCoreFoundations --fork-url $RPC_LOCALNET --broadcast -vvvv
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/01_CoreFoundations.s.sol:DeployCoreFoundations --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv
 */
contract DeployCoreFoundations is Script {
    uint256 internal _deployerPrivateKey;
    address internal _deployerAddress;
    address internal _godAddress;
    address internal _adminAddress;
    address internal _scheduler;
    bool internal _deployerIsGod;
    bool internal _deployerIsAdmin;

    error ZeroAddress(string name);

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        _godAddress = vm.envAddress("GOD_ADDRESS");
        _adminAddress = vm.envAddress("ADMIN_ADDRESS");
        _scheduler = vm.envAddress("EPOCH_ROLLER_ADDRESS");

        _deployerIsGod = (_deployerAddress == _godAddress);
        _deployerIsAdmin = (_deployerAddress == _adminAddress);
    }

    // NOTE: this is the script entrypoint
    function run() external {
        _checkZeroAddress(_deployerAddress, "DEPLOYER_ADDRESS");
        _checkZeroAddress(_godAddress, "GOD_ADDRESS");
        _checkZeroAddress(_adminAddress, "ADMIN_ADDRESS");
        _checkZeroAddress(_scheduler, "SCHEDULER");

        vm.startBroadcast(_deployerPrivateKey);
        _deployMainContracts();
        vm.stopBroadcast();
    }

    function _checkZeroAddress(address addr, string memory name) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress(name);
        }
    }

    function _deployMainContracts() internal {
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_GOD(), _godAddress);
        ap.grantRole(ap.ROLE_ADMIN(), _adminAddress);
        ap.grantRole(ap.ROLE_ADMIN(), _deployerAddress); // TMP
        if (!_deployerIsGod) {
            ap.renounceRole(ap.ROLE_GOD(), _deployerAddress);
        }

        TestnetToken sUSD = new TestnetToken("Smilee USD", "sUSD");
        sUSD.setDecimals(6);
        sUSD.setTransferRestriction(false);
        sUSD.setAddressProvider(address(ap));

        TestnetPriceOracle priceOracle = new TestnetPriceOracle(address(sUSD));
        ap.setPriceOracle(address(priceOracle));

        VaultProxy vaultProxy = new VaultProxy(address(ap));
        ap.setVaultProxy(address(vaultProxy));

        MarketOracle marketOracle = new MarketOracle();
        marketOracle.grantRole(marketOracle.ROLE_GOD(), _godAddress);
        marketOracle.grantRole(marketOracle.ROLE_ADMIN(), _adminAddress);
        marketOracle.grantRole(marketOracle.ROLE_ADMIN(), _scheduler);
        if (!_deployerIsGod) {
            marketOracle.renounceRole(marketOracle.ROLE_GOD(), _deployerAddress);
        }
        ap.setMarketOracle(address(marketOracle));

        // NOTE: in testnet the router cannot be used as the TestnetToken does not support it when swapping...
        SwapAdapterRouter swapAdapterRouter = new SwapAdapterRouter(address(ap), 0);
        swapAdapterRouter.grantRole(swapAdapterRouter.ROLE_GOD(), _godAddress);
        swapAdapterRouter.grantRole(swapAdapterRouter.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            swapAdapterRouter.renounceRole(swapAdapterRouter.ROLE_GOD(), _deployerAddress);
        }
        // ap.setExchangeAdapter(address(swapAdapterRouter));

        TestnetSwapAdapter swapper = new TestnetSwapAdapter(address(priceOracle));
        ap.setExchangeAdapter(address(swapper));

        FeeManager feeManager = new FeeManager(address(ap), 0);
        feeManager.grantRole(feeManager.ROLE_GOD(), _godAddress);
        feeManager.grantRole(feeManager.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            feeManager.renounceRole(feeManager.ROLE_GOD(), _deployerAddress);
        }
        ap.setFeeManager(address(feeManager));

        Registry registry = new Registry();
        registry.grantRole(registry.ROLE_GOD(), _godAddress);
        registry.grantRole(registry.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            registry.renounceRole(registry.ROLE_GOD(), _deployerAddress);
        }
        ap.setRegistry(address(registry));

        PositionManager pm = new PositionManager(address(ap));
        pm.grantRole(pm.ROLE_GOD(), _godAddress);
        pm.grantRole(pm.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            pm.renounceRole(pm.ROLE_GOD(), _deployerAddress);
        }
        ap.setDvpPositionManager(address(pm));

        VaultAccessNFT vaultAccess = new VaultAccessNFT(address(ap));
        vaultAccess.grantRole(vaultAccess.ROLE_GOD(), _godAddress);
        vaultAccess.grantRole(vaultAccess.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            vaultAccess.renounceRole(vaultAccess.ROLE_GOD(), _deployerAddress);
        }
        ap.setVaultAccessNFT(address(vaultAccess));

        IGAccessNFT igAccess = new IGAccessNFT();
        igAccess.grantRole(igAccess.ROLE_GOD(), _godAddress);
        igAccess.grantRole(igAccess.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            igAccess.renounceRole(igAccess.ROLE_GOD(), _deployerAddress);
        }
        ap.setDVPAccessNFT(address(igAccess));

        if (!_deployerIsAdmin) {
            ap.renounceRole(ap.ROLE_ADMIN(), _deployerAddress);
        }
    }
}
