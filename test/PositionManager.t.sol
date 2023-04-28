// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {IG} from "../src/IG.sol";
import {PositionManager} from "../src/PositionManager.sol";

contract PositionManagerTest is Test {
    bytes4 private constant NotOwner = bytes4(keccak256("NotOwner()"));
    bytes4 private constant CantBurnZero = bytes4(keccak256("CantBurnZero()"));
    bytes4 private constant InvalidTokenID = bytes4(keccak256("InvalidTokenID()"));
    bytes4 private constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));

    address baseToken = address(0x11);
    address sideToken = address(0x22);

    address alice = address(0x1);
    address bob = address(0x2);

    IPositionManager pm;

    function setUp() public {
        pm = new PositionManager(address(0x0));
    }

    function initAndMint() private returns (uint256 tokenId, IG ig) {
        ig = new IG(baseToken, sideToken, EpochFrequency.DAILY);
        ig.rollEpoch();

        (tokenId, ) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                premium: 10,
                strike: 0,
                strategy: OptionStrategy.CALL,
                recipient: alice
            })
        );
    }

    function testMint() public {
        (uint256 tokenId, IG ig) = initAndMint();

        assertEq(1, tokenId);

        (
            address pos_dvpAddr,
            address pos_baseToken,
            address pos_sideToken,
            uint256 pos_dvpFreq,
            uint256 pos_dvpType,
            uint256 pos_strike,
            bool pos_strategy,
            uint256 pos_expiry,
            uint256 pos_premium,
            uint256 pos_leverage,
            uint256 pos_notional,
            uint256 pos_cumulatedPayoff
        ) = pm.positions(tokenId);

        assertEq(address(ig), pos_dvpAddr);
        assertEq(baseToken, pos_baseToken);
        assertEq(sideToken, pos_sideToken);
        assertEq(EpochFrequency.DAILY, pos_dvpFreq);
        assertEq(0, pos_dvpType);
        assertEq(ig.currentStrike(), pos_strike);
        assertEq(OptionStrategy.CALL, pos_strategy);
        assertEq(ig.currentEpoch(), pos_expiry);
        assertEq(10, pos_premium);
        assertEq(1, pos_leverage);
        assertEq(1 * 10, pos_notional);
        assertEq(0, pos_cumulatedPayoff);
    }

    function testCantBurnNonOwner() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(bob);
        vm.expectRevert(NotOwner);
        pm.burn(tokenId);
    }

    function testCantBurnZero() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        vm.expectRevert(CantBurnZero);
        pm.sell(IPositionManager.SellParams({tokenId: tokenId, notional: 0}));
    }

    function testCantBurnTooMuch() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        vm.expectRevert(CantBurnMoreThanMinted);
        pm.sell(IPositionManager.SellParams({tokenId: tokenId, notional: 11}));
    }

    function testMintAndBurn() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        uint256 payoff = pm.burn(tokenId);
        vm.expectRevert(InvalidTokenID);
        pm.positions(tokenId);
    }
}
