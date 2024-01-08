// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {IHevm} from "../utils/IHevm.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {AddressProviderUtils} from "../utils/AddressProviderUtils.sol";
import {EchidnaVaultUtils} from "../utils/EchidnaVaultUtils.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {MockedIG} from "../../mock/MockedIG.sol";

abstract contract Setup {
    address internal constant VM_ADDRESS_SETUP = address(uint160(uint256(keccak256("hevm cheat code"))));
    IHevm internal hevm;
    address internal alice = address(0xf9a);
    address internal bob = address(0xf9b);
    address internal tokenAdmin = address(0xf9c);
    MockedVault internal vault;
    MockedIG internal ig;
    TestnetToken baseToken;

    constructor() {
        hevm = IHevm(VM_ADDRESS_SETUP);
    }

    function deploy() internal {
        hevm.warp(EpochFrequency.REF_TS + 1);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), tokenAdmin);

        baseToken = new TestnetToken("BaseTestToken", "BTT");
        baseToken.setAddressProvider(address(ap));

        AddressProviderUtils.initialize(tokenAdmin, ap, address(baseToken), hevm);
        vault = MockedVault(EchidnaVaultUtils.createVault(address(baseToken), tokenAdmin, ap, EpochFrequency.DAILY));

        EchidnaVaultUtils.grantAdminRole(tokenAdmin, address(vault));
        EchidnaVaultUtils.registerVault(tokenAdmin, address(vault), ap, hevm);
        address sideToken = vault.sideToken();

        ig = MockedIG(EchidnaVaultUtils.igSetup(tokenAdmin, vault, ap, hevm));

        _impliedVolSetup(address(baseToken), sideToken, ap);

        skipDay(false);
        hevm.prank(tokenAdmin);
        ig.rollEpoch();
    }

    function skipTo(uint256 to) internal {
        hevm.warp(to);
    }

    function skipDay(bool additionalSecond) internal {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        hevm.warp(block.timestamp + 1 days + secondToAdd);
    }

    function skipWeek(bool additionalSecond) internal {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        hevm.warp(block.timestamp + 1 weeks + secondToAdd);
    }

    function _between(uint256 val, uint256 lower, uint256 upper) internal pure returns (uint256) {
        return lower + (val % (upper - lower + 1));
    }

    function _convertVm() internal returns (Vm) {
        return Vm(address(hevm));
    }

    function _impliedVolSetup(address baseToken_, address sideToken, AddressProvider ap) internal {
      MarketOracle apMarketOracle = MarketOracle(ap.marketOracle());
      uint256 lastUpdate = apMarketOracle.getImpliedVolatilityLastUpdate(baseToken_, sideToken, EpochFrequency.DAILY);
      if (lastUpdate == 0) {
          hevm.prank(tokenAdmin);
          apMarketOracle.setImpliedVolatility(baseToken_, sideToken, EpochFrequency.DAILY, 0.5e18);
      }
    }


}
