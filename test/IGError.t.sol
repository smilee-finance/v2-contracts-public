// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "@project/interfaces/IPositionManager.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {OptionStrategy} from "@project/lib/OptionStrategy.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {Vault} from "@project/Vault.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {MockedVault} from "./mock/MockedVault.sol";

/**
    @title Test case for underlying asset going to zero
    @dev This should never happen, still we need to test shares value goes to zero, users deposits can be rescued and
         new deposits are not allowed
 */
contract IGErrorTest is Test {

    address admin = address(0x1);

    // User of Vault
    address alice = address(0x2);

    //User of DVP
    address charlie = address(0x4);

    AddressProvider ap;
    TestnetToken baseToken;
    TestnetToken sideToken;
    FeeManager feeManager;
    TestnetPriceOracle po;

    MockedRegistry registry;

    MockedVault vault;
    MockedIG ig;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);
        //ToDo: Replace with Factory
        vm.startPrank(admin);
        ap = new AddressProvider(0);
        registry = new MockedRegistry();
        ap.grantRole(ap.ROLE_ADMIN(), admin);
        registry.grantRole(registry.ROLE_ADMIN(), admin);
        ap.setRegistry(address(registry));
        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));

        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vm.startPrank(admin);
        ig = new MockedIG(address(vault), address(ap));
        ig.grantRole(ig.ROLE_ADMIN(), admin);
        ig.grantRole(ig.ROLE_EPOCH_ROLLER(), admin);
        vault.grantRole(vault.ROLE_ADMIN(), admin);
        vm.stopPrank();

        VaultUtils.addVaultDeposit(alice, 15000000e18, admin, address(vault), vm);
        po = TestnetPriceOracle(ap.priceOracle());
        MarketOracle ocl = MarketOracle(ap.marketOracle());

        vm.startPrank(admin);
        ig.setTradeVolatilityUtilizationRateFactor(2e18);
        ig.setTradeVolatilityTimeDecay(0.25e18);
        ig.setSigmaMultiplier(3e18);
        ocl.setImpliedVolatility(address(baseToken), address(sideToken), EpochFrequency.DAILY, 50e17);

        po.setTokenPrice(address(sideToken), 2000e18);
        vm.stopPrank();

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();

        vm.prank(admin);
        registry.registerDVP(address(ig));
        vm.prank(admin);
        MockedVault(vault).setAllowedDVP(address(ig));
        feeManager = FeeManager(ap.feeManager());
    }

    function testBuySellPremium0Scenario1() public {
        uint256 premium;

        //vm.warp(block.timestamp + 86000);

        uint256 prezzo = 2000e18;
        while (prezzo > 0) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            (premium, ) = _assurePremium(charlie, 2000e18, 1e18, 0);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 1e18, 0, premium, 0.1e18);
            prezzo -= 20e18;
            console.log(prezzo);
        }

        // console.log(ig.currentEpoch());
        // console.log(block.timestamp);

        // vm.prank(admin);
        // po.setTokenPrice(address(sideToken), 1870e18);

        // (uint256 premiumUp, uint256 premiumDown) = ig.premium(2000, 15e18, 0);
        // console.log(premiumUp, premiumDown);
        // (premiumUp, premiumDown) = ig.premium(2000, 0, 15e18);
        // console.log(premiumUp, premiumDown);

        // vm.startPrank(charlie);
        // (uint256 payoff, ) = ig.payoff(ig.currentEpoch(), 2000e18, 0, 15e18);
        // vm.stopPrank();

        // vm.prank(charlie);
        // ig.burn(ig.currentEpoch(), charlie, 2000e18, 0, 15e18, payoff, 0.1e18);

        // (premium_, ) = _assurePremium(charlie, 2000e18, 15e18, 0);

        // vm.prank(charlie);
        // ig.mint(charlie, 2000e18, 15e18, 0, premium_, 0.1e18);
    }

    function testBuySellPremium0Scenario2() public {
        vm.warp(block.timestamp + 86340);

        vm.prank(admin);
        po.setTokenPrice(address(sideToken), 50e18);

        (uint256 premiumUp, uint256 premiumDown) = ig.premium(2000, 15e18, 0);
        console.log(premiumUp, premiumDown);
        (premiumUp, premiumDown) = ig.premium(2000, 0, 15e18);
        console.log(premiumUp, premiumDown);

        (uint256 premium_, ) = _assurePremium(charlie, 2000e18, 0, 15e18);

        vm.prank(charlie);
        ig.mint(charlie, 2000e18, 0, 15e18, premium_, 0.1e18);

        (premium_, ) = _assurePremium(charlie, 2000e18, 15e18, 0);

        vm.prank(charlie);
        ig.mint(charlie, 2000e18, 15e18, 0, premium_, 0.1e18);
    }

    function testBuySellPremium0Scenario21() public {
        uint256 premium;

        //vm.warp(block.timestamp + 86340);

        uint256 prezzo = 2000e18;
        while (prezzo < 100000e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            (premium, ) = _assurePremium(charlie, 2000e18, 0, 1e18);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 0, 1e18, premium, 0.1e18);
            prezzo += 20e18;
            //console.log(prezzo);
        }

        // console.log(ig.currentEpoch());
        // console.log(block.timestamp);

        // vm.prank(admin);
        // po.setTokenPrice(address(sideToken), 1870e18);

        // (uint256 premiumUp, uint256 premiumDown) = ig.premium(2000, 15e18, 0);
        // console.log(premiumUp, premiumDown);
        // (premiumUp, premiumDown) = ig.premium(2000, 0, 15e18);
        // console.log(premiumUp, premiumDown);

        // vm.startPrank(charlie);
        // (uint256 payoff, ) = ig.payoff(ig.currentEpoch(), 2000e18, 0, 15e18);
        // vm.stopPrank();

        // vm.prank(charlie);
        // ig.burn(ig.currentEpoch(), charlie, 2000e18, 0, 15e18, payoff, 0.1e18);

        // (premium_, ) = _assurePremium(charlie, 2000e18, 15e18, 0);

        // vm.prank(charlie);
        // ig.mint(charlie, 2000e18, 15e18, 0, premium_, 0.1e18);
    }

    function testBuySellPremium0Scenario3() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo > 300e18) {
            // vm.startPrank(admin);
            // po.setTokenPrice(address(sideToken), prezzo);
            // vm.stopPrank();

            (premium, ) = _assurePremium(charlie, 2000e18, 1e18, 0);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 1e18, 0, premium, 0.1e18);
            prezzo -= 20e18;
            //console.log(prezzo);
        }

        prezzo = 2000e18;
        uint256 epoch = ig.currentEpoch();

        vm.warp(block.timestamp + 86340);
        while (prezzo > 300e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            vm.startPrank(charlie);
            (premium, ) = ig.payoff(epoch, 2000e18, 1e18, 0);
            ig.burn(epoch, charlie, 2000e18, 1e18, 0, premium, 0.1e18);
            vm.stopPrank();
            prezzo -= 20e18;
            console.log(prezzo);
        }

        // console.log(ig.currentEpoch());
        // console.log(block.timestamp);

        // vm.prank(admin);
        // po.setTokenPrice(address(sideToken), 1870e18);

        // (uint256 premiumUp, uint256 premiumDown) = ig.premium(2000, 15e18, 0);
        // console.log(premiumUp, premiumDown);
        // (premiumUp, premiumDown) = ig.premium(2000, 0, 15e18);
        // console.log(premiumUp, premiumDown);

        // vm.startPrank(charlie);
        // (uint256 payoff, ) = ig.payoff(ig.currentEpoch(), 2000e18, 0, 15e18);
        // vm.stopPrank();

        // vm.prank(charlie);
        // ig.burn(ig.currentEpoch(), charlie, 2000e18, 0, 15e18, payoff, 0.1e18);

        // (premium_, ) = _assurePremium(charlie, 2000e18, 15e18, 0);

        // vm.prank(charlie);
        // ig.mint(charlie, 2000e18, 15e18, 0, premium_, 0.1e18);
    }

    function testBuySellPremium0Scenario31() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo > 300e18) {
            // vm.startPrank(admin);
            // po.setTokenPrice(address(sideToken), prezzo);
            // vm.stopPrank();

            (premium, ) = _assurePremium(charlie, 2000e18, 1e18, 0);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 1e18, 0, premium, 0.1e18);
            prezzo -= 20e18;
            //console.log(prezzo);
        }

        prezzo = 2000e18;
        uint256 epoch = ig.currentEpoch();

        vm.warp(block.timestamp + 3600);
        while (prezzo > 300e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            vm.startPrank(charlie);
            (premium, ) = ig.payoff(epoch, 2000e18, 1e18, 0);
            ig.burn(epoch, charlie, 2000e18, 1e18, 0, premium, 0.1e18);
            vm.stopPrank();
            prezzo -= 20e18;
            console.log(prezzo);
        }
    }

    function testBuySellPremium0Scenario4() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo < 50000e18) {
            // vm.startPrank(admin);
            // po.setTokenPrice(address(sideToken), prezzo);
            // vm.stopPrank();

            (premium, ) = _assurePremium(charlie, 2000e18, 0, 1e18);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 0, 1e18, premium, 0.1e18);
            prezzo += 20e18;
            //console.log(prezzo);
        }

        prezzo = 2000e18;
        uint256 epoch = ig.currentEpoch();

        vm.warp(block.timestamp + 86340);
        while (prezzo < 50000e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            vm.startPrank(charlie);
            (uint256 payoff, ) = ig.payoff(epoch, 2000e18, 0, 1e18);
            ig.burn(epoch, charlie, 2000e18, 0, 1e18, payoff, 0.1e18);
            vm.stopPrank();
            prezzo += 20e18;
            console.log(prezzo);
        }

        // console.log(ig.currentEpoch());
        // console.log(block.timestamp);

        // vm.prank(admin);
        // po.setTokenPrice(address(sideToken), 1870e18);

        // (uint256 premiumUp, uint256 premiumDown) = ig.premium(2000, 15e18, 0);
        // console.log(premiumUp, premiumDown);
        // (premiumUp, premiumDown) = ig.premium(2000, 0, 15e18);
        // console.log(premiumUp, premiumDown);

        // vm.startPrank(charlie);
        // (uint256 payoff, ) = ig.payoff(ig.currentEpoch(), 2000e18, 0, 15e18);
        // vm.stopPrank();

        // vm.prank(charlie);
        // ig.burn(ig.currentEpoch(), charlie, 2000e18, 0, 15e18, payoff, 0.1e18);

        // (premium_, ) = _assurePremium(charlie, 2000e18, 15e18, 0);

        // vm.prank(charlie);
        // ig.mint(charlie, 2000e18, 15e18, 0, premium_, 0.1e18);
    }

    function testBuySellPremium0Scenario41() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo < 50000e18) {
            // vm.startPrank(admin);
            // po.setTokenPrice(address(sideToken), prezzo);
            // vm.stopPrank();

            (premium, ) = _assurePremium(charlie, 2000e18, 0, 1e18);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 0, 1e18, premium, 0.1e18);
            prezzo += 20e18;
            //console.log(prezzo);
        }

        prezzo = 2000e18;
        uint256 epoch = ig.currentEpoch();

        vm.warp(block.timestamp + 3600);
        while (prezzo < 50000e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            vm.startPrank(charlie);
            (uint256 payoff, ) = ig.payoff(epoch, 2000e18, 0, 1e18);
            ig.burn(epoch, charlie, 2000e18, 0, 1e18, payoff, 0.1e18);
            vm.stopPrank();
            prezzo += 20e18;
            console.log(prezzo);
        }
    }

    function _assurePremium(
        address user,
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) private returns (uint256 premium_, uint256 fee) {
        (premium_, fee) = ig.premium(strike, amountUp, amountDown);
        TokenUtils.provideApprovedTokens(admin, address(baseToken), user, address(ig), premium_, vm);
    }
}
