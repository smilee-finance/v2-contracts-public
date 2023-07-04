// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "../src/AddressProvider.sol";

contract RegistryTest is Test {
    bytes4 constant MissingAddress = bytes4(keccak256("MissingAddress()"));
    TestnetRegistry registry;
    MockedIG dvp;
    address admin = address(0x21);

    constructor() {
        vm.startPrank(admin);
        AddressProvider ap = new AddressProvider();
        registry = new TestnetRegistry();
        ap.setRegistry(address(registry));
        vm.stopPrank();

        MockedVault vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        dvp = new MockedIG(address(vault), address(0x42));
    }

    function testNotRegisteredAddress() public {
        address addrToCheck = address(0x150);
        bool isAddressRegistered = registry.isRegistered(addrToCheck);
        assertEq(isAddressRegistered, false);
    }

    function testRegisterAddress() public {
        address addrToRegister = address(dvp);

        bool isAddressRegistered = registry.isRegistered(addrToRegister);
        assertEq(isAddressRegistered, false);

        vm.prank(admin);
        registry.register(addrToRegister);

        isAddressRegistered = registry.isRegistered(addrToRegister);
        assertEq(isAddressRegistered, true);
    }

    function testUnregisterAddressFail() public {
        address addrToUnregister = address(0x150);
        vm.expectRevert(MissingAddress);
        vm.prank(admin);
        registry.unregister(addrToUnregister);
    }

    function testUnregisterAddress() public {
        address addrToUnregister = address(dvp);

        vm.prank(admin);
        registry.register(addrToUnregister);
        bool isAddressRegistered = registry.isRegistered(addrToUnregister);
        assertEq(isAddressRegistered, true);

        vm.prank(admin);
        registry.unregister(addrToUnregister);

        isAddressRegistered = registry.isRegistered(addrToUnregister);
        assertEq(isAddressRegistered, false);
    }
}
