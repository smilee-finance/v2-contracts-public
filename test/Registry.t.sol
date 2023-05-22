// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Registry} from "../src/Registry.sol";

contract RegistryTest is Test {
    bytes4 constant MissingAddress = bytes4(keccak256("MissingAddress()"));
    Registry registry;

    function setUp() public {
        registry = new Registry();
    }

    function testNotRegisteredAddress() public {
        address addrToCheck = address(0x150);
        bool isAddressRegistered = registry.isRegistered(addrToCheck);
        assertEq(isAddressRegistered, false);
    }

    function testRegisterAddress() public {
        address addrToRegister = address(0x150);
        registry.register(addrToRegister);
        bool isAddressRegistered = registry.isRegistered(addrToRegister);
        assertEq(isAddressRegistered, true);
    }

    function testUnregisterAddressFail() public {
        address addrToUnregister = address(0x150);
        vm.expectRevert(MissingAddress);
        registry.unregister(addrToUnregister);
    }

    function testUnregisterAddress() public {
        address addrToUnregister = address(0x150);
        registry.register(addrToUnregister);
        registry.unregister(addrToUnregister);
        bool isAddressRegistered = registry.isRegistered(addrToUnregister);
        assertEq(isAddressRegistered, false);
    }
}
