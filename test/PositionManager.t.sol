// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Test} from "forge-std/Test.sol";
import {ud, convert} from "@prb/math/UD60x18.sol";
import {IPositionManager} from "@project/interfaces/IPositionManager.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {OptionStrategy} from "@project/lib/OptionStrategy.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {IG} from "@project/IG.sol";
import {PositionManager} from "@project/periphery/PositionManager.sol";
import {IGAccessNFT} from "@project/periphery/IGAccessNFT.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {console} from "forge-std/console.sol";

contract PositionManagerTest is Test {
    bytes4 constant NotOwner = bytes4(keccak256("NotOwner()"));
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant InvalidTokenID = bytes4(keccak256("InvalidTokenID()"));
    bytes4 constant PositionExpired = bytes4(keccak256("PositionExpired()"));
    bytes4 constant AsymmetricAmount = bytes4(keccak256("AsymmetricAmount()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));
    bytes4 constant SlippedMarketValue = bytes4(keccak256("SlippedMarketValue()"));
    bytes4 constant NFTAccessDenied = bytes4(keccak256("NFTAccessDenied()"));
    bytes4 constant MissingAccessToken = bytes4(keccak256("MissingAccessToken()"));

    address baseToken;
    address sideToken;

    MockedVault vault;

    address admin = address(0x10);
    address alice = address(0x1);
    address bob = address(0x2);

    PositionManager pm;
    MockedRegistry registry;
    AddressProvider ap;
    FeeManager feeManager;
    IG ig;
    IGAccessNFT nft;

    constructor() {
        vm.warp(EpochFrequency.REF_TS + 1);

        vm.prank(admin);
        ap = new AddressProvider(0);

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        baseToken = vault.baseToken();
        sideToken = vault.sideToken();

        registry = MockedRegistry(ap.registry());
        feeManager = FeeManager(ap.feeManager());
    }

    function setUp() public {
        vm.startPrank(admin);
        pm = new PositionManager(address(ap));
        pm.grantRole(pm.ROLE_ADMIN(), admin);

        // NOTE: done in order to work with the limited transferability of the testnet tokens
        ap.setDvpPositionManager(address(pm));
        vm.stopPrank();

        // Suppose Vault has already liquidity
        VaultUtils.addVaultDeposit(alice, 100 ether, admin, address(vault), vm);

        vm.startPrank(admin);
        ig = new IG(address(vault), address(ap));
        ig.grantRole(ig.ROLE_ADMIN(), admin);
        ig.grantRole(ig.ROLE_EPOCH_ROLLER(), admin);
        registry.register(address(ig));

        vault.grantRole(vault.ROLE_ADMIN(), admin);
        vault.setAllowedDVP(address(ig));

        nft = new IGAccessNFT();
        nft.grantRole(nft.ROLE_ADMIN(), admin);
        ap.setDVPAccessNFT(address(nft));

        MarketOracle mo = MarketOracle(ap.marketOracle());

        mo.setDelay(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, 0, true);

        Utils.skipDay(true, vm);
        ig.rollEpoch();
        vm.stopPrank();
    }

    function _mint(uint256 tokenId_, address positionOwner, address sender, IG ig_, uint256 nftAccessTokenId) private returns (uint256 tokenId) {
        uint256 strike = ig_.currentStrike();
        uint256 slippage = 0.1e18;

        (uint256 expectedMarketValue, ) = ig_.premium(strike, 10 ether, 0);
        uint256 maxSpending = (expectedMarketValue * (1e18 + slippage)) / 1e18;
        TokenUtils.provideApprovedTokens(admin, baseToken, sender, address(pm), maxSpending, vm);

        // NOTE: somehow, the sender is something else without this prank...
        vm.prank(sender);
        (tokenId, ) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig_),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: strike,
                recipient: positionOwner,
                tokenId: tokenId_,
                expectedPremium: expectedMarketValue,
                maxSlippage: slippage,
                nftAccessTokenId: nftAccessTokenId
            })
        );
        assertGe(tokenId, 1);
        assertGe(pm.totalSupply(), 1);
        // should use all allowance and return different in case
        assertEq(0, IERC20(baseToken).allowance(sender, address(pm)));
    }

    function testMintNewPosition() public {
        uint256 tokenId = _mint(0, alice, DEFAULT_SENDER, ig, 0);
        assertEq(1, tokenId);
        assertEq(1, pm.balanceOf(alice));

        IPositionManager.PositionDetail memory pos = pm.positionDetail(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(false, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        Epoch memory epoch = ig.getEpoch();
        assertEq(epoch.current, pos.expiry);
        assertEq(10 ether, pos.notionalUp);
        assertEq(0, pos.notionalDown);
        assertEq(0, pos.cumulatedPayoff);
    }

    function testMintTwiceSamePosition() public {
        uint256 tokenId = _mint(0, alice, alice, ig, 0);
        assertEq(1, tokenId);

        IPositionManager.PositionDetail memory pos = pm.positionDetail(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(false, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        Epoch memory epoch = ig.getEpoch();
        assertEq(epoch.current, pos.expiry);
        assertEq(10 ether, pos.notionalUp);
        assertEq(0, pos.notionalDown);
        assertEq(0, pos.cumulatedPayoff);

        uint256 tokenIdSecondMint = _mint(tokenId, alice, alice, ig, 0);
        assertEq(tokenIdSecondMint, tokenId);
        pos = pm.positionDetail(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(false, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        epoch = ig.getEpoch();
        assertEq(epoch.current, pos.expiry);
        assertEq(20 ether, pos.notionalUp);
        assertEq(0, pos.notionalDown);
        assertEq(0, pos.cumulatedPayoff);
    }

    /**
     * Test mint same position but caller is not the owner
     */
    function testMintPositionNotOwner() public {
        uint256 tokenId = _mint(0, alice, DEFAULT_SENDER, ig, 0);

        TokenUtils.provideApprovedTokens(admin, baseToken, address(0x5), address(pm), 10 ether, vm);
        uint256 strike = ig.currentStrike();

        vm.prank(bob);
        vm.expectRevert(NotOwner);
        (tokenId, ) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: strike,
                recipient: address(0x5),
                tokenId: tokenId,
                expectedPremium: 0,
                maxSlippage: 0.1e18,
                nftAccessTokenId: 0
            })
        );
    }

    /**
     * Test mint same position but with invalid params
     */
    function testMintPositionInvalidToken() public {
        uint256 tokenId = _mint(0, alice, DEFAULT_SENDER, ig, 0);

        uint256 strike = ig.currentStrike();
        uint256 differentStrike = ig.currentStrike() + 100e18;
        IG differentIG = new IG(address(vault), address(ap));
        vm.prank(admin);
        registry.register(address(differentIG));

        // Different DVP from position
        vm.prank(alice);
        vm.expectRevert(InvalidTokenID);
        pm.mint(IPositionManager.MintParams({
                dvpAddr: address(differentIG),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: strike,
                recipient: alice,
                tokenId: tokenId,
                expectedPremium: 0,
                maxSlippage: 0.1e18,
                nftAccessTokenId: 0
            }));

        // Different strike from position
        vm.prank(alice);
        vm.expectRevert(InvalidTokenID);
        (tokenId, ) = pm.mint(IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: differentStrike,
                recipient: alice,
                tokenId: tokenId,
                expectedPremium: 0,
                maxSlippage: 0.1e18,
                nftAccessTokenId: 0
            }));
    }

    function testMintPositionAfterExpiry() public {
        uint256 tokenId = _mint(0, alice, alice, ig, 0);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        ig.rollEpoch();
        uint256 strike = ig.currentStrike();

        vm.prank(alice);
        vm.expectRevert(PositionExpired);
        (tokenId, ) = pm.mint(IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: strike,
                recipient: alice,
                tokenId: tokenId,
                expectedPremium: 0,
                maxSlippage: 0.1e18,
                nftAccessTokenId: 0
            }));
    }

    function testMintUnbalancedAmount() public {
        uint256 strike = ig.currentStrike();
        uint256 slippage = 0.1e18;

        (uint256 expectedMarketValue, ) = ig.premium(strike, 5e18, 5e18);
        uint256 maxSpending = (expectedMarketValue * (1e18 + slippage)) / 1e18;
        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(pm), maxSpending, vm);

        vm.prank(alice);
        vm.expectRevert(AsymmetricAmount);
        pm.mint(IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: 2e18,
                notionalDown: 4e18,
                strike: strike,
                recipient: alice,
                tokenId: 0,
                expectedPremium: expectedMarketValue,
                maxSlippage: slippage,
                nftAccessTokenId: 0
            })
        );
    }

    function testBurnPosition() public {
        uint256 tokenId = _mint(0, alice, alice, ig, 0);

        uint256 aliceBaseTokenBalance = IERC20(baseToken).balanceOf(alice);

        vm.warp(block.timestamp + 20000);

        IPositionManager.PositionDetail memory position = pm.positionDetail(tokenId);

        (uint256 pmExpectedMarketValue, ) = pm.payoff(tokenId, position.notionalUp, position.notionalDown);
        vm.prank(address(pm));
        (uint256 expectedMarketValue, ) = ig.payoff(position.expiry, position.strike, position.notionalUp, position.notionalDown);

        assertEq(pmExpectedMarketValue, expectedMarketValue);

        IPositionManager.SellParams memory params = IPositionManager.SellParams({
                tokenId: tokenId,
                notionalUp: position.notionalUp,
                notionalDown: position.notionalDown,
                expectedMarketValue: pmExpectedMarketValue,
                maxSlippage:0.1e18
        });

        vm.prank(alice);
        uint256 payoff = pm.sell(params);

        assertEq(aliceBaseTokenBalance + payoff, IERC20(baseToken).balanceOf(alice));
        assertEq(0, pm.balanceOf(alice));
    }

    /**
     * Test burn not owned position
     */
    function testCantBurnNotOwnedPosition() public {
        uint256 tokenId = _mint(0, alice, alice, ig, 0);

        IPositionManager.PositionDetail memory position = pm.positionDetail(tokenId);

        vm.prank(address(pm));
        (uint256 expectedMarketValue, ) = ig.payoff(position.expiry, position.strike, position.notionalUp, position.notionalDown);
        IPositionManager.SellParams memory params = IPositionManager.SellParams({
                tokenId: tokenId,
                notionalUp: position.notionalUp,
                notionalDown: position.notionalDown,
                expectedMarketValue: expectedMarketValue,
                maxSlippage:0.1e18
        });

        vm.prank(bob);
        vm.expectRevert(NotOwner);
        pm.sell(params);
    }

    function testMintAndBurnAllPosition() public {
        uint256 firstTokenId = _mint(0, alice, alice, ig, 0);
        uint256 secondTokenId = _mint(0, alice, alice, ig, 0);

        // assert alice has 2 differt position opened
        assertNotEq(firstTokenId, secondTokenId);
        assertEq(2, pm.balanceOf(alice));

        uint256 aliceBaseTokenBalance = IERC20(baseToken).balanceOf(alice);

        vm.warp(block.timestamp + 20000);

        IPositionManager.SellParams[] memory sellAllParams = new PositionManager.SellParams[](2);

        IPositionManager.PositionDetail memory position = pm.positionDetail(firstTokenId);
        vm.prank(address(pm));
        (uint256 expectedMarketValue, ) = ig.payoff(position.expiry, position.strike, position.notionalUp, position.notionalDown);

        sellAllParams[0] = IPositionManager.SellParams({
                tokenId: firstTokenId,
                notionalUp: position.notionalUp,
                notionalDown: position.notionalDown,
                expectedMarketValue: expectedMarketValue,
                maxSlippage:0.1e18
        });

        position = pm.positionDetail(secondTokenId);
        vm.prank(address(pm));
        (expectedMarketValue, ) = ig.payoff(position.expiry, position.strike, position.notionalUp, position.notionalDown);

        sellAllParams[1] = IPositionManager.SellParams({
                tokenId: secondTokenId,
                notionalUp: position.notionalUp,
                notionalDown: position.notionalDown,
                expectedMarketValue: expectedMarketValue,
                maxSlippage:0.1e18
        });

        vm.prank(alice);
        uint256 totalPayoff = pm.sellAll(sellAllParams);

        assertEq(aliceBaseTokenBalance + totalPayoff, IERC20(baseToken).balanceOf(alice));
        assertEq(0, pm.balanceOf(alice));
    }

    /**
     * Test burn all position, but one at least one position is not owned by the caller
     */
    function testMintAndBurnAllPositionWithNotOwned() public {
        uint256 firstTokenId = _mint(0, alice, alice, ig, 0);
        uint256 secondTokenId = _mint(0, bob, bob, ig, 0);

        vm.warp(block.timestamp + 20000);

        IPositionManager.SellParams[] memory sellAllParams = new PositionManager.SellParams[](2);

        IPositionManager.PositionDetail memory position = pm.positionDetail(firstTokenId);
        vm.prank(address(pm));
        (uint256 expectedMarketValue, ) = ig.payoff(position.expiry, position.strike, position.notionalUp, position.notionalDown);

        sellAllParams[0] = IPositionManager.SellParams({
                tokenId: firstTokenId,
                notionalUp: position.notionalUp,
                notionalDown: position.notionalDown,
                expectedMarketValue: expectedMarketValue,
                maxSlippage:0.1e18
        });

        position = pm.positionDetail(secondTokenId);
        vm.prank(address(pm));
        (expectedMarketValue, ) = ig.payoff(position.expiry, position.strike, position.notionalUp, position.notionalDown);

        sellAllParams[1] = IPositionManager.SellParams({
                tokenId: secondTokenId,
                notionalUp: position.notionalUp,
                notionalDown: position.notionalDown,
                expectedMarketValue: expectedMarketValue,
                maxSlippage:0.1e18
        });

        vm.prank(alice);
        vm.expectRevert(NotOwner);
        pm.sellAll(sellAllParams);
    }

    function testCantBurnTooMuch() public {
        uint256 tokenId = _mint(0, alice, alice, ig, 0);

        vm.prank(alice);
        vm.expectRevert(CantBurnMoreThanMinted);
        pm.sell(
            IPositionManager.SellParams({
                tokenId: tokenId,
                notionalUp: 11 ether,
                notionalDown: 0,
                expectedMarketValue: 0,
                maxSlippage: 0.1e18
            })
        );
    }

    function testCantBurnUnbalancedAmount() public {
            // Mint a smile position
            uint256 strike = ig.currentStrike();
            uint256 slippage = 0.1e18;

            (uint256 expectedMarketValue, ) = ig.premium(strike, 10 ether, 10 ether);
            uint256 maxSpending = (expectedMarketValue * (1e18 + slippage)) / 1e18;
            TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(pm), maxSpending, vm);

            vm.prank(alice);
            (uint256 tokenId, ) = pm.mint(
                IPositionManager.MintParams({
                    dvpAddr: address(ig),
                    notionalUp: 10 ether,
                    notionalDown: 10 ether,
                    strike: strike,
                    recipient: alice,
                    tokenId: 0,
                    expectedPremium: expectedMarketValue,
                    maxSlippage: slippage,
                    nftAccessTokenId: 0
                })
            );

            IPositionManager.PositionDetail memory position = pm.positionDetail(tokenId);
            vm.prank(address(pm));
            (expectedMarketValue, ) = ig.payoff(position.expiry, position.strike, position.notionalUp, position.notionalDown);

            vm.prank(alice);
            vm.expectRevert(AsymmetricAmount);
            pm.sell(
                IPositionManager.SellParams({
                    tokenId: tokenId,
                    notionalUp: 9 ether,
                    notionalDown: 1 ether,
                    expectedMarketValue: expectedMarketValue,
                    maxSlippage: 0.1e18
                })
            );
    }

    function testMintWithAccesTokenId() public {
        vm.startPrank(admin);
        uint256 pmAccessTokenId = nft.createToken(address(pm), 100e18);
        pm.setNftAccessToken(pmAccessTokenId);
        pm.setNftAccessFlag(true);
        ig.setNftAccessFlag(true);

        uint256 aliceAccessTokenId = nft.createToken(alice, 100e18);
        vm.stopPrank();

        uint256 tokenId = _mint(0, alice, alice, ig, aliceAccessTokenId);
        assertEq(1, tokenId);
        assertEq(1, pm.balanceOf(alice));

        IPositionManager.PositionDetail memory pos = pm.positionDetail(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(false, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        Epoch memory epoch = ig.getEpoch();
        assertEq(epoch.current, pos.expiry);
        assertEq(10 ether, pos.notionalUp);
        assertEq(0, pos.notionalDown);
        assertEq(0, pos.cumulatedPayoff);
    }

    /**
     * Test a priority access mint is called by not the owner of the NFT
     */
    function testMintWithAccesTokenIdOwnerNotSender() public {
        vm.startPrank(admin);
        uint256 pmAccessTokenId = nft.createToken(address(pm), 100e18);

        pm.setNftAccessToken(pmAccessTokenId);
        pm.setNftAccessFlag(true);
        ig.setNftAccessFlag(true);

        uint256 bobAccessTokenId = nft.createToken(bob, 100e18);
        vm.stopPrank();

        uint256 strike = ig.currentStrike();
        uint256 slippage = 0.1e18;

        (uint256 expectedMarketValue, ) = ig.premium(strike, 10 ether, 0);
        uint256 maxSpending = (expectedMarketValue * (1e18 + slippage)) / 1e18;
        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(pm), maxSpending, vm);

        vm.prank(alice);
        vm.expectRevert(NFTAccessDenied);
        pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: strike,
                recipient: alice,
                tokenId: 0,
                expectedPremium: expectedMarketValue,
                maxSlippage: slippage,
                nftAccessTokenId: bobAccessTokenId
            })
        );
    }

    function testMissingAccessToken() public {
        vm.startPrank(admin);

        vm.expectRevert(MissingAccessToken);
        pm.setNftAccessFlag(true);

        vm.expectRevert(MissingAccessToken);
        pm.setNftAccessToken(0);
        vm.stopPrank();
    }
}
