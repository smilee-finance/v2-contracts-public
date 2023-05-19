// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {IRegistry} from "../src/interfaces/IRegistry.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Vault} from "../src/Vault.sol";
import {IG} from "../src/IG.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";

contract PositionManagerTest is Test {
    bytes4 constant NotOwner = bytes4(keccak256("NotOwner()"));
    bytes4 constant CantBurnZero = bytes4(keccak256("CantBurnZero()"));
    bytes4 constant InvalidTokenID = bytes4(keccak256("InvalidTokenID()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));

    address baseToken;
    address sideToken;

    Vault vault;

    address alice = address(0x1);
    address bob = address(0x2);

    IPositionManager pm;
    IRegistry registry;

    constructor() {
        vault = Vault(VaultUtils.createVaultFromNothing(EpochFrequency.DAILY, address(0x10), vm));
        baseToken = vault.baseToken();
        sideToken = vault.sideToken();

        registry = IRegistry(TestnetToken(baseToken).getController());
    }

    function setUp() public {
        pm = new PositionManager(address(0x0));
        // NOTE: done in order to work with the limited transferability of the testnet tokens
        registry.register(address(pm));
    }

    function initAndMint() private returns (uint256 tokenId, IG ig) {
        ig = new IG(address(vault));
        ig.rollEpoch();

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, DEFAULT_SENDER, address(pm), 10 ether, vm);

        // NOTE: somehow, the sender is something else without this prank...
        vm.prank(DEFAULT_SENDER);
        (tokenId, ) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                premium: 10 ether,
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
        assertEq(10 ether, pos.premium);
        assertEq(1, pos.leverage);
        assertEq(1 * 10 ether, pos.notional);
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
        pm.sell(IPositionManager.SellParams({tokenId: tokenId, notional: 11 ether}));
    }

    function testMintAndBurn() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        pm.burn(tokenId);
        vm.expectRevert(InvalidTokenID);
        pm.positions(tokenId);
    }
}
