// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IHevm} from "./IHevm.sol";
import {Vm} from "forge-std/Vm.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {MockedRegistry} from "../../mock/MockedRegistry.sol";

library AddressProviderUtils {

    function initialize(address admin, AddressProvider addressProvider, address baseToken, IHevm vm) public {
        address registryAddress = addressProvider.registry();
        if (registryAddress == address(0)) {
            MockedRegistry registry = new MockedRegistry();
            registry.grantRole(registry.ROLE_ADMIN(), admin);
            registryAddress = address(registry);
            vm.prank(admin);
            addressProvider.setRegistry(registryAddress);
        }

        address priceOracleAddress = addressProvider.priceOracle();
        if (priceOracleAddress == address(0)) {
            vm.prank(admin);
            TestnetPriceOracle priceOracle = new TestnetPriceOracle(address(baseToken));
            priceOracleAddress = address(priceOracle);
            vm.prank(admin);
            addressProvider.setPriceOracle(priceOracleAddress);
        }

        address feeManagerAddress = addressProvider.feeManager();
        if (feeManagerAddress == address(0)) {
            FeeManager feeManager = new FeeManager();
            feeManager.grantRole(feeManager.ROLE_ADMIN(), admin);
            feeManagerAddress = address(feeManager);
            vm.prank(admin);
            addressProvider.setFeeManager(feeManagerAddress);
        }

        address marketOracleAddress = addressProvider.marketOracle();
        if (marketOracleAddress == address(0)) {
            MarketOracle marketOracle = new MarketOracle();
            marketOracle.grantRole(marketOracle.ROLE_ADMIN(), admin);
            marketOracleAddress = address(marketOracle);
            vm.prank(admin);
            addressProvider.setMarketOracle(marketOracleAddress);
        }

        address dexAddress = addressProvider.exchangeAdapter();
        if (dexAddress == address(0)) {
            vm.prank(admin);
            TestnetSwapAdapter exchange = new TestnetSwapAdapter(priceOracleAddress);
            dexAddress = address(exchange);
            vm.prank(admin);
            addressProvider.setExchangeAdapter(dexAddress);
        }
    }

}
