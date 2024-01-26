// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {FeeManager} from "../../src/FeeManager.sol";
import {MarketOracle} from "../../src/MarketOracle.sol";
import {PositionManager} from "../../src/periphery/PositionManager.sol";
import {Registry} from "../../src/periphery/Registry.sol";
import {VaultProxy} from "../../src/periphery/VaultProxy.sol";
import {ChainlinkPriceOracle} from "../../src/providers/chainlink/ChainlinkPriceOracle.sol";
import {UniswapAdapter} from "../../src/providers/uniswap/UniswapAdapter.sol";
import {SwapAdapterRouter} from "../../src/providers/SwapAdapterRouter.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/mainnet/01_CoreFoundations.s.sol:DeployCoreFoundations --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv
 */
contract DeployCoreFoundations is Script {
    uint256 internal _deployerPrivateKey;
    address internal _deployerAddress;
    address internal _adminMultiSigAddress;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = 0x64e02814da99b567a92404a5ac82c087cd41b0065cd3f4c154c14130f1966aaf;
        _deployerAddress = 0xd4039eB67CBB36429Ad9DD30187B94f6A5122215;
        _adminMultiSigAddress = 0xd4039eB67CBB36429Ad9DD30187B94f6A5122215;
    }

    // NOTE: this is the script entrypoint
    function run() external {
        vm.startBroadcast(_deployerPrivateKey);
        _deployMainContracts();
        vm.stopBroadcast();
    }

    function _deployMainContracts() internal {
        // Address USDC: Is it needed?
        // address stableCoin = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_GOD(), _adminMultiSigAddress);
        ap.grantRole(ap.ROLE_ADMIN(), _deployerAddress);
        //ap.renounceRole(ap.ROLE_GOD(), _deployerAddress);

        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle();
        ap.setPriceOracle(address(priceOracle));

        VaultProxy vaultProxy = new VaultProxy(address(ap));
        ap.setVaultProxy(address(vaultProxy));

        MarketOracle marketOracle = new MarketOracle();
        marketOracle.grantRole(marketOracle.ROLE_GOD(), _adminMultiSigAddress);
        marketOracle.grantRole(marketOracle.ROLE_ADMIN(), _deployerAddress);
        //marketOracle.renounceRole(marketOracle.ROLE_GOD(), _deployerAddress);
        ap.setMarketOracle(address(marketOracle));

        SwapAdapterRouter swapAdapterRouter = new SwapAdapterRouter(address(priceOracle), 0);
        ap.setExchangeAdapter(address(swapAdapterRouter));

        address uniswapFactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

        // Create uniswap adapter
        new UniswapAdapter(address(swapAdapterRouter), uniswapFactoryAddress, 0);


        FeeManager feeManager = new FeeManager();
        feeManager.grantRole(feeManager.ROLE_GOD(), _adminMultiSigAddress);
        feeManager.grantRole(feeManager.ROLE_ADMIN(), _deployerAddress);
        //feeManager.renounceRole(feeManager.ROLE_GOD(), _deployerAddress);
        ap.setFeeManager(address(feeManager));

        Registry registry = new Registry();
        registry.grantRole(registry.ROLE_GOD(), _adminMultiSigAddress);
        registry.grantRole(registry.ROLE_ADMIN(), _deployerAddress);
        //registry.renounceRole(registry.ROLE_GOD(), _deployerAddress);
        ap.setRegistry(address(registry));

        PositionManager pm = new PositionManager();
        ap.setDvpPositionManager(address(pm));

        // ap.renounceRole(ap.ROLE_ADMIN(), _deployerAddress);
    }
}
