// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
// import {Epoch} from "@project/lib/EpochController.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {Vault} from "@project/Vault.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";

contract VaultDVPTest is Test {
    address admin;
    address dvp;
    TestnetToken baseToken;
    TestnetToken sideToken;
    AddressProvider addressProvider;
    TestnetPriceOracle priceOracle;

    Vault vault;

    bytes4 public constant ERR_DVP_ALREADY_SET = bytes4(keccak256("DVPAlreadySet()"));

    constructor() {
        admin = address(777);
        dvp = address(764);

        vm.startPrank(admin);
        addressProvider = new AddressProvider(0);
        addressProvider.grantRole(addressProvider.ROLE_ADMIN(), admin);
        vm.stopPrank();

        baseToken = TestnetToken(TokenUtils.create("USDC", 7, addressProvider, admin, vm));
        sideToken = TestnetToken(TokenUtils.create("WETH", 18, addressProvider, admin, vm));

        vm.startPrank(admin);

        baseToken.setTransferRestriction(false);
        sideToken.setTransferRestriction(false);

        // Needed by the exchange adapter:
        priceOracle = new TestnetPriceOracle(address(baseToken));
        priceOracle.setTokenPrice(address(sideToken), 1e18);
        addressProvider.setPriceOracle(address(priceOracle));

        TestnetSwapAdapter exchange = new TestnetSwapAdapter(addressProvider.priceOracle());
        addressProvider.setExchangeAdapter(address(exchange));

        // No fees by default:
        FeeManager feeManager = new FeeManager(0);
        feeManager.grantRole(feeManager.ROLE_ADMIN(), admin);
        addressProvider.setFeeManager(address(feeManager));

        vm.stopPrank();
    }

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);
        vm.startPrank(admin);
        vault = new Vault(
            address(baseToken),
            address(sideToken),
            EpochFrequency.DAILY,
            EpochFrequency.DAILY,
            address(addressProvider)
        );

        vault.grantRole(vault.ROLE_ADMIN(), admin);

        vault.setAllowedDVP(dvp);
        vm.stopPrank();
    }

    function testChangeAllowedDVP() public {
        address otherAddress = address(123);
        vm.prank(admin);
        vm.expectRevert(ERR_DVP_ALREADY_SET);
        vault.setAllowedDVP(otherAddress);
    }
}
