// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FeeManager} from "@project/FeeManager.sol";

contract FeeManagerTest is Test {
    FeeManager _feeManager;
    address _admin = address(0x1);
    address _fakeDVP = address(0x1001);

    function setUp() public {
        vm.startPrank(_admin);
        _feeManager = new FeeManager();
        // _feeManager.grantRole(_feeManager.ROLE_ADMIN(), _admin);
        vm.stopPrank();
    }

    function testFeeManagerSetter(
        uint256 timeToExpiryThreshold,
        uint256 minFeeBeforeThreshold,
        uint256 minFeeAfterThreshold,
        uint256 successFeeTier,
        uint256 vaultSellMinFee,
        uint256 feePercentage,
        uint256 capPercertage,
        uint256 mFeePercentage,
        uint256 mCapPercentage
    ) public {
        vm.startPrank(_admin);

        vm.assume(timeToExpiryThreshold != 0);
        vm.assume(minFeeBeforeThreshold < 5e6);
        vm.assume(minFeeAfterThreshold < 5e6);
        vm.assume(successFeeTier < 10e17);
        vm.assume(vaultSellMinFee < 5e6);
        vm.assume(feePercentage < 0.05e18);
        vm.assume(capPercertage < 0.3e18);
        vm.assume(mFeePercentage < 0.05e18);
        vm.assume(mCapPercentage < 0.3e18);

        FeeManager.FeeParams memory params = FeeManager.FeeParams(
            timeToExpiryThreshold,
            minFeeBeforeThreshold,
            minFeeAfterThreshold,
            successFeeTier,
            vaultSellMinFee,
            feePercentage,
            capPercertage,
            mFeePercentage,
            mCapPercentage
        );

        _feeManager.setDVPFee(_fakeDVP, params);

        {
            (
                uint256 timeToExpiryThresholdCheck,
                uint256 minFeeBeforeThresholdCheck,
                uint256 minFeeAfterThresholdCheck,
                uint256 successFeeTierCheck,
                uint256 vaultSellMinFeeCheck,
                uint256 feePercentageCheck,
                uint256 capPercentageCheck,
                uint256 maturityFeePercentageCheck,
                uint256 maturityCapPercentageCheck
            ) = _feeManager.dvpsFeeParams(_fakeDVP);

            assertEq(params.timeToExpiryThreshold, timeToExpiryThresholdCheck);
            assertEq(params.minFeeBeforeTimeThreshold, minFeeBeforeThresholdCheck);
            assertEq(params.minFeeAfterTimeThreshold, minFeeAfterThresholdCheck);
            assertEq(params.successFeeTier, successFeeTierCheck);
            assertEq(params.vaultSellMinFee, vaultSellMinFeeCheck);
            assertEq(params.feePercentage, feePercentageCheck);
            assertEq(params.capPercentage, capPercentageCheck);
            assertEq(params.maturityFeePercentage, maturityFeePercentageCheck);
            assertEq(params.maturityCapPercentage, maturityCapPercentageCheck);
        }

        vm.stopPrank();
    }

    function testTradeBuyFee() public {
        FeeManager.FeeParams memory params = FeeManager.FeeParams(
            3600, // 1H
            3e5,
            2e5,
            0.5e18,
            3e5,
            0.5e17, // Fee Applied to Notional
            0.1e17, // Fee Applied to Premium
            0.25e17,
            0.5e17
        );

        vm.prank(_admin);
        _feeManager.setDVPFee(_fakeDVP, params);

        // Check Notional Fee
        uint256 fakeEpochBeforeTreeshold = block.timestamp + 7200;

        uint256 premium = 200e18;
        uint256 amountUp = 30e18;
        uint256 amountDown = 5e18;

        uint256 expectedFee = 1.75e18;
        uint256 expectedMinFee = 3e5;

        (uint256 fee, uint256 vaultMinFee) = _feeManager.tradeBuyFee(
            _fakeDVP,
            fakeEpochBeforeTreeshold,
            amountUp + amountDown,
            premium,
            18
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Premium Fee
        premium = 0.2e18;

        expectedFee = 1e16;
        expectedMinFee = 3e5;

        (fee, vaultMinFee) = _feeManager.tradeBuyFee(
            _fakeDVP,
            fakeEpochBeforeTreeshold,
            premium,
            amountUp + amountDown,
            18
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Min Fee Before Threshold
        premium = 0.1e5;

        expectedFee = 3e5;
        expectedMinFee = 3e5;

        (fee, vaultMinFee) = _feeManager.tradeBuyFee(
            _fakeDVP,
            fakeEpochBeforeTreeshold,
            premium,
            amountUp + amountDown,
            18
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Min Fee After Threshold
        uint256 fakeEpochAfterTreeshold = block.timestamp + 3599;
        expectedFee = 2e5;
        expectedMinFee = 2e5;

        (fee, vaultMinFee) = _feeManager.tradeBuyFee(
            _fakeDVP,
            fakeEpochAfterTreeshold,
            premium,
            amountUp + amountDown,
            18
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);
    }

    //ToDo: Review with decimals.
    function testTradeSellFee() public {
        FeeManager.FeeParams memory params = FeeManager.FeeParams(
            3600, // 1H
            3e5,
            2e5,
            0.5e17, // 5%
            5e6,
            0.5e17, // Fee Applied to Notional
            0.1e17, // Fee Applied to Premium
            0.25e17, // Fee Applied to Notional
            0.05e17 // Fee Applied to Premium
        );

        vm.prank(_admin);
        _feeManager.setDVPFee(_fakeDVP, params);

        // Check Sell Without Profit No Maturity Reached (Premium based fee)
        uint256 premium = 20e18;
        uint256 initialPaidPremium = 30e18;
        uint256 amountUp = 3000e18;
        uint256 amountDown = 5e18;

        uint256 expectedFee = 200000000005000000;
        uint256 expectedMinFee = 5e6;

        (uint256 fee, uint256 vaultMinFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            18,
            false
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Sell Without Profit Maturity Reached (Premium based fee)
        premium = 20e18;
        initialPaidPremium = 30e18;
        amountUp = 3000e18;
        amountDown = 5e18;

        expectedFee = 1e17;
        expectedMinFee = 0;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            18,
            true
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Sell Without Profit No Maturity Reached (Notional based fee)
        premium = 200e18;
        initialPaidPremium = 300e18;
        amountUp = 30e18;
        amountDown = 5e18;

        expectedFee = 1750000000005000000;
        expectedMinFee = 5e6;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            18,
            false
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Sell Without Profit Maturity Reached (Notional based fee)
        premium = 200e18;
        initialPaidPremium = 300e18;
        amountUp = 30e18;
        amountDown = 5e18;

        expectedFee = 0.875e18;
        expectedMinFee = 0;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            18,
            true
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Sell With Profit No Maturity Reached (Premium based fee)
        premium = 20e18;
        initialPaidPremium = 10e18;
        amountUp = 3000e18;
        amountDown = 5e18;

        expectedFee = 700000000005000000;
        expectedMinFee = 5e6;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            18,
            false
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Sell With Profit Maturity Reached (Premium based fee)
        premium = 20e18;
        initialPaidPremium = 10e18;
        amountUp = 3000e18;
        amountDown = 5e18;

        expectedFee = 0.6e18; // 0.1 + 0.5
        expectedMinFee = 0;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            18,
            true
        );
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Sell With Profit No Maturity Reached (Notional based fee)
        premium = 200e18;
        initialPaidPremium = 100e18;
        amountUp = 30e18;
        amountDown = 5e18;

        expectedFee = 6750000000005000000;
        expectedMinFee = 5e6;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(_fakeDVP, amountUp + amountDown, premium, initialPaidPremium, 18, false);
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Sell With Profit Maturity Reached (Notional based fee)
        premium = 200e18;
        initialPaidPremium = 100e18;
        amountUp = 30e18;
        amountDown = 5e18;

        expectedFee = 5.875e18;
        expectedMinFee = 0;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(_fakeDVP, amountUp + amountDown, premium, initialPaidPremium, 18, true);
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Premium 0 No Maturity Reached

        premium = 0;

        expectedFee = 5e6;
        expectedMinFee = 5e6;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(_fakeDVP, amountUp + amountDown, premium, initialPaidPremium, 18, false);
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

        // Check Premium 0 Maturity Reached

        premium = 0;

        expectedFee = 0;
        expectedMinFee = 0;

        (fee, vaultMinFee) = _feeManager.tradeSellFee(_fakeDVP, amountUp + amountDown, premium, initialPaidPremium, 18, true);
        assertEq(expectedFee, fee);
        assertEq(expectedMinFee, vaultMinFee);

    }
}
