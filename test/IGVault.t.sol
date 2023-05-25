// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {IRegistry} from "../src/interfaces/IRegistry.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {Registry} from "../src/Registry.sol";
import {Vault} from "../src/Vault.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";

/**
    @title Test case for underlying asset going to zero
    @dev This should never happen, still we need to test shares value goes to zero, users deposits can be rescued and
         new deposits are not allowed
 */
contract IGVaultTest is Test {
    bytes4 constant NotEnoughLiquidity = bytes4(keccak256("NotEnoughLiquidity()"));

    address tokenAdmin = address(0x1);

    // User of Vault
    address alice = address(0x2);
    address bob = address(0x3);

    //User of DVP
    address charlie = address(0x4);
    address david = address(0x5);

    TestnetToken baseToken;
    TestnetToken sideToken;

    IRegistry registry;

    MockedVault vault;
    MockedIG ig;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);
        //ToDo: Replace with Factory
        registry = new Registry();
        vault = MockedVault(VaultUtils.createVaultWithRegistry(EpochFrequency.DAILY, tokenAdmin, vm, registry));

        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        ig = new MockedIG(address(vault));
        ig.setOptionPrice(1000);
        ig.useFakeDeltaHedge();

        registry.register(address(ig));

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

        _addVaultDeposit(alice, 0.5 ether);

        Utils.skipDay(true, vm);
        ig.rollEpoch();

        _assurePremium(charlie, 0, OptionStrategy.CALL, 1 ether);

        vm.expectRevert(NotEnoughLiquidity);
        ig.mint(charlie, 0, OptionStrategy.CALL, 1 ether);
    }

    // Assumption: Price 1:1
    // ToDo: Adjust with different price
    function testBuyOptionWithLiquidity(uint64 aliceAmount, uint64 bobAmount, uint128 optionAmount) public {
        vm.assume(aliceAmount > 0.01 ether);
        vm.assume(bobAmount > 0.01 ether);
        vm.assume(optionAmount > 0.01 ether);
        vm.assume((uint128(aliceAmount) + uint128(bobAmount)) >= optionAmount);

        _addVaultDeposit(alice, aliceAmount);
        _addVaultDeposit(bob, bobAmount);

        Utils.skipDay(true, vm);
        ig.rollEpoch();

        uint256 vaultNotionalBeforeMint = vault.notional();
        uint256 premium = _assurePremium(charlie, 0, OptionStrategy.CALL, optionAmount);

        vm.prank(charlie);
        ig.mint(charlie, 0, OptionStrategy.CALL, optionAmount);

        uint256 vaultNotionalAfterMint = vault.notional();

        bytes32 posId = keccak256(abi.encodePacked(charlie, OptionStrategy.CALL, ig.currentStrike()));

        (uint256 amount, , , ) = ig.positions(posId);
        assertEq(amount, optionAmount);
        assertEq(vaultNotionalBeforeMint + premium, vaultNotionalAfterMint);
    }

    // ToDo: Same test with portion of burn
    function testBuyTwoOptionOneBurn(
        uint64 aliceAmount,
        uint64 bobAmount,
        uint64 charlieAmount,
        uint64 davidAmount,
        bool partialBurn
    ) public {
        vm.assume(aliceAmount > 0.01 ether);
        vm.assume(bobAmount > 0.01 ether);
        vm.assume(charlieAmount > 0.01 ether);
        vm.assume(davidAmount > 0.01 ether);

        vm.assume(uint256(aliceAmount) + uint256(bobAmount) >= uint256(charlieAmount) + uint256(davidAmount));

        _addVaultDeposit(alice, aliceAmount);
        _addVaultDeposit(bob, bobAmount);

        Utils.skipDay(true, vm);
        ig.rollEpoch();

        uint256 charliePremium = _assurePremium(charlie, 0, OptionStrategy.CALL, charlieAmount);
        vm.prank(charlie);
        ig.mint(charlie, 0, OptionStrategy.CALL, charlieAmount);


        uint256 davidPremium = _assurePremium(david, 0, OptionStrategy.CALL, davidAmount);
         
        vm.prank(david);
        ig.mint(david, 0, OptionStrategy.CALL, davidAmount);

        uint256 vaultNotionalBeforeBurn = vault.notional();

        bytes32 posId = keccak256(abi.encodePacked(david, OptionStrategy.CALL, ig.currentStrike()));

        (uint256 amountBeforeBurn, , , ) = ig.positions(posId);

        assertEq(davidAmount, amountBeforeBurn);

        uint256 davidAmountToBurn = davidAmount;
        if(partialBurn) {
            davidAmountToBurn = davidAmountToBurn / 10;
        }

        uint256 davidPayoff = ig.payoff(ig.currentEpoch(), 0, OptionStrategy.CALL, davidAmountToBurn);

        vm.startPrank(david);
        ig.burn(ig.currentEpoch(), david, 0, OptionStrategy.CALL, davidAmountToBurn);
        vm.stopPrank();

        uint256 vaultNotionalAfterBurn = vault.notional();
        (uint256 amountAfterBurn, , , ) = ig.positions(posId);

        assert()
        assertEq(davidPayoff, baseToken.balanceOf(david));
        assertEq(amountBeforeBurn - davidAmountToBurn, amountAfterBurn);
        assertEq(vaultNotionalBeforeBurn, vaultNotionalAfterBurn + davidPayoff);
    }

    


    function _addVaultDeposit(address user, uint256 amount) private {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), user, address(vault), amount, vm);
        vm.prank(user);
        vault.deposit(amount);
    }

    function _assurePremium(
        address user,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) private returns (uint256 premium_) {
        premium_ = ig.premium(strike, strategy, amount);
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), user, address(ig), premium_, vm);
    }
}
