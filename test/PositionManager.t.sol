// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {IG} from "../src/IG.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {PositionManager} from "../src/PositionManager.sol";

import {console} from "forge-std/console.sol";

contract PositionManagerTest is Test {
    // Errors hashes
    // bytes4 private constant NoActiveEpoch = bytes4(keccak256("NoActiveEpoch()"));

    address baseToken = address(0x11);
    address sideToken = address(0x22);

    address alice = address(0x1);

    function setUp() public {}

    function testMint() public {
        IG ig = new IG(baseToken, sideToken, EpochFrequency.DAILY, 0);
        ig.rollEpoch();

        IPositionManager pm = new PositionManager(address(0x0));

        (uint256 tokenId, uint256 posLiquidity) = pm.mint(
            IPositionManager.MintParams({dvpAddr: address(ig), premium: 10, strike: 0, strategy: 0, recipient: alice})
        );

        assertEq(1, tokenId);

        (
            address pos_dvpAddr,
            address pos_baseToken,
            address pos_sideToken,
            uint256 pos_dvpFreq,
            uint256 pos_dvpType,
            uint256 pos_strike,
            uint256 pos_strategy,
            uint256 pos_expiry,
            uint256 pos_premium,
            uint256 pos_leverage
        ) = pm.positions(tokenId);

        assertEq(address(ig), pos_dvpAddr);
        assertEq(baseToken, pos_baseToken);
        assertEq(sideToken, pos_sideToken);
        assertEq(EpochFrequency.DAILY, pos_dvpFreq);
        assertEq(0, pos_dvpType);
        assertEq(ig.currentStrike(), pos_strike);
        assertEq(0, pos_strategy);
        assertEq(ig.currentEpoch(), pos_expiry);
        assertEq(10, pos_premium);
        assertEq(1, pos_leverage);
    }
}
