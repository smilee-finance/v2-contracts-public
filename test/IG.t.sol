// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {Vault} from "../src/Vault.sol";
import {IG} from "../src/IG.sol";
import {AddressProvider} from "../src/AddressProvider.sol";

contract IGTest is Test {
    bytes4 constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));
    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));

    address baseToken = address(0x11);
    address sideToken = address(0x22);
    AddressProvider _ap = new AddressProvider();
    Vault vault = new Vault(baseToken, sideToken, EpochFrequency.DAILY, address(_ap));

    address alice = address(0x1);
    address bob = address(0x2);

    function setUp() public {}

    function testCantCreate() public {
        vm.expectRevert(AddressZero);
        new IG(address(0x0), address(0x0), address(vault));
    }

    function testCantUse() public {
        IDVP ig = new IG(baseToken, sideToken, address(vault));

        vm.expectRevert(NoActiveEpoch);
        ig.mint(address(0x1), 0, OptionStrategy.CALL, 1);
    }

    function testCanUse() public {
        IDVP ig = new IG(baseToken, sideToken, address(vault));
        ig.rollEpoch();
        ig.mint(address(0x1), 0, OptionStrategy.CALL, 1);
    }

    function testMint() public {
        uint256 inputAmount = 1;

        IG ig = new IG(baseToken, sideToken, address(vault));
        ig.rollEpoch();
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

        IG ig = new IG(baseToken, sideToken, address(vault));
        ig.rollEpoch();
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);

        bytes32 posId = keccak256(abi.encodePacked(alice, OptionStrategy.CALL, ig.currentStrike()));
        (uint256 amount, bool strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(2 * inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testMintAndBurn() public {
        uint256 inputAmount = 1;

        IG ig = new IG(baseToken, sideToken, address(vault));
        ig.rollEpoch();
        uint256 currEpoch = ig.currentEpoch();

        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);
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

        IG ig = new IG(baseToken, sideToken, address(vault));
        ig.rollEpoch();
        uint256 currEpoch = ig.currentEpoch();
        ig.mint(alice, 0, aInputStrategy, inputAmount);
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
        IDVP ig = new IG(baseToken, sideToken, address(vault));
        ig.rollEpoch();

        vm.expectRevert(AmountZero);
        ig.mint(alice, 0, OptionStrategy.CALL, 0);
    }

    function testCantBurnMoreThanMinted() public {
        uint256 inputAmount = 1;

        IDVP ig = new IG(baseToken, sideToken, address(vault));
        ig.rollEpoch();
        ig.mint(alice, 0, OptionStrategy.CALL, inputAmount);

        uint256 epoch = ig.currentEpoch();
        vm.expectRevert(CantBurnMoreThanMinted);
        ig.burn(epoch, alice, 0, OptionStrategy.CALL, inputAmount + 1);
    }
}
