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
    AddressProvider ap;

    constructor() {
        vm.startPrank(admin);
        ap = new AddressProvider();
        registry = new TestnetRegistry();
        ap.setRegistry(address(registry));
        vm.stopPrank();

        MockedVault vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        dvp = new MockedIG(address(vault), address(ap));
    }

    function testNotRegisteredAddress() public {
        address addrToCheck = address(0x150);
        bool isAddressRegistered = registry.isRegistered(addrToCheck);
        assertEq(false, isAddressRegistered);
    }

    function testRegisterAddress() public {
        address addrToRegister = address(dvp);

        bool isAddressRegistered = registry.isRegistered(addrToRegister);
        assertEq(false, isAddressRegistered);

        vm.prank(admin);
        registry.register(addrToRegister);

        isAddressRegistered = registry.isRegistered(addrToRegister);
        assertEq(true, isAddressRegistered);
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
        assertEq(true, isAddressRegistered);

        vm.prank(admin);
        registry.unregister(addrToUnregister);

        isAddressRegistered = registry.isRegistered(addrToUnregister);
        assertEq(false, isAddressRegistered);
    }

    function testSideTokenIndexing() public {
        address dvpAddr = address(dvp);
        vm.prank(admin);
        registry.register(dvpAddr);

        address tokenAddr = dvp.sideToken();
        address[] memory tokens = registry.getSideTokens();
        address[] memory dvps = registry.getDVPsBySideToken(tokenAddr);

        assertEq(1, tokens.length);
        assertEq(tokenAddr, tokens[0]);

        assertEq(1, dvps.length);
        assertEq(dvpAddr, dvps[0]);

        vm.prank(admin);
        registry.unregister(dvpAddr);

        tokens = registry.getSideTokens();
        dvps = registry.getDVPsBySideToken(tokenAddr);

        assertEq(0, tokens.length);
        assertEq(0, dvps.length);
    }

    function testSideTokenIndexingDup() public {
        address dvpAddr = address(dvp);
        vm.prank(admin);
        registry.register(dvpAddr);

        vm.prank(admin);
        registry.register(dvpAddr);

        address tokenAddr = dvp.sideToken();
        address[] memory tokens = registry.getSideTokens();
        address[] memory dvps = registry.getDVPsBySideToken(tokenAddr);

        assertEq(1, tokens.length);
        assertEq(tokenAddr, tokens[0]);

        assertEq(1, dvps.length);
        assertEq(dvpAddr, dvps[0]);
    }

    function testMultiSideTokenIndexing() public {
        MockedVault vault2 = MockedVault(
            VaultUtils.createVaultSideTokenSym(dvp.baseToken(), "JOE", 0, ap, admin, vm)
        );
        MockedIG dvp2 = new MockedIG(address(vault2), address(ap));

        vm.prank(admin);
        registry.register(address(dvp));

        vm.prank(admin);
        registry.register(address(dvp2));

        address[] memory tokens = registry.getSideTokens();
        assertEq(2, tokens.length);
        assertEq(dvp.sideToken(), tokens[0]);
        assertEq(dvp2.sideToken(), tokens[1]);

        address[] memory dvps = registry.getDVPsBySideToken(dvp.sideToken());
        assertEq(1, dvps.length);
        assertEq(address(dvp), dvps[0]);

        dvps = registry.getDVPsBySideToken(dvp2.sideToken());
        assertEq(1, dvps.length);
        assertEq(address(dvp2), dvps[0]);

        vm.prank(admin);
        registry.unregister(address(dvp));

        tokens = registry.getSideTokens();
        assertEq(1, tokens.length);
        assertEq(dvp2.sideToken(), tokens[0]);

        dvps = registry.getDVPsBySideToken(dvp.sideToken());
        assertEq(0, dvps.length);

        dvps = registry.getDVPsBySideToken(dvp2.sideToken());
        assertEq(1, dvps.length);
        assertEq(address(dvp2), dvps[0]);
    }
}
