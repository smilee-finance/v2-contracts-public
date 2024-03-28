// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IDVP} from "@project/interfaces/IDVP.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {OptionStrategy} from "@project/lib/OptionStrategy.sol";
import {TimeLockedFinanceParameters, TimeLockedFinanceValues} from "@project/lib/FinanceIG.sol";
import {TimeLock, TimeLockedBool, TimeLockedUInt} from "@project/lib/TimeLock.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {DVPUtils} from "./utils/DVPUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Amount} from "@project/lib/Amount.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract IGTest is Test {
    using TimeLock for TimeLockedBool;
    using TimeLock for TimeLockedUInt;

    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant AsymmetricAmount = bytes4(keccak256("AsymmetricAmount()"));
    bytes4 constant PositionNotFound = bytes4(keccak256("PositionNotFound()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));
    bytes4 constant NotEnoughNotional = bytes4(keccak256("NotEnoughNotional()"));
    bytes4 constant EpochFinished = bytes4(keccak256("EpochFinished()"));
    bytes4 constant SlippedMarketValue = bytes4(keccak256("SlippedMarketValue()"));
    bytes constant IGPaused = bytes("Pausable: paused");
    bytes public ERR_NOT_ADMIN;
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    uint256 MIN_MINT;

    address baseToken;
    address sideToken;
    MockedVault vault;
    MockedRegistry registry;
    MockedIG ig;
    AddressProvider ap;
    FeeManager feeManager;

    address admin = address(0x10);
    address alice = address(0x1);
    address bob = address(0x2);

    constructor() {
        vm.warp(EpochFrequency.REF_TS);
        vm.startPrank(admin);
        ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), admin);
        registry = new MockedRegistry();
        registry.grantRole(registry.ROLE_ADMIN(), admin);
        ap.setRegistry(address(registry));
        vm.stopPrank();

        feeManager = FeeManager(ap.feeManager());

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        baseToken = vault.baseToken();
        sideToken = vault.sideToken();

        uint256 btUnit = 10 ** IERC20Metadata(baseToken).decimals();
        MIN_MINT = btUnit; // 0.1

        ERR_NOT_ADMIN = abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(alice),
                        " is missing role ",
                        Strings.toHexString(uint256(ROLE_ADMIN), 32)
                    );
    }

    function setUp() public {
        vm.startPrank(admin);
        ig = new MockedIG(address(vault), address(ap));
        ig.grantRole(ig.ROLE_ADMIN(), admin);
        ig.grantRole(ig.ROLE_EPOCH_ROLLER(), admin);
        ig.grantRole(ig.ROLE_TRADER(), alice);
        ig.grantRole(ig.ROLE_TRADER(), bob);
        vault.grantRole(vault.ROLE_ADMIN(), admin);

        FeeManager(ap.feeManager()).setDVPFee(
            address(ig),
            FeeManager.FeeParams(3600, 0, 0, 0, 0.0035e18, 0.125e18, 0.0015e18, 0.125e18)
        );

        registry.register(address(ig));
        MockedVault(vault).setAllowedDVP(address(ig));
        vm.stopPrank();

        ig.useFakeDeltaHedge();

        // Suppose Vault has already liquidity
        VaultUtils.addVaultDeposit(alice, 100 ether, admin, address(vault), vm);

        DVPUtils.disableOracleDelayForIG(ap, ig, admin, vm);

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();
    }

    // ToDo: review with a different vault
    // function testCantCreate() public {
    //     vm.expectRevert(AddressZero);
    //   //     new MockedIG(address(vault));
    // }

    function testCanUse() public {
        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(ig), 1, vm);

        uint256 strike = ig.currentStrike();
        vm.prank(alice);
        ig.mint(alice, strike, 1, 0, 0, 0.1e18);
    }

    function testMint(uint256 inputAmount) public {
        (, , , uint256 bullAvailNotional) = ig.notional();
        inputAmount = Utils.boundFuzzedValueToRange(inputAmount, MIN_MINT, bullAvailNotional);

        uint256 strikeMint = ig.currentStrike();
        (uint256 expectedMarketValue, ) = ig.premium(strikeMint, inputAmount, 0);

        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(ig), expectedMarketValue, vm);
        uint256 strike = ig.currentStrike();

        vm.prank(alice);
        ig.mint(alice, strikeMint, inputAmount, 0, expectedMarketValue, 0.1e18);

        bytes32 posId = keccak256(abi.encodePacked(alice, strike));

        (uint256 amount, bool strategy, uint256 posStrike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), posStrike);
        assertEq(inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testCantMintWithoutNFT() public {
        // [TODO] Need to mint NFT before
    }

    function testCantMintZero() public {
        uint256 strike = ig.currentStrike();
        vm.prank(alice);
        vm.expectRevert(AmountZero);
        ig.mint(alice, strike, 0, 0, 0, 0.1e18);
    }

    function testCantMintAfterEpochFinished() public {
        uint256 strike = ig.currentStrike();

        vm.warp(ig.currentEpoch() + 1);
        vm.prank(alice);
        vm.expectRevert(EpochFinished);
        ig.mint(alice, strike, 0, 0, 0, 0.1e18);
    }

    // TODO: move to the position manager
    // function testUserCantMintUnbalancedAmount() public {
    //     uint256 strike = ig.currentStrike();
    //     Amount memory amount = Amount(1, 2);
    //     vm.prank(alice);
    //     vm.expectRevert(AsymmetricAmount);
    //     ig.mint(alice, strike, amount.up, amount.down, 0, 0.1e18, 0);
    // }

    function testCantMintMoreThanAvailable() public {
        uint256 strike = ig.currentStrike();
        (, ,  uint256 bearAvailNotional , uint256 bullAvailNotional) = ig.notional();
        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(ig), bullAvailNotional + bearAvailNotional, vm);

        // More than bull available notional
        vm.prank(alice);
        vm.expectRevert(NotEnoughNotional);
        ig.mint(alice, strike, bullAvailNotional + 1, 0, 0, 0.1e18);

        // More than bear available notional
        vm.prank(alice);
        vm.expectRevert(NotEnoughNotional);
        ig.mint(alice, strike, 0, bearAvailNotional + 1, 0, 0.1e18);
    }

    function testMultipleMintSameEpoch(uint256 amountFirstMint, uint256 amountSecondMint) public {
        // First mint
        Amount memory firstMintAmount = _getInputAmount(amountFirstMint, OptionStrategy.CALL);
        _mint(firstMintAmount, alice);

        // Second mint
        Amount memory secondMintAmount = _getInputAmount(amountSecondMint, OptionStrategy.CALL);
        _mint(secondMintAmount, alice);

        bytes32 posId = keccak256(abi.encodePacked(alice, ig.currentStrike()));
        (uint256 amount, bool strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(ig.currentEpoch(), epoch);

        assertEq(firstMintAmount.up + secondMintAmount.up, amount);
    }

    function testBurn(uint256 inputAmount, bool strategy) public {
        uint256 currEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        Amount memory amount = _getInputAmount(inputAmount, strategy);
        _mint(amount, alice);

        // Burn
        (, ,uint256 bearAvailNotional , uint256 bullAvailNotional) = ig.notional();
        uint256 aliceBalanceBeforeBurn = IERC20(baseToken).balanceOf(alice);

        vm.prank(alice);
        (uint256 expectedMarketValue, ) = ig.payoff(currEpoch, strike, amount.up, amount.down, 0);
        vm.prank(alice);
        uint256 payoff = ig.burn(currEpoch, alice, strike, amount.up, amount.down, expectedMarketValue, 0.1e18, 0);

        bytes32 posId = keccak256(abi.encodePacked(alice, ig.currentStrike()));

        (uint256 posAmount, , uint256 pStrike, uint256 epoch) = ig.positions(posId);
        (, ,uint256 bearAvailNotionalAfterBurn , uint256 bullAvailNotionalAfterBurn) = ig.notional();

        strategy ? assertEq(bullAvailNotionalAfterBurn, bullAvailNotional + amount.up) : assertEq(bearAvailNotionalAfterBurn, bearAvailNotional + amount.down);
        assertEq(aliceBalanceBeforeBurn + payoff, IERC20(baseToken).balanceOf(alice));
        assertEq(strike, pStrike);
        assertEq(0, posAmount);
        assertEq(currEpoch, epoch);
    }

    function testCantBurnPositionNotFound() public {
        uint256 currEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

         vm.prank(alice);
        vm.expectRevert(PositionNotFound);
        ig.payoff(currEpoch, strike, 0, 0, 0);

        vm.prank(alice);
        vm.expectRevert(PositionNotFound);
        ig.burn(currEpoch, alice, strike, 0, 0, 0, 0.1e18, 0);
    }

    function testCantBurnZero(uint256 inputAmount, bool strategy) public {
        uint256 currEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        Amount memory amount = _getInputAmount(inputAmount, strategy);
        _mint(amount, alice);

        vm.prank(alice);
        (uint256 expectedMarketValue, ) = ig.payoff(currEpoch, strike, 0, 0, 0);
        vm.prank(alice);
        vm.expectRevert(AmountZero);
        ig.burn(currEpoch, alice, strike, 0, 0, expectedMarketValue, 0.1e18, 0);
    }

    function testMintAndBurnMultipleUser(uint256 aInputAmount, bool aInputStrategy, uint256 bInputAmount, bool bInputStrategy) public {

        Amount memory aAmount = _getInputAmount(aInputAmount, aInputStrategy);
        _mint(aAmount, alice);

        Amount memory bAmount = _getInputAmount(bInputAmount, bInputStrategy);
        _mint(bAmount, bob);

        uint256 strike = ig.currentStrike();
        bytes32 posIdAlice = keccak256(abi.encodePacked(alice, strike));
        bytes32 posIdBob = keccak256(abi.encodePacked(bob, strike));

        {
            (uint256 amount, bool strategy, , ) = ig.positions(posIdAlice);
            assertEq(aInputStrategy, strategy);
            assertEq((aAmount.up + aAmount.down), amount);
        }

        {
            (uint256 amount, bool strategy, , ) = ig.positions(posIdBob);
            assertEq(bInputStrategy, strategy);
            assertEq((bAmount.up + bAmount.down), amount);
        }

        _burn(aAmount, alice);
        _burn(bAmount, bob);

        {
            (uint256 amount, , , ) = ig.positions(posIdAlice);
            assertEq(0, amount);
        }

        {
            (uint256 amount, , , ) = ig.positions(posIdBob);
            assertEq(0, amount);
        }
    }

    function testCantBurnMoreThanMinted() public {
        uint256 inputAmount = 1e18;

        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(ig), inputAmount, vm);

        uint256 strike = ig.currentStrike();
        uint256 epoch = ig.currentEpoch();

        (uint256 expectedMarketValue, ) = ig.premium(strike, inputAmount, 0);
        vm.prank(alice);
        ig.mint(alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18);

        vm.prank(alice);
        // TBD: the inputAmount cannot be used wrong as it cause an arithmetic over/underflow...
        (expectedMarketValue, ) = ig.payoff(epoch, strike, inputAmount, 0, 0);
        vm.prank(alice);
        vm.expectRevert(CantBurnMoreThanMinted);
        ig.burn(epoch, alice, strike, inputAmount + 1e18, 0, expectedMarketValue, 0.1e18, 0);
    }

    // ToDo: Review this test
    // function testGetUtilizationRate() public {
    //     uint256 ur = ig.getUtilizationRate();
    //     assertEq(0, ur);

    //     (, , , uint256 bullAvailNotional) = ig.notional();
    //     Amount memory amount = Amount(bullAvailNotional / 2, 0);
    //     _mint(amount, alice);

    //     // assuming bullAvailNotional ~= bearAvailNotional => bullAvailNotional / 2 = 25% of total
    //     ur = ig.getUtilizationRate();
    //     assertEq(0.25e18, ur);
    // }

    function testIGPaused() public {
        MarketOracle mo = MarketOracle(ap.marketOracle());
        vm.startPrank(admin);
        mo.setDelay(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, 0, true);
        vm.stopPrank();

        uint256 inputAmount = 1 ether;
        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(ig), inputAmount, vm);

        assertEq(ig.paused(), false);

        vm.expectRevert();
        ig.changePauseState();

        vm.prank(admin);
        ig.changePauseState();
        assertEq(ig.paused(), true);

        uint256 strike = ig.currentStrike();

        vm.startPrank(alice);
        (uint256 expectedMarketValue, ) = ig.premium(strike, inputAmount, 0);
        vm.expectRevert(IGPaused);
        ig.mint(alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18);
        vm.stopPrank();

        uint256 epoch = ig.currentEpoch();

        vm.prank(admin);
        ig.changePauseState();
        (expectedMarketValue, ) = ig.premium(strike, inputAmount, 0);
        vm.prank(alice);
        ig.mint(alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18);
        vm.prank(admin);
        ig.changePauseState();
        vm.startPrank(alice);
        (expectedMarketValue, ) = ig.payoff(epoch, strike, inputAmount, 0, 0);
        vm.expectRevert(IGPaused);
        ig.burn(epoch, alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18, 0);
        vm.stopPrank();

        Utils.skipDay(true, vm);

        vm.prank(admin);
        vm.expectRevert(IGPaused);
        ig.rollEpoch();

        // From here on, all the IG functions should work properly
        vm.prank(admin);
        ig.changePauseState();
        assertEq(ig.paused(), false);

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();

        epoch = ig.currentEpoch();
        strike = ig.currentStrike();

        (expectedMarketValue, ) = ig.premium(strike, inputAmount, 0);
        vm.startPrank(alice);
        ig.mint(alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18);

        (expectedMarketValue, ) = ig.payoff(epoch, strike, inputAmount, 0, 0);
        ig.burn(epoch, alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18, 0);
        vm.stopPrank();
    }

    function testRollEpochWhenDVPHasJumpedSomeRolls() public {
        MarketOracle mo = MarketOracle(ap.marketOracle());
        vm.startPrank(admin);
        mo.setDelay(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, 0, true);
        vm.stopPrank();

        uint256 previousEpoch = ig.currentEpoch();
        uint256 firstExpiry = EpochFrequency.nextExpiry(previousEpoch, EpochFrequency.DAILY);
        uint256 secondExpiry = EpochFrequency.nextExpiry(firstExpiry, EpochFrequency.DAILY);
        uint256 thirdExpiry = EpochFrequency.nextExpiry(secondExpiry, EpochFrequency.DAILY);
        Utils.skipDay(true, vm);
        Utils.skipDay(true, vm);

        uint256 epochNumbers = ig.getNumberOfEpochs();
        assertEq(epochNumbers, 1);

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();

        uint256 nextEpoch = ig.currentEpoch();
        uint256 lastEpoch = ig.lastRolledEpoch();
        epochNumbers = ig.getNumberOfEpochs();

        assertEq(epochNumbers, 2);
        assertEq(previousEpoch, lastEpoch);
        assertNotEq(nextEpoch, firstExpiry);
        assertNotEq(nextEpoch, secondExpiry);
        assertEq(nextEpoch, thirdExpiry);
    }

    function testSetTradeVolatilityParams() public {
        vm.expectRevert();
        ig.setTradeVolatilityTimeDecay(25e16);

        vm.expectRevert();
        ig.setTradeVolatilityUtilizationRateFactor(1.25e18);

        vm.startPrank(admin);
        ig.setTradeVolatilityUtilizationRateFactor(1.25e18);
        ig.setTradeVolatilityTimeDecay(25e16);
        vm.stopPrank();
    }

    function testMintWithSlippage(uint256 inputAmount, bool strategy) public {
        Amount memory amount = _getInputAmount(inputAmount, strategy);
        uint256 strike = ig.currentStrike();

        (uint256 expectedMarketValue, ) = ig.premium(strike, amount.up, amount.down);
        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(ig), expectedMarketValue, vm);

        ig.setOptionPrice(2e18);

        vm.prank(alice);
        vm.expectRevert("ERC20: insufficient allowance");
        ig.mint(alice, strike, amount.up, amount.down, expectedMarketValue, 0.1e18);
    }

    function testBurnWithSlippage(uint256 inputAmount, bool strategy) public {
        Amount memory amount = _getInputAmount(inputAmount, strategy);

        //MockedIG ig = new MockedIG(address(vault));
        uint256 currEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(ig), (amount.up + amount.down), vm);
        (uint256 expectedMarketValue, ) = ig.premium(strike, amount.up, amount.down);
        vm.prank(alice);
        ig.mint(alice, strike, amount.up, amount.down, expectedMarketValue, 0.1e18);

        vm.prank(alice);
        (expectedMarketValue, ) = ig.payoff(currEpoch, strike, amount.up, amount.down, 0);

        vm.prank(alice);
        vm.expectRevert(SlippedMarketValue);
        ig.burn(currEpoch, alice, strike, amount.up, amount.down, 20e18, 0.1e18, 0);
    }

    function testSetTimeLockedParameters() public {
        // Get default values:
        TimeLockedFinanceValues memory currentValues = _getTimeLockedFinanceParameters();

        // Check default values:
        assertEq(3e18, currentValues.sigmaMultiplier);
        assertEq(2e18, currentValues.tradeVolatilityUtilizationRateFactor);
        assertEq(0.25e18, currentValues.tradeVolatilityTimeDecay);
        assertEq(0.9e18, currentValues.volatilityPriceDiscountFactor);
        assertEq(true, currentValues.useOracleImpliedVolatility);

        // Change some of the default values:
        currentValues.volatilityPriceDiscountFactor = 0.85e18;
        currentValues.useOracleImpliedVolatility = false;

        vm.prank(admin);
        ig.setParameters(currentValues);

        // They do not change until the next epoch:
        currentValues = _getTimeLockedFinanceParameters();
        assertEq(3e18, currentValues.sigmaMultiplier);
        assertEq(2e18, currentValues.tradeVolatilityUtilizationRateFactor);
        assertEq(0.25e18, currentValues.tradeVolatilityTimeDecay);
        assertEq(0.9e18, currentValues.volatilityPriceDiscountFactor);
        assertEq(true, currentValues.useOracleImpliedVolatility);

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();

        currentValues = _getTimeLockedFinanceParameters();
        assertEq(3e18, currentValues.sigmaMultiplier);
        assertEq(2e18, currentValues.tradeVolatilityUtilizationRateFactor);
        assertEq(0.25e18, currentValues.tradeVolatilityTimeDecay);
        assertEq(0.85e18, currentValues.volatilityPriceDiscountFactor);
        assertEq(false, currentValues.useOracleImpliedVolatility);
    }

    function _getTimeLockedFinanceParameters() private view returns (TimeLockedFinanceValues memory currentValues) {
        (, , , , , , TimeLockedFinanceParameters memory igParams, , ) = ig.financeParameters();
        currentValues = TimeLockedFinanceValues({
            sigmaMultiplier: igParams.sigmaMultiplier.get(),
            tradeVolatilityUtilizationRateFactor: igParams.tradeVolatilityUtilizationRateFactor.get(),
            tradeVolatilityTimeDecay: igParams.tradeVolatilityTimeDecay.get(),
            volatilityPriceDiscountFactor: igParams.volatilityPriceDiscountFactor.get(),
            useOracleImpliedVolatility: igParams.useOracleImpliedVolatility.get()
        });
    }

    // - [TBD] - Test burn when epoch is expired

    // UTILS
    function _getInputAmount(uint256 fuzzedInput, bool strategy) internal view returns(Amount memory amount) {
        (, , uint256 bearAvailNotional, uint256 bullAvailNotional) = ig.notional();
        uint256 maxInput = strategy ? bullAvailNotional : bearAvailNotional;
        vm.assume(MIN_MINT < maxInput);
        fuzzedInput = Utils.boundFuzzedValueToRange(fuzzedInput, MIN_MINT, maxInput);
        amount = Amount(strategy ? fuzzedInput : 0, strategy ? 0 : fuzzedInput);
}

    function _mint(Amount memory amount, address user) internal returns (uint256 expectedMarketValue, uint256 fee, uint256 premium) {
        uint256 strike = ig.currentStrike();
        TokenUtils.provideApprovedTokens(admin, baseToken, user, address(ig), (amount.up + amount.down), vm);
        (expectedMarketValue, fee) = ig.premium(strike, amount.up, amount.down);
        vm.prank(user);
        premium = ig.mint(user, strike, amount.up, amount.down, expectedMarketValue, 0.1e18);
    }

    function _burn(Amount memory amount, address user) internal returns (uint256 expectedMarketValue, uint256 fee, uint256 paidPayoff) {
        uint256 strike = ig.currentStrike();
        uint256 currEpoch = ig.currentEpoch();
        vm.prank(user);
        (expectedMarketValue, fee) = ig.payoff(currEpoch, strike, amount.up, amount.down, 0);
        vm.prank(user);
        paidPayoff = ig.burn(currEpoch, user, strike, amount.up, amount.down, expectedMarketValue, 0.1e18, 0);
    }
}
