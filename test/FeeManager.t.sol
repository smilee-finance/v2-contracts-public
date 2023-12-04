// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FeeManager} from "@project/FeeManager.sol";

contract FeeManagerTest is Test {
    FeeManager _feeManager;
    address _admin = address(0x1);

    function setUp() public {
        vm.startPrank(_admin);
        _feeManager = new FeeManager(FeeManager.Params(0, 0.035e18, 0.125e18, 0.01e18, 0.1e18, 0));
        _feeManager.grantRole(_feeManager.ROLE_ADMIN(), _admin);
        vm.stopPrank();
    }

    function testFeeManagerSetter(
        uint256 minFee,
        uint256 feePercentage,
        uint256 capPercertage,
        uint256 mFeePercentage,
        uint256 mCapPercentage
    ) public {
        vm.startPrank(_admin);

        vm.assume(minFee < 5e6);
        vm.assume(feePercentage < 0.05e18);
        vm.assume(capPercertage < 0.3e18);
        vm.assume(mFeePercentage < 0.05e18);
        vm.assume(mCapPercentage < 0.3e18);

        _feeManager.setMinFee(minFee);
        _feeManager.setFeePercentage(feePercentage);
        _feeManager.setCapPercentage(capPercertage);
        _feeManager.setMaturityFeePercentage(mFeePercentage);
        _feeManager.setMaturityCapPercentage(mCapPercentage);

        FeeManager.Params memory params = _feeManager.getParams();
        assertEq(minFee, params.minFee);
        assertEq(feePercentage, params.feePercentage);
        assertEq(capPercertage, params.capPercentage);
        assertEq(mFeePercentage, params.maturityFeePercentage);
        assertEq(mCapPercentage, params.maturityCapPercentage);

        vm.stopPrank();
    }

    function testTradeFee() public {
        uint256 premium = 0.2e18;
        uint256 amountUp = 30000e18;
        uint256 amountDown = 5e18;

        uint256 expectedFee = 7e15;

        uint256 fee = _feeManager.tradeFee(premium, amountUp + amountDown, 18, false);
        assertEq(expectedFee, fee);
    }

    function testTradeFeeAfterMaturity() public {
        uint256 premium = 0.2e18;
        uint256 amountUp = 30000e18;
        uint256 amountDown = 5e18;

        uint256 expectedFee = 2e15;

        uint256 fee = _feeManager.tradeFee(premium, amountUp + amountDown, 18, true);
        assertEq(expectedFee, fee);
    }
}
