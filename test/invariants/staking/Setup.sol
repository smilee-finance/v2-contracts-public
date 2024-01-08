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
import {MasterChefSmilee} from "@project/periphery/MasterChefSmilee.sol";
import {MasterChefSmilee} from "@project/periphery/MasterChefSmilee.sol";
import {SimpleRewarderPerSec} from "@project/periphery/SimpleRewarderPerSec.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";

abstract contract Setup {
    address internal constant VM_ADDRESS_SETUP = address(uint160(uint256(keccak256("hevm cheat code"))));
    IHevm internal hevm;
    address internal alice = address(0xf9a);
    address internal bob = address(0xf9b);
    address internal tokenAdmin = address(0xf9c);

    MockedVault internal vault;
    MasterChefSmilee internal mcs;
    SimpleRewarderPerSec internal rewarder;
    uint256 internal smileePerSec = 1;

    constructor() {
        hevm = IHevm(VM_ADDRESS_SETUP);
    }

    function deploy() internal {
        hevm.warp(EpochFrequency.REF_TS + 1);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), tokenAdmin);

        TestnetToken baseToken = new TestnetToken("BaseTestToken", "BTT");
        baseToken.setAddressProvider(address(ap));

        AddressProviderUtils.initialize(tokenAdmin, ap, address(baseToken), hevm);
        vault = MockedVault(EchidnaVaultUtils.createVault(address(baseToken), tokenAdmin, ap, EpochFrequency.DAILY));

        EchidnaVaultUtils.grantAdminRole(tokenAdmin, address(vault));
        EchidnaVaultUtils.registerVault(tokenAdmin, address(vault), ap, hevm);
        EchidnaVaultUtils.grantEpochRollerRole(tokenAdmin, tokenAdmin, address(vault), hevm);
        address sideToken = vault.sideToken();

        _impliedVolSetup(address(baseToken), sideToken, ap);

        skipDay(false);
        EchidnaVaultUtils.rollEpoch(tokenAdmin, vault, hevm);

        VaultUtils.addVaultDeposit(alice, 100, address(this), address(vault), _convertVm());
        VaultUtils.addVaultDeposit(bob, 100, address(this), address(vault), _convertVm());

        skipDay(false);
        EchidnaVaultUtils.rollEpoch(tokenAdmin, vault, hevm);

        hevm.prank(alice);
        vault.redeem(100);

        hevm.prank(bob);
        vault.redeem(100);

        mcs = new MasterChefSmilee(smileePerSec, block.timestamp, ap);

        skipDay(false);
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

    function _impliedVolSetup(address baseToken, address sideToken, AddressProvider ap) internal {
      MarketOracle apMarketOracle = MarketOracle(ap.marketOracle());
      uint256 lastUpdate = apMarketOracle.getImpliedVolatilityLastUpdate(baseToken, sideToken, EpochFrequency.DAILY);
      if (lastUpdate == 0) {
          hevm.prank(tokenAdmin);
          apMarketOracle.setImpliedVolatility(baseToken, sideToken, EpochFrequency.DAILY, 0.5e18);
      }
    }
}
