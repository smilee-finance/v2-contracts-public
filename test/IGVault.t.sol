// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {FeeManager} from "../src/FeeManager.sol";

/**
    @title Test case for underlying asset going to zero
    @dev This should never happen, still we need to test shares value goes to zero, users deposits can be rescued and
         new deposits are not allowed
 */
contract IGVaultTest is Test {
    bytes4 constant NotEnoughLiquidity = bytes4(keccak256("NotEnoughLiquidity()"));
    bytes4 constant VaultPaused = bytes4(keccak256("VaultPaused()"));

    address admin = address(0x1);

    // User of Vault
    address alice = address(0x2);
    address bob = address(0x3);

    //User of DVP
    address charlie = address(0x4);
    address david = address(0x5);

    TestnetToken baseToken;
    TestnetToken sideToken;
    FeeManager feeManager;

    TestnetRegistry registry;

    MockedVault vault;
    MockedIG ig;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);
        //ToDo: Replace with Factory
        vm.startPrank(admin);
        AddressProvider ap = new AddressProvider();
        registry = new TestnetRegistry();
        ap.setRegistry(address(registry));
        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));

        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        ig = new MockedIG(address(vault), address(ap));
        ig.setOptionPrice(1e3);
        ig.setPayoffPerc(1e17);
        ig.useFakeDeltaHedge();

        vm.prank(admin);
        registry.registerDVP(address(ig));
        vm.prank(admin);
        MockedVault(vault).setAllowedDVP(address(ig));
        feeManager = FeeManager(ap.feeManager());

        ig.rollEpoch();
    }

    // Verificare sempre la liquidità in tutti i test
    // Assert su cosa ci aspettiamo nella Vault
    // Implement CALL & PUT
    // C & D comprano posizioni e chiudono alla scadenza => Accertarsi che il payoff venga spostato nella DVP
    // C & D comprano posizioni e perdono
    // C & D comprano posizioni e perdono, cosa succede ad Alice & Bob che vogliono uscire dalla Vault (parziale o totale)
    // C & D comprano e chiudono alla scadenza, cosa succede ad Alice & Bob che vogliono uscire dalla Vault (parziale o totale)
    // Controllare test quando non ci sono opzioni disponibili, cosa succede se ne minti un'altra (not enought liquidity)
    // Controllare test quando non ci sono opzioni disponibili, cosa succede se ne bruci una (altro utente può acquistare)

    function testBuyOptionWithoutLiquidity() public {
        uint256 inputAmount = 1 ether;
        (uint256 expectedMarketValue, ) = ig.premium(0, inputAmount, 0);
        vm.prank(charlie);
        vm.expectRevert(NotEnoughLiquidity);
        ig.mint(charlie, 0, inputAmount, 0, expectedMarketValue, 0.1e18);

        VaultUtils.addVaultDeposit(alice, 0.5 ether, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        ig.rollEpoch();

        _assurePremium(charlie, 0, inputAmount, 0);

        vm.expectRevert(NotEnoughLiquidity);
        ig.mint(charlie, 0, inputAmount, 0, expectedMarketValue, 0.1e18);
    }

    // Assumption: Price 1:1
    // ToDo: Adjust with different price
    function testBuyOptionWithLiquidity(uint64 aliceAmount, uint64 bobAmount, uint128 optionAmount) public {
        vm.assume(aliceAmount > 0);
        vm.assume(bobAmount > 0);
        vm.assume(optionAmount > 0);
        vm.assume(((uint128(aliceAmount) + uint128(bobAmount))) / 2 >= optionAmount);

        VaultUtils.addVaultDeposit(alice, aliceAmount, admin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, bobAmount, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        ig.rollEpoch();

        uint256 vaultNotionalBeforeMint = vault.notional();
        (uint256 premium, uint256 fee) = _assurePremium(charlie, 0, optionAmount, 0);

        vm.startPrank(charlie);
        premium = ig.mint(charlie, 0, optionAmount, 0, premium, 0.1e18);
        vm.stopPrank();
        // ToDo: check premium change

        uint256 vaultNotionalAfterMint = vault.notional();

        bytes32 posId = keccak256(abi.encodePacked(charlie, ig.currentStrike()));

        (uint256 amount, , , ) = ig.positions(posId);
        assertEq(amount, optionAmount);
        assertEq(vaultNotionalBeforeMint + premium - fee, vaultNotionalAfterMint);
    }

    struct Parameters {
        uint256 aliceAmount;
        uint256 bobAmount;
        uint64 charlieAmount;
        uint64 davidAmount;
        bool partialBurn;
        bool optionStrategy;
    }

    function testBuyTwoOptionOneBurn(
        uint64 charlieAmount,
        uint64 davidAmount,
        bool partialBurn,
        bool optionStrategy
    ) public {
        vm.assume(charlieAmount > 0.01 ether && charlieAmount < 5 ether);
        vm.assume(davidAmount > 0.01 ether && davidAmount < 5 ether);

        uint256 aliceAmount = 10 ether;
        uint256 bobAmount = 10 ether;
        vm.assume((aliceAmount + bobAmount) / 2 >= uint256(charlieAmount) + uint256(davidAmount));

        // NOTE: avoids stack too deep
        _buyTwoOptionOneBurn(
            Parameters(aliceAmount, bobAmount, charlieAmount, davidAmount, partialBurn, optionStrategy)
        );
    }

    function _buyTwoOptionOneBurn(Parameters memory params) internal {
        VaultUtils.addVaultDeposit(alice, params.aliceAmount, admin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, params.bobAmount, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        ig.rollEpoch();

        uint256 initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(params.aliceAmount + params.bobAmount, initialLiquidity);

        (uint256 premium, ) = _assurePremium(
            charlie,
            0,
            (params.optionStrategy) ? params.charlieAmount : 0,
            (params.optionStrategy) ? 0 : params.charlieAmount
        );
        vm.prank(charlie);
        ig.mint(
            charlie,
            0,
            (params.optionStrategy) ? params.charlieAmount : 0,
            (params.optionStrategy) ? 0 : params.charlieAmount,
            premium,
            0.1e18
        );

        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        // Mint without rolling epoch doesn't change the vaule of initialLiquidity
        assertEq(params.aliceAmount + params.bobAmount, initialLiquidity);

        (uint256 davidInitialBalance, ) = _assurePremium(
            david,
            0,
            (params.optionStrategy) ? params.davidAmount : 0,
            (params.optionStrategy) ? 0 : params.davidAmount
        );
        uint256 strike = ig.currentStrike();
        {
            uint256 davidPremium;
            vm.prank(david);
            davidPremium = ig.mint(
                david,
                strike,
                (params.optionStrategy) ? params.davidAmount : 0,
                (params.optionStrategy) ? 0 : params.davidAmount,
                davidInitialBalance,
                0.1e18
            );
            davidInitialBalance -= davidPremium;
        }

        uint256 vaultNotionalBeforeBurn = vault.notional();
        bytes32 posId = keccak256(abi.encodePacked(david, ig.currentStrike()));
        (uint256 amountBeforeBurn, , , ) = ig.positions(posId);

        assertEq(params.davidAmount, amountBeforeBurn);

        uint256 davidAmountToBurn = params.davidAmount;
        if (params.partialBurn) {
            davidAmountToBurn = davidAmountToBurn / 10;
        }

        uint256 davidPayoff;
        uint256 davidPayoffFee;
        {
            vm.startPrank(david);
            bool optionStrategy = params.optionStrategy;
            (davidPayoff, davidPayoffFee) = ig.payoff(
                ig.currentEpoch(),
                strike,
                (optionStrategy) ? davidAmountToBurn : 0,
                (optionStrategy) ? 0 : davidAmountToBurn
            );

            davidPayoff = ig.burn(
                ig.currentEpoch(),
                david,
                strike,
                (optionStrategy) ? davidAmountToBurn : 0,
                (optionStrategy) ? 0 : davidAmountToBurn,
                davidPayoff,
                0.1e18
            );
            vm.stopPrank();
        }

        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        // Mint without rolling epoch doesn't change the vaule of initialLiquidity
        assertEq(params.aliceAmount + params.bobAmount, initialLiquidity);

        uint256 vaultNotionalAfterBurn = vault.notional();
        (uint256 amountAfterBurn, , , ) = ig.positions(posId);

        assertEq(davidInitialBalance + davidPayoff, baseToken.balanceOf(david));
        assertEq(amountBeforeBurn - davidAmountToBurn, amountAfterBurn);
        assertEq(vaultNotionalBeforeBurn, vaultNotionalAfterBurn + davidPayoff + davidPayoffFee);
    }

    function testBuyTwoOptionOneBurnAfterMaturity(
        uint64 charlieAmount,
        uint64 davidAmount,
        bool optionStrategy
    ) public {
        vm.assume(charlieAmount > 0.01 ether && charlieAmount < 5 ether);
        vm.assume(davidAmount > 0.01 ether && davidAmount < 5 ether);

        uint256 aliceAmount = 10 ether;
        uint256 bobAmount = 10 ether;

        vm.assume((aliceAmount + bobAmount) / 2 >= uint256(charlieAmount) + uint256(davidAmount));

        _buyTwoOptionOneBurnAfterMaturity(
            Parameters(aliceAmount, bobAmount, charlieAmount, davidAmount, false, optionStrategy)
        );
    }

    function _buyTwoOptionOneBurnAfterMaturity(Parameters memory params) internal {
        VaultUtils.addVaultDeposit(alice, params.aliceAmount, admin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, params.bobAmount, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        ig.rollEpoch();
        {
            uint256 initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
            assertEq(params.aliceAmount + params.bobAmount, initialLiquidity);
        }

        (uint256 premium, ) = _assurePremium(
            charlie,
            0,
            (params.optionStrategy) ? params.charlieAmount : 0,
            (params.optionStrategy) ? 0 : params.charlieAmount
        );
        vm.prank(charlie);
        ig.mint(
            charlie,
            0,
            (params.optionStrategy) ? params.charlieAmount : 0,
            (params.optionStrategy) ? 0 : params.charlieAmount,
            premium,
            0.1e18
        );

        (uint256 davidInitialBalance, ) = _assurePremium(
            david,
            0,
            (params.optionStrategy) ? params.davidAmount : 0,
            (params.optionStrategy) ? 0 : params.davidAmount
        );
        {
            vm.prank(david);
            uint256 davidPremium = ig.mint(
                david,
                0,
                (params.optionStrategy) ? params.davidAmount : 0,
                (params.optionStrategy) ? 0 : params.davidAmount,
                davidInitialBalance,
                0.1e18
            );
            davidInitialBalance -= davidPremium;
        }

        uint256 vaultNotionalBeforeRollEpoch = vault.notional();
        uint256 positionEpoch = ig.currentEpoch();
        uint256 positionStrike = ig.currentStrike();

        Utils.skipDay(true, vm);
        ig.rollEpoch();

        // {
        //     uint256 initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        //     // Since the position have the same premium and payoff perc, the initialLiquidity state shouldn't change.
        //     assertApproxEqAbs(params.aliceAmount + params.bobAmount, initialLiquidity, 1e2);
        // }

        vm.prank(charlie);
        (uint256 charliePayoff, uint256 charlieFeePayoff) = ig.payoff(
            positionEpoch,
            positionStrike,
            (params.optionStrategy) ? params.charlieAmount : 0,
            (params.optionStrategy) ? 0 : params.charlieAmount
        );

        assertApproxEqAbs(params.charlieAmount / 10, charliePayoff + charlieFeePayoff, 1e2);

        vm.prank(david);
        (uint256 davidPayoff, uint256 davidFeePayoff) = ig.payoff(
            positionEpoch,
            positionStrike,
            (params.optionStrategy) ? params.davidAmount : 0,
            (params.optionStrategy) ? 0 : params.davidAmount
        );

        assertApproxEqAbs(params.davidAmount / 10, davidPayoff + davidFeePayoff, 1e2);

        uint256 pendingPayoff = VaultUtils.vaultState(vault).liquidity.pendingPayoffs;
        assertApproxEqAbs((charliePayoff + charlieFeePayoff) + (davidPayoff + davidFeePayoff), pendingPayoff, 1e2);

        {
            bool optionStrategy = params.optionStrategy;
            uint256 davidAmount = params.davidAmount;
            vm.prank(david);
            davidPayoff = ig.burn(
                positionEpoch,
                david,
                positionStrike,
                (optionStrategy) ? davidAmount : 0,
                (optionStrategy) ? 0 : davidAmount,
                davidPayoff,
                0.1e18
            );
        }

        pendingPayoff = VaultUtils.vaultState(vault).liquidity.pendingPayoffs;

        assertApproxEqAbs(charliePayoff + charlieFeePayoff, pendingPayoff, 1e2);

        assertApproxEqAbs(
            vaultNotionalBeforeRollEpoch - (davidPayoff + davidFeePayoff) - (charliePayoff + charlieFeePayoff),
            vault.notional(),
            1e3
        );
        assertApproxEqAbs(davidInitialBalance + davidPayoff, baseToken.balanceOf(david), 1e3);
    }

    /**
        Test what happen in the roll epoch of the vault when the payoff exceeds the notional
     */
    function testRollEpochWhenPayoffExceedsNotional() public {
        ig.setPayoffPerc(15e17); // 150%
        ig.setOptionPrice(0);
        ig.useRealDeltaHedge();

        // Provide 1000 liquidity:
        uint256 aliceAmount = 10000e18;
        VaultUtils.addVaultDeposit(alice, aliceAmount, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        ig.rollEpoch();
        // VaultUtils.logState(vault);

        // Initiate half withdraw (500):
        vm.prank(alice);
        vault.initiateWithdraw(500e18);

        Utils.skipDay(true, vm);
        ig.rollEpoch();
        // VaultUtils.logState(vault);

        // Mint option of 250:
        uint256 optionAmount = 250e18;
        _assurePremium(charlie, 0, optionAmount, 0);
        vm.prank(charlie);
        ig.mint(charlie, 0, optionAmount, 0, 0, 0.1e18);

        Utils.skipDay(true, vm);
        ig.rollEpoch();
        // VaultUtils.logState(vault);
    }

    function testIGBehaviourWhenVaultIsPaused() public {
        VaultUtils.addVaultDeposit(alice, 1000e18, admin, address(vault), vm);
        Utils.skipDay(true, vm);
        ig.rollEpoch();

        uint256 optionAmount = 250e18;
        (uint256 premium, ) = _assurePremium(charlie, 0, optionAmount, 0);
        // Mint option of 125:
        vm.prank(charlie);
        ig.mint(charlie, 0, optionAmount / 2, 0, premium, 0.1e18);

        vm.prank(admin);
        vault.changePauseState();

        // Try Mint option after Vault was paused
        vm.startPrank(charlie);
        (uint256 expectedMarketValue, ) = ig.premium(0, optionAmount, 0);
        vm.expectRevert(VaultPaused);
        ig.mint(charlie, 0, optionAmount, 0, expectedMarketValue, 0.1e18);
        vm.stopPrank();

        // Try burn option after Vault was paused
        uint256 currentEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();
        vm.startPrank(charlie);
        (expectedMarketValue, ) = ig.payoff(currentEpoch, strike, optionAmount / 2, 0);
        vm.expectRevert(VaultPaused);
        ig.burn(currentEpoch, charlie, strike, optionAmount / 2, 0, expectedMarketValue, 0.1e18);
        vm.stopPrank();

        vm.prank(admin);
        vault.changePauseState();

        // Burn should be work again
        vm.startPrank(charlie);
        (expectedMarketValue, ) = ig.payoff(currentEpoch, strike, optionAmount / 2, 0);
        ig.burn(ig.currentEpoch(), charlie, strike, optionAmount / 2, 0, expectedMarketValue, 0.1e18);
        vm.stopPrank();

        // Test RollEpoch revert when Vault is paused
        vm.prank(admin);
        vault.changePauseState();

        Utils.skipDay(true, vm);
        vm.expectRevert("Pausable: paused");
        ig.rollEpoch();
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
