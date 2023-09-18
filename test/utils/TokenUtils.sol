// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {FeeManager} from "../../src/FeeManager.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetRegistry} from "../../src/testnet/TestnetRegistry.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";

library TokenUtils {
    function createToken(
        string memory name,
        string memory symbol,
        address addressProvider,
        address admin,
        Vm vm
    ) public returns (address tokenAddr) {
        vm.startPrank(admin);

        TestnetToken token = new TestnetToken(name, symbol);
        tokenAddr = address(token);

        AddressProvider ap = AddressProvider(addressProvider);

        address registryAddress = ap.registry();
        if (registryAddress == address(0)) {
            TestnetRegistry registry = new TestnetRegistry();
            registryAddress = address(registry);
            ap.setRegistry(registryAddress);
        }

        token.setAddressProvider(addressProvider);

        address priceOracleAddress = ap.priceOracle();
        if (priceOracleAddress == address(0)) {
            TestnetPriceOracle priceOracle = new TestnetPriceOracle(tokenAddr);
            priceOracleAddress = address(priceOracle);
            ap.setPriceOracle(priceOracleAddress);
        }

        address feeManagerAddress = ap.feeManager();
        if (feeManagerAddress == address(0)) {
            FeeManager feeManager =  new FeeManager(3.5e15, 0.125e18, 1.5e15, 0.125e18);
            feeManagerAddress = address(feeManager);
            ap.setFeeManager(feeManagerAddress);
        }

        address marketOracleAddress = ap.marketOracle();
        if (marketOracleAddress == address(0)) {
            marketOracleAddress = priceOracleAddress;
            ap.setMarketOracle(marketOracleAddress);
        }

        address dexAddress = ap.exchangeAdapter();
        if (dexAddress == address(0)) {
            TestnetSwapAdapter exchange = new TestnetSwapAdapter(priceOracleAddress);
            dexAddress = address(exchange);
            ap.setExchangeAdapter(dexAddress);
        }

        vm.stopPrank();
    }

    /// @dev Provide a certain amount of a given tokens to a given wallet, and approve exchange to a given address
    function provideApprovedTokens(
        address tokenAdmin,
        address token,
        address receiver,
        address approved,
        uint256 amount,
        Vm vm
    ) internal {
        vm.prank(tokenAdmin);
        TestnetToken(token).mint(receiver, amount);
        vm.prank(receiver);
        TestnetToken(token).approve(approved, amount);
    }

    /**
     * Function used to skip coverage on this file
     */
    function testCoverageSkip() private view {}
}
