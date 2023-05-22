// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {Utils} from "./utils/Utils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Registry} from "../src/Registry.sol";
import {Vault} from "../src/Vault.sol";

contract IGTest is Test {
    bytes4 constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));

    address baseToken;
    address sideToken;
    Vault vault;
    Registry registry;
    MockedIG ig;

    address admin = address(0x10);
    address alice = address(0x1);
    address bob = address(0x2);

    constructor() {
        registry = new Registry();
        //ToDo: Get controller from baseToken as done in PositionManager.t.sol
        vault = Vault(VaultUtils.createVaultFromNothingWithRegistry(EpochFrequency.DAILY, admin, vm, registry));

        baseToken = vault.baseToken();
        sideToken = vault.sideToken();
    }

    function setUp() public {
        // ig = new MockedIG(address(vault));
        // registry.register(address(ig));
        // ig.useFakeDeltaHedge();

        // // Roll first epoch (this enables deposits)
        // ig.rollEpoch();

        // // Suppose Vault has already liquidity
        // TokenUtils.provideApprovedTokens(admin, address(baseToken), address(alice), address(vault), 100 ether, vm);
        // vm.prank(alice);
        // vault.deposit(100 ether);

        // Utils.skipDay(true, vm);

        // ig.rollEpoch();
    }

    function testIno() public {
        ig = new MockedIG(address(vault));
        registry.register(address(ig));
        ig.useFakeDeltaHedge();

        // Roll first epoch (this enables deposits)
        ig.rollEpoch();

        // Suppose Vault has already liquidity
        TokenUtils.provideApprovedTokens(admin, address(baseToken), address(alice), address(vault), 100 ether, vm);
        vm.prank(alice);
        vault.deposit(100 ether);

        Utils.skipDay(true, vm);

        ig.rollEpoch();
    }

    // ToDo: review with a different vault
    // function testCantCreate() public {
    //     vm.expectRevert(AddressZero);
    //   //     new MockedIG(address(vault));
    // }

    function testCantUse() public {
        //IDVP ig = new MockedIG(address(vault));

        vm.expectRevert(NoActiveEpoch);
        ig.mint(address(0x1), 0, OptionStrategy.CALL, 1);
    }

    function testCanUse() public {
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), 1, vm);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, 1);
    }

    function testMint() public {
        uint256 inputAmount = 1;

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);

        bytes32 posId = keccak256(abi.encodePacked(alice, OptionStrategy.CALL, ig.currentStrike()));

        (uint256 amount, bool strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testMintSum() public {
        uint256 inputAmount = 1;

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);

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

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);
        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);
        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);

        vm.prank(alice);
        ig.burn(currEpoch, alice, 0, OptionStrategy.CALL, inputAmount);

        bytes32 posId = keccak256(abi.encodePacked(alice, OptionStrategy.CALL, ig.currentStrike()));

        (uint256 amount, bool strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), strike);
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
        ig.mint(alice, 0, aInputStrategy, inputAmount);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, bob, address(ig), inputAmount, vm);

        vm.prank(bob);
        ig.mint(bob, 0, bInputStrategy, inputAmount);

        bytes32 posId1 = keccak256(abi.encodePacked(alice, aInputStrategy, ig.currentStrike()));
        bytes32 posId2 = keccak256(abi.encodePacked(bob, bInputStrategy, ig.currentStrike()));

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
        ig.burn(currEpoch, alice, 0, aInputStrategy, inputAmount);
        vm.prank(bob);
        ig.burn(currEpoch, bob, 0, bInputStrategy, inputAmount);

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
        ig.mint(alice, 0, OptionStrategy.CALL, 0);
    }

    function testCantBurnMoreThanMinted() public {
        uint256 inputAmount = 1;

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        vm.prank(alice);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);

        uint256 epoch = ig.currentEpoch();
        vm.expectRevert(CantBurnMoreThanMinted);
        ig.burn(epoch, alice, 0, OptionStrategy.CALL, inputAmount + 1);
    }
}
