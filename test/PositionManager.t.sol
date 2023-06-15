// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {IG} from "../src/IG.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";

contract PositionManagerTest is Test {
    bytes4 constant NotOwner = bytes4(keccak256("NotOwner()"));
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant InvalidTokenID = bytes4(keccak256("InvalidTokenID()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));

    address baseToken;
    address sideToken;

    MockedVault vault;

    address alice = address(0x1);
    address bob = address(0x2);

    IPositionManager pm;
    TestnetRegistry registry;

    constructor() {
        vm.warp(EpochFrequency.REF_TS + 1);
        vault = MockedVault(VaultUtils.createVaultFromNothing(EpochFrequency.DAILY, address(0x10), vm));
        baseToken = vault.baseToken();
        sideToken = vault.sideToken();

        registry = TestnetRegistry(TestnetToken(baseToken).getController());
    }

    function setUp() public {
        pm = new PositionManager();
        // NOTE: done in order to work with the limited transferability of the testnet tokens
        vm.prank(address(0x10));
        registry.registerPositionManager(address(pm));

        Utils.skipDay(true, vm);
        vault.rollEpoch();

        // Suppose Vault has already liquidity
        VaultUtils.addVaultDeposit(alice, 100 ether, address(0x10), address(vault), vm);

        Utils.skipDay(true, vm);
        vault.rollEpoch();
    }

    function initAndMint() private returns (uint256 tokenId, IG ig) {
        ig = new IG(address(vault), address(0x42));
        vm.prank(address(0x10));
        vault.setAllowedDVP(address(ig));
        
        Utils.skipDay(true, vm);
        ig.rollEpoch();

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, DEFAULT_SENDER, address(pm), 10 ether, vm);

        // NOTE: somehow, the sender is something else without this prank...
        vm.prank(DEFAULT_SENDER);
        (tokenId, ) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                notional: 10 ether,
                strike: 0,
                strategy: OptionStrategy.CALL,
                recipient: alice,
                tokenId: 0
            })
        );
    }

    function testMint() public {
        (uint256 tokenId, IG ig) = initAndMint();

        assertEq(1, tokenId);

        IPositionManager.PositionDetail memory pos = pm.positionDetail(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(false, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        assertEq(OptionStrategy.CALL, pos.strategy);
        assertEq(ig.currentEpoch(), pos.expiry);
        assertEq(10 ether, pos.notional);
        assertEq(10, pos.leverage);
        assertEq(1 ether, pos.premium);
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
        vm.expectRevert(AmountZero);
        pm.sell(IPositionManager.SellParams({tokenId: tokenId, notional: 0}));
    }

    function testCantBurnTooMuch() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        vm.expectRevert(CantBurnMoreThanMinted);
        pm.sell(IPositionManager.SellParams({tokenId: tokenId, notional: 11 ether}));
    }

    function testMintAndBurn() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        pm.burn(tokenId);

        // ToDo: improve checks
        vm.expectRevert(InvalidTokenID);
        pm.positionDetail(tokenId);
    }
}
