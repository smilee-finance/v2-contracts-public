// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FeeManager} from "../src/FeeManager.sol";

contract FeeManagerTest is Test {
    FeeManager feeManager;

    address admin = address(0x1);

    function setUp() public {
        vm.prank(admin);
        feeManager = new FeeManager(0.035e18, 0.125e18, 0.01e18, 0.1e18);
    }

    function testFeeManagerSetter(uint256 feePercentage, uint256 capPercertage, uint256 mFeePercentage, uint256 mCapPercentage) public {
        vm.startPrank(admin);
        feeManager.setFeePercentage(feePercentage);
        assertEq(feePercentage ,feeManager.feePercentage());
        feeManager.setCapPercentage(capPercertage);
        assertEq(capPercertage ,feeManager.capPercentage());
        feeManager.setFeeMaturityPercentage(mFeePercentage);
        assertEq(mFeePercentage ,feeManager.maturityFeePercentage());
        feeManager.setCapMaturityPercentage(mCapPercentage);
        assertEq(mCapPercentage ,feeManager.maturityCapPercentage());
        vm.stopPrank();
    }

    function testCalculateTradeFee() public {
        uint256 premium = 0.2e18;
        uint256 amountUp = 30000e18;
        uint256 amountDown = 5e18;


        uint256 expectedFee = 7e15;

        uint256 fee = feeManager.calculateTradeFee(premium, amountUp + amountDown, 18, false);
        assertEq(expectedFee, fee);
    }

    function testCalculateTradeFeeAfterMaturity() public {
        uint256 premium = 0.2e18;
        uint256 amountUp = 30000e18;
        uint256 amountDown = 5e18;


        uint256 expectedFee = 2e15;

        uint256 fee = feeManager.calculateTradeFee(premium, amountUp +  amountDown, 18, true);
        assertEq(expectedFee, fee);
    }
}
