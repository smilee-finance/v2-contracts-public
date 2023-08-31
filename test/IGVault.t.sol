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

/**
    @title Test case for underlying asset going to zero
    @dev This should never happen, still we need to test shares value goes to zero, users deposits can be rescued and
         new deposits are not allowed
 */
contract IGVaultTest is Test {
    bytes4 constant NotEnoughLiquidity = bytes4(keccak256("NotEnoughLiquidity()"));

    address admin = address(0x1);

    // User of Vault
    address alice = address(0x2);
    address bob = address(0x3);

    //User of DVP
    address charlie = address(0x4);
    address david = address(0x5);

    TestnetToken baseToken;
    TestnetToken sideToken;

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
        vm.prank(charlie);
        vm.expectRevert(NotEnoughLiquidity);
        ig.mint(charlie, 0, OptionStrategy.CALL, 1 ether);

        VaultUtils.addVaultDeposit(alice, 0.5 ether, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        ig.rollEpoch();

        _assurePremium(charlie, 0, OptionStrategy.CALL, 1 ether);

        vm.expectRevert(NotEnoughLiquidity);
        ig.mint(charlie, 0, OptionStrategy.CALL, 1 ether);
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
        uint256 premium = _assurePremium(charlie, 0, OptionStrategy.CALL, optionAmount);

        vm.prank(charlie);
        premium = ig.mint(charlie, 0, OptionStrategy.CALL, optionAmount);
        // ToDo: check premium change

        uint256 vaultNotionalAfterMint = vault.notional();

        bytes32 posId = keccak256(abi.encodePacked(charlie, OptionStrategy.CALL, ig.currentStrike()));

        (uint256 amount, , , ) = ig.positions(posId);
        assertEq(amount, optionAmount);
        assertEq(vaultNotionalBeforeMint + premium, vaultNotionalAfterMint);
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

        _assurePremium(charlie, 0, params.optionStrategy, params.charlieAmount);
        vm.prank(charlie);
        ig.mint(charlie, 0, params.optionStrategy, params.charlieAmount);

        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        // Mint without rolling epoch doesn't change the vaule of initialLiquidity
        assertEq(params.aliceAmount + params.bobAmount, initialLiquidity);

        uint256 davidInitialBalance = _assurePremium(david, 0, params.optionStrategy, params.davidAmount);
        uint256 strike = ig.currentStrike();
        {
            vm.prank(david);
            uint256 davidPremium = ig.mint(david, strike, params.optionStrategy, params.davidAmount);
            davidInitialBalance -= davidPremium;
        }

        uint256 vaultNotionalBeforeBurn = vault.notional();
        bytes32 posId = keccak256(abi.encodePacked(david, params.optionStrategy, ig.currentStrike()));
        (uint256 amountBeforeBurn, , , ) = ig.positions(posId);

        assertEq(params.davidAmount, amountBeforeBurn);

        uint256 davidAmountToBurn = params.davidAmount;
        if (params.partialBurn) {
            davidAmountToBurn = davidAmountToBurn / 10;
        }

        uint256 positionEpoch = ig.currentEpoch();

        vm.prank(david);
        uint256 davidPayoff = ig.payoff(positionEpoch, strike, params.optionStrategy, davidAmountToBurn);

        vm.prank(david);
        ig.burn(positionEpoch, david, strike, params.optionStrategy, davidAmountToBurn);

        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        // Mint without rolling epoch doesn't change the vaule of initialLiquidity
        assertEq(params.aliceAmount + params.bobAmount, initialLiquidity);

        uint256 vaultNotionalAfterBurn = vault.notional();
        (uint256 amountAfterBurn, , , ) = ig.positions(posId);

        assertEq(davidInitialBalance + davidPayoff, baseToken.balanceOf(david));
        assertEq(amountBeforeBurn - davidAmountToBurn, amountAfterBurn);
        assertEq(vaultNotionalBeforeBurn, vaultNotionalAfterBurn + davidPayoff);
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

        _assurePremium(charlie, 0, params.optionStrategy, params.charlieAmount);
        vm.prank(charlie);
        ig.mint(charlie, 0, params.optionStrategy, params.charlieAmount);

        uint256 davidInitialBalance = _assurePremium(david, 0, params.optionStrategy, params.davidAmount);
        {
            vm.prank(david);
            uint256 davidPremium = ig.mint(david, 0, params.optionStrategy, params.davidAmount);
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
        uint256 charliePayoff = ig.payoff(positionEpoch, positionStrike, params.optionStrategy, params.charlieAmount);

        assertApproxEqAbs(params.charlieAmount / 10, charliePayoff, 1e2);

        vm.prank(david);
        uint256 davidPayoff = ig.payoff(positionEpoch, positionStrike, params.optionStrategy, params.davidAmount);

        assertApproxEqAbs(params.davidAmount / 10, davidPayoff, 1e2);

        uint256 pendingPayoff = VaultUtils.vaultState(vault).liquidity.pendingPayoffs;
        assertApproxEqAbs(charliePayoff + davidPayoff, pendingPayoff, 1e2);

        vm.prank(david);
        ig.burn(positionEpoch, david, positionStrike, params.optionStrategy, params.davidAmount);

        pendingPayoff = VaultUtils.vaultState(vault).liquidity.pendingPayoffs;
        assertApproxEqAbs(charliePayoff, pendingPayoff, 1e2);

        assertApproxEqAbs(vaultNotionalBeforeRollEpoch - davidPayoff - charliePayoff, vault.notional(), 1e3);
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
        uint256 aliceAmount = 1000e18;
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
        _assurePremium(charlie, 0, OptionStrategy.CALL, optionAmount);
        vm.prank(charlie);
        ig.mint(charlie, 0, OptionStrategy.CALL, optionAmount);

        Utils.skipDay(true, vm);
        ig.rollEpoch();
        // VaultUtils.logState(vault);
    }

    function _assurePremium(
        address user,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) private returns (uint256 premium_) {
        premium_ = ig.premium(strike, strategy, amount);
        TokenUtils.provideApprovedTokens(admin, address(baseToken), user, address(ig), premium_, vm);
    }
}
