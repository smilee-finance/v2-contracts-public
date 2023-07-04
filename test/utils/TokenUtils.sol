// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetRegistry} from "../../src/testnet/TestnetRegistry.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";

library TokenUtils {

    function createToken(string memory name, string memory symbol, address addressProviderAddr, address admin, Vm vm) public returns (address tokenAddr) {
        vm.startPrank(admin);

        TestnetToken token = new TestnetToken(name, symbol);
        tokenAddr = address(token);

        AddressProvider ap = AddressProvider(addressProviderAddr);

        address registryAddress = ap.registry();
        if (registryAddress == address(0)) {
            TestnetRegistry registry = new TestnetRegistry();
            registryAddress = address(registry);
            ap.setRegistry(registryAddress);
        }

        token.setController(registryAddress);

        address priceOracleAddress = ap.priceOracle();
        if (priceOracleAddress == address(0)) {
            TestnetPriceOracle priceOracle = new TestnetPriceOracle(tokenAddr);
            priceOracleAddress = address(priceOracle);
            ap.setPriceOracle(priceOracleAddress);
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

        token.setSwapper(dexAddress);

        vm.stopPrank();
    }

    // /// @dev Create TestnetToken couple contracts
    // function initTokens(
    //     address tokenAdmin,
    //     address controller,
    //     address swapper,
    //     Vm vm
    // ) internal returns (address baseToken, address sideToken) {
    //     vm.startPrank(tokenAdmin);

    //     TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
    //     token.setController(controller);
    //     token.setSwapper(swapper);
    //     baseToken = address(token);

    //     token = new TestnetToken("Testnet WETH", "stWETH");
    //     token.setController(controller);
    //     token.setSwapper(swapper);
    //     sideToken = address(token);

    //     vm.stopPrank();
    // }

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
