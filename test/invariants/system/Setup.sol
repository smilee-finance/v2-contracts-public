// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {IHevm} from "../utils/IHevm.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {AddressProviderUtils} from "../lib/AddressProviderUtils.sol";
import {EchidnaVaultUtils} from "../lib/EchidnaVaultUtils.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {MockedIG} from "../../mock/MockedIG.sol";
import {Parameters} from "../utils/scenarios/Parameters.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";

abstract contract Setup is Parameters {
    event Debug(string);
    event DebugUInt(string, uint256);
    event DebugAddr(string, address);
    event DebugBool(string, bool);

    // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);

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
        baseToken.setDecimals(BASE_TOKEN_DECIMALS);
        baseToken.transferOwnership(admin);
        hevm.prank(admin);
        baseToken.setAddressProvider(address(ap));

        AddressProviderUtils.initialize(admin, ap, address(baseToken), FLAG_SLIPPAGE, hevm);
        EPOCH_FREQUENCY = EpochFrequency.DAILY;
        vault = MockedVault(EchidnaVaultUtils.createVault(address(baseToken), admin, SIDE_TOKEN_DECIMALS, INITIAL_TOKEN_PRICE, ap, EPOCH_FREQUENCY, hevm));

        EchidnaVaultUtils.grantAdminRole(admin, address(vault));
        EchidnaVaultUtils.registerVault(admin, address(vault), ap, hevm);
        address sideToken = vault.sideToken();

        ig = MockedIG(EchidnaVaultUtils.igSetup(admin, vault, ap, hevm));
        hevm.prank(admin);
        ig.setUseOracleImpliedVolatility(USE_ORACLE_IMPL_VOL);

        MarketOracle marketOracle = MarketOracle(ap.marketOracle());
        uint256 frequency = ig.getEpoch().frequency;
        hevm.prank(admin);
        marketOracle.setDelay(address(baseToken), sideToken, frequency, 0, true);

        _impliedVolSetup(address(baseToken), sideToken, ap);

        if (INITIAL_VAULT_DEPOSIT > 0) {
            VaultUtils.addVaultDeposit(USER1, INITIAL_VAULT_DEPOSIT, admin, address(vault), _convertVm());
        }
    }

    function _between(uint256 val, uint256 lower, uint256 upper) internal pure returns (uint256) {
        return lower + (val % (upper - lower + 1));
    }

    function _convertVm() internal view returns (Vm) {
        return Vm(address(hevm));
    }

    function _impliedVolSetup(address baseToken_, address sideToken, AddressProvider _ap) internal {
        MarketOracle apMarketOracle = MarketOracle(_ap.marketOracle());
        uint256 lastUpdate = apMarketOracle.getImpliedVolatilityLastUpdate(baseToken_, sideToken, EPOCH_FREQUENCY);
        if (lastUpdate == 0) {
            hevm.prank(admin);
            apMarketOracle.setImpliedVolatility(baseToken_, sideToken, EPOCH_FREQUENCY, VOLATILITY);
        }
    }
}
