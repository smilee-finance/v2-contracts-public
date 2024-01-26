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
import {Parameters} from "../utils/Parameters.sol";
import {FeeManager} from "@project/FeeManager.sol";

abstract contract Setup is Parameters {
    event Debug(string);
    event DebugUInt(string, uint256);
    event DebugAddr(string, address);
    event DebugBool(string, bool);

    address internal constant VM_ADDRESS_SETUP = address(uint160(uint256(keccak256("hevm cheat code"))));
    IHevm internal hevm;

    address internal admin = address(0xf9c);

    MockedVault internal vault;
    MockedIG internal ig;
    AddressProvider ap;
    TestnetToken baseToken;

    constructor() {
        hevm = IHevm(VM_ADDRESS_SETUP);
    }

    function deploy() internal {
        hevm.warp(EpochFrequency.REF_TS + 1);
        ap = new AddressProvider(0);

        ap.grantRole(ap.ROLE_ADMIN(), admin);
        baseToken = new TestnetToken("BaseTestToken", "BTT");
        baseToken.transferOwnership(admin);
        hevm.prank(admin);
        baseToken.setAddressProvider(address(ap));

        AddressProviderUtils.initialize(admin, ap, address(baseToken), hevm);
        vault = MockedVault(EchidnaVaultUtils.createVault(address(baseToken), admin, ap, EpochFrequency.DAILY, hevm));

        EchidnaVaultUtils.grantAdminRole(admin, address(vault));
        EchidnaVaultUtils.registerVault(admin, address(vault), ap, hevm);
        address sideToken = vault.sideToken();

        ig = MockedIG(EchidnaVaultUtils.igSetup(admin, vault, ap, hevm));
        hevm.prank(admin);
        ig.setUseOracleImpliedVolatility(USE_ORACLE_IMPL_VOL);

        _impliedVolSetup(address(baseToken), sideToken, ap);
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

    function _convertVm() internal view returns (Vm) {
        return Vm(address(hevm));
    }

    function _impliedVolSetup(address baseToken_, address sideToken, AddressProvider _ap) internal {
      MarketOracle apMarketOracle = MarketOracle(_ap.marketOracle());
      uint256 lastUpdate = apMarketOracle.getImpliedVolatilityLastUpdate(baseToken_, sideToken, EpochFrequency.DAILY);
      if (lastUpdate == 0) {
          hevm.prank(admin);
          apMarketOracle.setImpliedVolatility(baseToken_, sideToken, EpochFrequency.DAILY, VOLATILITY);
      }
    }


}
