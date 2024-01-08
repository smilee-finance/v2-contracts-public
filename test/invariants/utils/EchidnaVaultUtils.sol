// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IHevm} from "../utils/IHevm.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {AddressProviderUtils} from "./AddressProviderUtils.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {MockedRegistry} from "../../mock/MockedRegistry.sol";
import {MockedIG} from "../../mock/MockedIG.sol";

library EchidnaVaultUtils {
    function createVault(
        address baseToken,
        address tokenAdmin,
        AddressProvider addressProvider,
        uint256 epochFrequency
    ) public returns (address) {
        TestnetToken sideToken = new TestnetToken("SideTestToken", "STT");
        sideToken.setAddressProvider(address(addressProvider));
        TestnetPriceOracle apPriceOracle = TestnetPriceOracle(addressProvider.priceOracle());
        apPriceOracle.setTokenPrice(address(sideToken), 1 ether);
        MockedVault vault = new MockedVault(
            address(baseToken),
            address(sideToken),
            epochFrequency,
            address(addressProvider)
        );
        return address(vault);
    }

    function registerVault(address admin, address vault, AddressProvider addressProvider, IHevm vm) public {
        MockedRegistry apRegistry = MockedRegistry(addressProvider.registry());
        vm.prank(admin);
        apRegistry.registerVault(vault);
    }

    function grantAdminRole(address admin, address vault_) public {
        MockedVault vault = MockedVault(vault_);
        bytes32 role = vault.ROLE_ADMIN();
        vault.grantRole(role, admin);
    }

    function grantEpochRollerRole(address admin, address roller, address vault_, IHevm vm) public {
        MockedVault vault = MockedVault(vault_);
        bytes32 role = vault.ROLE_EPOCH_ROLLER();
        vm.prank(admin);
        vault.grantRole(role, roller);
    }

    function rollEpoch(address admin, MockedVault vault, IHevm vm) public {
        vm.prank(admin);
        vault.rollEpoch();
    }

    function igSetup(address admin, MockedVault vault, AddressProvider ap, IHevm vm) public returns (address) {

        MockedIG ig = new MockedIG(address(vault), address(ap));

        bytes32 roleAdmin = ig.ROLE_ADMIN();
        bytes32 roleRoller = ig.ROLE_EPOCH_ROLLER();

        ig.grantRole(roleAdmin, admin);
        vm.prank(admin);
        ig.grantRole(roleRoller, admin);

        MockedRegistry registry = MockedRegistry(ap.registry());

        vm.prank(admin);
        registry.registerDVP(address(ig));

        vm.prank(admin);
        vault.setAllowedDVP(address(ig));

        return address(ig);
    }
}
