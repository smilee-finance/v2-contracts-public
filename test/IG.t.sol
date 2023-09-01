// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";

contract IGTest is Test {
    bytes4 constant EpochNotInitialized = bytes4(keccak256("EpochNotInitialized()"));
    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));
    bytes constant IGPaused = bytes("Pausable: paused");
    bytes constant OwnerError = bytes("Ownable: caller is not the owner");
    bytes4 constant SlippedMarketValue = bytes4(keccak256("SlippedMarketValue()"));

    address baseToken;
    address sideToken;
    MockedVault vault;
    TestnetRegistry registry;
    MockedIG ig;
    AddressProvider ap;

    address admin = address(0x10);
    address alice = address(0x1);
    address bob = address(0x2);

    constructor() {
        vm.startPrank(admin);
        ap = new AddressProvider();
        registry = new TestnetRegistry();
        ap.setRegistry(address(registry));
        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));

        baseToken = vault.baseToken();
        sideToken = vault.sideToken();
    }

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS + 1);
        vm.startPrank(admin);
        ig = new MockedIG(address(vault), address(ap));
        registry.register(address(ig));
        MockedVault(vault).setAllowedDVP(address(ig));
        vm.stopPrank();
        ig.useFakeDeltaHedge();

        // Roll first epoch (this enables deposits)
        Utils.skipDay(false, vm);
        ig.rollEpoch();

        // Suppose Vault has already liquidity
        VaultUtils.addVaultDeposit(alice, 100 ether, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        ig.rollEpoch();
    }

    // ToDo: review with a different vault
    // function testCantCreate() public {
    //     vm.expectRevert(AddressZero);
    //   //     new MockedIG(address(vault));
    // }

    // ToDo: Add test for rollEpoch before will become active

    function testCantUse() public {
        IDVP ig_ = new MockedIG(address(vault), address(ap));

        vm.expectRevert(EpochNotInitialized);
        ig_.mint(address(0x1), 0, OptionStrategy.CALL, 1, 0);
    }

    function testCanUse() public {
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), 1, vm);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, 1, 0);
    }

    function testMint() public {
        uint256 inputAmount = 1 ether;

        // ToDo: review with premium
        // uint256 expectedPremium = ig.premium(0, OptionStrategy.CALL, inputAmount);
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        uint256 expectedMarketValue = ig.premium(0, OptionStrategy.CALL, inputAmount);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        bytes32 posId = keccak256(abi.encodePacked(alice, OptionStrategy.CALL, ig.currentStrike()));

        (uint256 amount, bool strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testMintSum() public {
        uint256 inputAmount = 1 ether;

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        uint256 expectedMarketValue = ig.premium(0, OptionStrategy.CALL, inputAmount);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        expectedMarketValue = ig.premium(0, OptionStrategy.CALL, inputAmount);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        bytes32 posId = keccak256(abi.encodePacked(alice, OptionStrategy.CALL, ig.currentStrike()));
        (uint256 amount, bool strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(2 * inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testMintAndBurn() public {
        uint256 inputAmount = 1 ether;

        //MockedIG ig = new MockedIG(address(vault));
        uint256 currEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);
        uint256 expectedMarketValue = ig.premium(strike, OptionStrategy.CALL, inputAmount);
        vm.prank(alice);
        ig.mint(alice, strike, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);
        expectedMarketValue = ig.premium(strike, OptionStrategy.CALL, inputAmount);
        vm.prank(alice);
        ig.mint(alice, strike, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        vm.prank(alice);
        expectedMarketValue = ig.payoff(currEpoch, strike, OptionStrategy.CALL, inputAmount);
        vm.prank(alice);
        ig.burn(currEpoch, alice, strike, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        bytes32 posId = keccak256(abi.encodePacked(alice, OptionStrategy.CALL, ig.currentStrike()));

        (uint256 amount, bool strategy, uint256 pStrike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(strike, pStrike);
        assertEq(inputAmount, amount);
        assertEq(currEpoch, epoch);
    }

    function testMintMultiple() public {
        bool aInputStrategy = OptionStrategy.CALL;
        bool bInputStrategy = OptionStrategy.PUT;
        uint256 inputAmount = 1;
        uint256 currEpoch = ig.currentEpoch();

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        vm.prank(alice);
        ig.mint(alice, 0, aInputStrategy, inputAmount, 0);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, bob, address(ig), inputAmount, vm);

        vm.prank(bob);
        ig.mint(bob, 0, bInputStrategy, inputAmount, 0);

        uint256 strike = ig.currentStrike();

        bytes32 posId1 = keccak256(abi.encodePacked(alice, aInputStrategy, strike));
        bytes32 posId2 = keccak256(abi.encodePacked(bob, bInputStrategy, strike));

        {
            (uint256 amount1, bool strategy1, , ) = ig.positions(posId1);
            assertEq(aInputStrategy, strategy1);
            assertEq(inputAmount, amount1);
        }

        {
            (uint256 amount2, bool strategy2, , ) = ig.positions(posId2);
            assertEq(bInputStrategy, strategy2);
            assertEq(inputAmount, amount2);
        }

        vm.prank(alice);
        ig.burn(currEpoch, alice, strike, aInputStrategy, inputAmount, 0);
        vm.prank(bob);
        ig.burn(currEpoch, bob, strike, bInputStrategy, inputAmount, 0);

        {
            (uint256 amount1, , , ) = ig.positions(posId1);
            assertEq(0, amount1);
        }

        {
            (uint256 amount2, , , ) = ig.positions(posId2);
            assertEq(0, amount2);
        }
    }

    function testCantMintZero() public {
        vm.expectRevert(AmountZero);
        ig.mint(alice, 0, OptionStrategy.CALL, 0, 0);
    }

    function testCantBurnMoreThanMinted() public {
        uint256 inputAmount = 1e18;

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        uint256 strike = ig.currentStrike();
        uint256 epoch = ig.currentEpoch();

        uint256 expectedMarketValue = ig.premium(strike, OptionStrategy.CALL, inputAmount);
        vm.prank(alice);
        ig.mint(alice, strike, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        vm.prank(alice);
        // TBD: the inputAmount cannot be used wrong as it cause an arithmetic over/underflow...
        expectedMarketValue = ig.payoff(epoch, strike, OptionStrategy.CALL, inputAmount);
        vm.prank(alice);
        vm.expectRevert(CantBurnMoreThanMinted);
        ig.burn(epoch, alice, strike, OptionStrategy.CALL, inputAmount + 1e18, expectedMarketValue);
    }

    function testIGPaused() public {
        uint256 inputAmount = 1 ether;
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        assertEq(ig.isPaused(), false);

        vm.expectRevert(OwnerError);
        ig.changePauseState();

        vm.prank(admin);
        ig.changePauseState();
        assertEq(ig.isPaused(), true);

        vm.startPrank(alice);
        uint256 expectedMarketValue = ig.premium(0, OptionStrategy.CALL, inputAmount);
        vm.expectRevert(IGPaused);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount, expectedMarketValue);
        vm.stopPrank();

        uint256 epoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        vm.prank(admin);
        ig.changePauseState();
        expectedMarketValue = ig.premium(0, OptionStrategy.CALL, inputAmount);
        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount, expectedMarketValue);
        vm.prank(admin);
        ig.changePauseState();
        vm.startPrank(alice);
        expectedMarketValue = ig.payoff(epoch, strike, OptionStrategy.CALL, inputAmount);
        vm.expectRevert(IGPaused);
        ig.burn(epoch, alice, strike, OptionStrategy.CALL, inputAmount, expectedMarketValue);
        vm.stopPrank();

        Utils.skipDay(true, vm);

        vm.expectRevert(IGPaused);
        ig.rollEpoch();

        // From here on, all the IG functions should work properly
        vm.prank(admin);
        ig.changePauseState();
        assertEq(ig.isPaused(), false);

        ig.rollEpoch();

        epoch = ig.currentEpoch();
        strike = ig.currentStrike();

        expectedMarketValue = ig.premium(0, OptionStrategy.CALL, inputAmount);
        vm.startPrank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        expectedMarketValue = ig.payoff(epoch, strike, OptionStrategy.CALL, inputAmount);
        ig.burn(epoch, alice, strike, OptionStrategy.CALL, inputAmount, expectedMarketValue);
        vm.stopPrank();
    }

    function testRollEpochWhenDVPHasJumpedSomeRolls() public {
        uint256 previousEpoch = ig.currentEpoch();
        uint256 firstExpiry = EpochFrequency.nextExpiry(previousEpoch, EpochFrequency.DAILY);
        uint256 secondExpiry = EpochFrequency.nextExpiry(firstExpiry, EpochFrequency.DAILY);
        uint256 thirdExpiry = EpochFrequency.nextExpiry(secondExpiry, EpochFrequency.DAILY);
        Utils.skipDay(true, vm);
        Utils.skipDay(true, vm);
        Utils.skipDay(true, vm);

        uint256 epochNumbers = ig.getNumberOfEpochs();
        assertEq(epochNumbers, 2);



        ig.rollEpoch();
        uint256 nextEpoch = ig.currentEpoch();
        uint256 lastEpoch = ig.lastRolledEpoch();
        (, uint256 epochNumbers_) = ig.getEpochs();
    

        assertEq(epochNumbers_, 3);
        assertEq(previousEpoch, lastEpoch);
        assertNotEq(nextEpoch, firstExpiry);
        assertNotEq(nextEpoch, secondExpiry);
        assertEq(nextEpoch, thirdExpiry);
    }

    function testSetTradeVolatilityParams() public {
        vm.expectRevert(OwnerError);
        ig.setTradeVolatilityTimeDecay(25e16);

        vm.expectRevert(OwnerError);
        ig.setTradeVolatilityUtilizationRateFactor(25e16);

        vm.startPrank(admin);        
        ig.setTradeVolatilityUtilizationRateFactor(25e16);
        ig.setTradeVolatilityTimeDecay(25e16);
        vm.stopPrank();
    }

    function testMintWithSlippage() public {
        uint256 inputAmount = 1 ether;

        // ToDo: review with premium
        // uint256 expectedPremium = ig.premium(0, OptionStrategy.CALL, inputAmount);
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        uint256 expectedMarketValue = ig.premium(0, OptionStrategy.CALL, inputAmount);

        ig.setOptionPrice(20e18);

        vm.prank(alice);
        vm.expectRevert(SlippedMarketValue);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount, expectedMarketValue);
    }

    function testBurnWithSlippage() public {
        uint256 inputAmount = 1 ether;

        //MockedIG ig = new MockedIG(address(vault));
        uint256 currEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);
        uint256 expectedMarketValue = ig.premium(strike, OptionStrategy.CALL, inputAmount);
        vm.prank(alice);
        ig.mint(alice, strike, OptionStrategy.CALL, inputAmount, expectedMarketValue);

        vm.prank(alice);
        expectedMarketValue = ig.payoff(currEpoch, strike, OptionStrategy.CALL, inputAmount);

        vm.expectRevert(SlippedMarketValue);
        vm.prank(alice);
        ig.burn(currEpoch, alice, strike, OptionStrategy.CALL, inputAmount, 20e18);
    }
}
