// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultProxy} from "../src/interfaces/IVaultProxy.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultProxy} from "../src/VaultProxy.sol";

import {MockedVault} from "./mock/MockedVault.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";

contract VaultProxyTest is Test {
    address _tokenAdmin = address(0x1);
    address _alice = address(0x2);
    address _bob = address(0x3);
    TestnetToken _baseToken;
    TestnetToken _sideToken;
    MockedVault _vault0;
    MockedVault _vault1;
    VaultProxy _proxy = new VaultProxy();

    /**
        @notice Creates a couple of vaults.
     */
    function setUp() public {
        vm.warp(EpochFrequency.REF_TS + 1);
        vm.prank(_tokenAdmin);

        AddressProvider ap = new AddressProvider();
        _vault0 = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, _tokenAdmin, vm));
        _baseToken = TestnetToken(_vault0.baseToken());
        _sideToken = TestnetToken(_vault0.sideToken());
        _vault1 = MockedVault(
            VaultUtils.createVaultFromTokens(
                address(_baseToken),
                address(_sideToken),
                EpochFrequency.WEEKLY,
                ap,
                _tokenAdmin,
                vm
            )
        );
        _vault0.rollEpoch();
        _vault1.rollEpoch();

        // enable token transfers to allow transfers to proxy
        // TODO - enable test without need to unblock all transfers
        vm.prank(_tokenAdmin);
        _baseToken.setTransferBlocked(false);
        vm.prank(_tokenAdmin);
        _sideToken.setTransferBlocked(false);
    }

    /**
        Check simple deposit works
     */
    function testDeposit() public {
        TokenUtils.provideApprovedTokens(_tokenAdmin, address(_baseToken), _alice, address(_proxy), 100, vm);
        vm.prank(_alice);
        _proxy.deposit(IVaultProxy.DepositParams(address(_vault0), _alice, 100));
        Utils.skipDay(false, vm);
        _vault0.rollEpoch();

        (, uint256 unredeemedShares) = _vault0.shareBalances(_alice);
        assertEq(100, _vault0.totalSupply());
        assertEq(100, unredeemedShares);
    }

    /**
        Check multiple deposits can be done with a single approval
     */
    function testMultipleDeposit() public {
        TokenUtils.provideApprovedTokens(_tokenAdmin, address(_baseToken), _alice, address(_proxy), 200, vm);

        vm.prank(_alice);
        _proxy.deposit(IVaultProxy.DepositParams(address(_vault0), _alice, 100));

        vm.prank(_alice);
        _proxy.deposit(IVaultProxy.DepositParams(address(_vault1), _alice, 100));

        Utils.skipDay(false, vm);
        _vault0.rollEpoch();

        for (uint256 i = 0; i < 6; i++) {
            Utils.skipDay(false, vm);
        }
        _vault1.rollEpoch();

        (, uint256 unredeemedShares0) = _vault0.shareBalances(_alice);
        (, uint256 unredeemedShares1) = _vault1.shareBalances(_alice);
        assertEq(100, _vault0.totalSupply());
        assertEq(100, unredeemedShares0);

        assertEq(100, _vault1.totalSupply());
        assertEq(100, unredeemedShares1);
    }
}
