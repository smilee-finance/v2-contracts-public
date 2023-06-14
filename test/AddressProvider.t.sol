// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Factory} from "../src/Factory.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {DVP} from "../src/DVP.sol";
import {DVPType} from "../src/lib/DVPType.sol";
import {Vault} from "../src/Vault.sol";
import {IG} from "../src/IG.sol";
import {AddressProvider} from "../src/AddressProvider.sol";

contract AddressProviderTest is Test {
    address tokenAdmin = address(0x1);

    AddressProvider addressProvider;

    function setUp() public {
        vm.prank(tokenAdmin);
        addressProvider = new AddressProvider();
    }

    function testAddressProviderUnauthorized() public {
        //vm.startPrank(address(0x100));
        vm.expectRevert("Ownable: caller is not the owner");
        addressProvider.setExchangeAdapter(address(0x100));
    }

    function testAddressProviderSetExchangeAdapter() public {
        vm.prank(tokenAdmin);
        addressProvider.setExchangeAdapter(address(0x100));

        assertEq(address(0x100), addressProvider.exchangeAdapter());
    }

    function testAddressProviderSetPriceOracle() public {
        vm.prank(tokenAdmin);
        addressProvider.setPriceOracle(address(0x101));

        assertEq(address(0x101), addressProvider.priceOracle());
    }

    function testAddressProviderSetMarketOracle() public {
        vm.prank(tokenAdmin);
        addressProvider.setMarketOracle(address(0x102));

        assertEq(address(0x102), addressProvider.marketOracle());
    }

    function testAddressProviderSetRegistry() public {
        vm.prank(tokenAdmin);
        addressProvider.setRegistry(address(0x103));

        assertEq(address(0x103), addressProvider.registry());
    }
}
