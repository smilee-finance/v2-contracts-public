// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
// import {Epoch} from "@project/lib/EpochController.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {Vault} from "@project/Vault.sol";
import {VaultLib} from "@project/lib/VaultLib.sol";
import {Utils} from "../utils/Utils.sol";
import {VaultUtils} from "../utils/VaultUtils.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AmountsMath} from "@project/lib/AmountsMath.sol";


contract VaultDVPTest is Test {
    using AmountsMath for uint256;

    address admin;
    address dvp;
    address user;
    TestnetToken baseToken;
    TestnetToken sideToken;
    AddressProvider addressProvider;
    TestnetPriceOracle priceOracle;

    Vault vault;

    uint256 internal _toleranceBaseToken;
    uint256 internal _toleranceSideToken;

    bytes4 public constant ERR_DVP_ALREADY_SET = bytes4(keccak256("DVPAlreadySet()"));
    bytes4 public constant ERR_OUT_OF_ALLOWED_RANGE = bytes4(keccak256("OutOfAllowedRange()"));
    bytes4 public constant ERR_EPOCH_NOT_FINISHED = bytes4(keccak256("EpochNotFinished()"));
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    bytes32 public constant ROLE_EPOCH_ROLLER = keccak256("ROLE_EPOCH_ROLLER");
    bytes public ERR_NOT_ADMIN;
    bytes public ERR_NOT_EPOCH_ROLLER;

    constructor() {
        admin = address(777);
        dvp = address(764);
        user = address(644);

        ERR_NOT_ADMIN = abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(dvp),
                        " is missing role ",
                        Strings.toHexString(uint256(ROLE_ADMIN), 32)
                    );

        ERR_NOT_EPOCH_ROLLER = abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(admin),
                        " is missing role ",
                        Strings.toHexString(uint256(ROLE_EPOCH_ROLLER), 32)
                    );

        vm.startPrank(admin);
        addressProvider = new AddressProvider(0);
        addressProvider.grantRole(addressProvider.ROLE_ADMIN(), admin);
        vm.stopPrank();

        baseToken = TestnetToken(TokenUtils.create("USDC", 6, addressProvider, admin, vm));
        sideToken = TestnetToken(TokenUtils.create("WETH", 18, addressProvider, admin, vm));

        _toleranceBaseToken = 10 ** baseToken.decimals() / 1000;
        _toleranceSideToken = 10 ** sideToken.decimals() / 1000;

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
        FeeManager feeManager = new FeeManager(address(addressProvider), 0);
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

    function testChangeAllowedDVPNotAdmin() public {
        address otherAddress = address(123);
        vm.prank(dvp);
        vm.expectRevert(ERR_NOT_ADMIN);
        vault.setAllowedDVP(otherAddress);
    }

    function testChangeHedgeMargin(uint256 hedgeMargin) public {
        hedgeMargin = Utils.boundFuzzedValueToRange(hedgeMargin, 0, 1000);
        vm.prank(admin);
        vault.setHedgeMargin(hedgeMargin);
    }

    function testChangeHedgeMarginExeedAllowed() public {
        uint256 hedgeMargin = 1001;
        vm.prank(admin);
        vm.expectRevert(ERR_OUT_OF_ALLOWED_RANGE);
        vault.setHedgeMargin(hedgeMargin);
    }

    function testChangeHedgeMarginNotAdmin(uint256 hedgeMargin) public {
        hedgeMargin = Utils.boundFuzzedValueToRange(hedgeMargin, 0, 1000);
        vm.prank(dvp);
        vm.expectRevert(ERR_NOT_ADMIN);
        vault.setHedgeMargin(hedgeMargin);
    }

    function testChangeMaxDeposit(uint256 maxDeposit) public {
        assertEq(vault.maxDeposit(), 1_000_000_000 * (10 ** baseToken.decimals())); // default max deposit
        maxDeposit = Utils.boundFuzzedValueToRange(maxDeposit, 1, 2_000_000_000);
        maxDeposit = maxDeposit * (10 ** baseToken.decimals());
        vm.prank(admin);
        vault.setMaxDeposit(maxDeposit);
        assertEq(vault.maxDeposit(), maxDeposit);
    }

    function testChangeMaxDepositNotAdmin(uint256 maxDeposit) public {
        assertEq(vault.maxDeposit(), 1_000_000_000 * (10 ** baseToken.decimals())); // default max deposit
        maxDeposit = Utils.boundFuzzedValueToRange(maxDeposit, 1, 2_000_000_000);
        maxDeposit = maxDeposit * (10 ** baseToken.decimals());
        vm.prank(dvp);
        vm.expectRevert(ERR_NOT_ADMIN);
        vault.setMaxDeposit(maxDeposit);
    }

    function testChangePausedState() public {
        bool paused = vault.paused();
        vm.prank(admin);
        vault.changePauseState();
        assertEq(!paused, vault.paused());
    }

    function testChangePausedStateNotAdmin() public {
        vm.prank(dvp);
        vm.expectRevert(ERR_NOT_ADMIN);
        vault.changePauseState();
    }

    function testKillVault() public {
        VaultLib.VaultState memory state = VaultUtils.getState(vault);
        assertEq(false, state.killed);
        vm.prank(admin);
        vault.killVault();
        state = VaultUtils.getState(vault);
        assertEq(true, state.killed);
    }

    function testKillVaultNotAdmin() public {
        vm.prank(dvp);
        vm.expectRevert(ERR_NOT_ADMIN);
        vault.killVault();
    }

    function testChangePriorityAccessFlag() public {
        vm.prank(admin);
        vault.setPriorityAccessFlag(true);
        assertEq(true, vault.priorityAccessFlag());
        vm.prank(admin);
        vault.setPriorityAccessFlag(false);
        assertEq(false, vault.priorityAccessFlag());
    }

    function testChangePriorityAccessFlagNotAdmin(bool flag) public {
        vm.prank(dvp);
        vm.expectRevert(ERR_NOT_ADMIN);
        vault.setPriorityAccessFlag(flag);
    }

    function testEmergencyRebalance(uint256 amount, uint256 sideTokenPrice) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        // First epoch with deposit:
        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        // In order to buy side token for base token the price need to go down
        sideTokenPrice = Utils.boundFuzzedValueToRange(sideTokenPrice, 0.001e18, 1_000e18);
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        // NOTE: ignoring pendings as we know that there are no ones
        uint256 baseTokenBalance = baseToken.balanceOf(address(vault));
        uint256 sideTokenBalance = AmountsMath.wrapDecimals(sideToken.balanceOf(address(vault)), sideToken.decimals());

        assertApproxEqAbs(amount / 2, baseTokenBalance, _toleranceBaseToken);
        assertApproxEqAbs(AmountsMath.unwrapDecimals(AmountsMath.wrapDecimals(amount / 2, baseToken.decimals()), sideToken.decimals()), sideTokenBalance, _toleranceSideToken);

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(admin);
        vault.emergencyRebalance();

        uint256 swappedSideTokenValue = AmountsMath.unwrapDecimals(sideTokenBalance.wmul(sideTokenPrice), baseToken.decimals());
        uint256 baseTokenBalanceAfterRebalance = baseTokenBalance + swappedSideTokenValue;

        assertApproxEqAbs(baseTokenBalanceAfterRebalance, baseToken.balanceOf(address(vault)), _toleranceBaseToken);
        assertEq(0, sideToken.balanceOf(address(vault)));
    }

    function testEmergencyRebalanceEpochNotFinished(uint256 amount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        // First epoch with deposit:
        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.prank(admin);
        vm.expectRevert(ERR_EPOCH_NOT_FINISHED);
        vault.emergencyRebalance();
    }

    function testEmergencyRebalanceEpochNotAdmin(uint256 amount) public {
        uint256 minAmount = 10 ** baseToken.decimals();
        amount = Utils.boundFuzzedValueToRange(amount, minAmount, vault.maxDeposit());

        // First epoch with deposit:
        vm.prank(admin);
        baseToken.mint(user, amount);

        vm.startPrank(user);
        baseToken.approve(address(vault), amount);
        vault.deposit(amount, user, 0);
        vm.stopPrank();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vault.rollEpoch();

        vm.warp(vault.getEpoch().current + 1);
        vm.prank(dvp);
        vm.expectRevert(ERR_NOT_ADMIN);
        vault.emergencyRebalance();
    }

    /**
     * Test admin can grant epoch roller role to himself, can roll epoch and then renunce role
     */
    function testAdminGrantRoleAndCanRollEpoch() public {
        vm.startPrank(admin);

        vault.grantRole(ROLE_EPOCH_ROLLER, admin);

        vm.warp(vault.getEpoch().current + 1);
        vault.rollEpoch();

        vault.renounceRole(ROLE_EPOCH_ROLLER, admin);

        vm.warp(vault.getEpoch().current + 1);
        vm.expectRevert(ERR_NOT_EPOCH_ROLLER);
        vault.rollEpoch();

        vm.stopPrank();
    }
}
