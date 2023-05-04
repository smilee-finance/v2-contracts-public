// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {Vault} from "../src/Vault.sol";
import {IG} from "../src/IG.sol";
import {PositionManager} from "../src/PositionManager.sol";

contract PositionManagerTest is Test {
    bytes4 constant NotOwner = bytes4(keccak256("NotOwner()"));
    bytes4 constant CantBurnZero = bytes4(keccak256("CantBurnZero()"));
    bytes4 constant InvalidTokenID = bytes4(keccak256("InvalidTokenID()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));

    address baseToken = address(0x11);
    address sideToken = address(0x22);

    Vault vault = new Vault(baseToken, sideToken, EpochFrequency.DAILY);

    address alice = address(0x1);
    address bob = address(0x2);

    IPositionManager pm;

    function setUp() public {
        pm = new PositionManager(address(0x0));
    }

    function initAndMint() private returns (uint256 tokenId, IG ig) {
        ig = new IG(baseToken, sideToken, address(vault));
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

        IPositionManager.PositionDetail memory pos = pm.positions(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(0, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        assertEq(OptionStrategy.CALL, pos.strategy);
        assertEq(ig.currentEpoch(), pos.expiry);
        assertEq(10, pos.premium);
        assertEq(1, pos.leverage);
        assertEq(1 * 10, pos.notional);
        assertEq(0, pos.cumulatedPayoff);
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
        pm.burn(tokenId);
        vm.expectRevert(InvalidTokenID);
        pm.positions(tokenId);
    }
}
