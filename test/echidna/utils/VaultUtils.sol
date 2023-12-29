// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IHevm} from "../IHevm.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {AddressProviderUtils} from "./AddressProviderUtils.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {TestnetPriceOracle} from "../../../src/testnet/TestnetPriceOracle.sol";
import {MockedRegistry} from "../../mock/MockedRegistry.sol";

library EchidnaVaultUtils {
    function createVault(
        address tokenAdmin,
        AddressProvider addressProvider,
        uint256 epochFrequency,
        IHevm vm
    ) public returns (address) {
        TestnetToken baseToken = new TestnetToken("BaseTestToken", "BTT");
        baseToken.setAddressProvider(address(addressProvider));
        TestnetToken sideToken = new TestnetToken("SideTestToken", "STT");
        sideToken.setAddressProvider(address(addressProvider));

        AddressProviderUtils.initialize(tokenAdmin, addressProvider, address(baseToken), vm);

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
}
