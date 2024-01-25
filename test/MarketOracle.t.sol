// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";

contract MarketOracleTest is Test {

    MarketOracle marketOracle;

    address admin = address(777);
    address baseToken = address(111);
    address sideToken = address(222);

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.startPrank(admin);
        
        marketOracle = new MarketOracle();
        marketOracle.grantRole(marketOracle.ROLE_ADMIN(), admin);

        vm.stopPrank();       
    }

    function testSetMaxDelay() public {
        uint256 timeWindow = 86400;
        uint256 newDelay = 2 hours;

        vm.prank(admin);
        marketOracle.setMaxDelay(baseToken, sideToken, timeWindow, newDelay);

        uint256 delay = marketOracle.getMaxDelay(baseToken, sideToken, timeWindow);
        assertEq(newDelay, delay);
    }

    function getDefaultMaxDelay() public {
        uint256 timeWindow = 86400;

        uint256 delay = marketOracle.getMaxDelay(baseToken, sideToken, timeWindow);
        assertEq(4 hours, delay);
    }

    function testSetImpliedVolatility() public {
        uint256 timeWindow = 86400;
        uint256 newIvValue = 5e18;

        vm.prank(admin);
        marketOracle.setImpliedVolatility(baseToken, sideToken, timeWindow, newIvValue);

        uint256 iv = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);

        assertEq(newIvValue, iv);
    }

    function testSetRiskFreeRate() public {
        uint256 newRiskFreeRateValue = 0.2e18;

        vm.prank(admin);
        marketOracle.setRiskFreeRate(sideToken, newRiskFreeRateValue);

        uint256 riskFreeRate = marketOracle.getRiskFreeRate(sideToken);

        assertEq(newRiskFreeRateValue, riskFreeRate);
    }

    function testSetImpliedVolatilityOutOfAllowedRange() public {
        uint256 timeWindow = 86400;
        uint256 newIvValue = 11e18;


        vm.prank(admin);
        vm.expectRevert(MarketOracle.OutOfAllowedRange.selector);
        marketOracle.setImpliedVolatility(baseToken, sideToken, timeWindow, newIvValue);
    }

    function testSetRiskFreeRateOutOfAllowedRange() public {
        uint256 newRiskFreeRateValue = 0.3e18;

        vm.prank(admin);
        vm.expectRevert(MarketOracle.OutOfAllowedRange.selector);
        marketOracle.setRiskFreeRate(sideToken, newRiskFreeRateValue);
    }

    /**
     * Test Get Implied volatility with daily frequency of update.
     * The value's keeped before 1 day plus the max_delay set for the given tokens (default 4 hours)
     */
    function testGetImpliedVolatilityOfDailyBeforeAndAfterDelay() public {
        uint256 timeWindow = 86400;
        uint256 newIvValue = 5e18;

        vm.prank(admin);
        marketOracle.setImpliedVolatility(baseToken, sideToken, timeWindow, newIvValue);

        // It should still work: 1 day passed from last update
        vm.warp(block.timestamp + 1 days);
        uint256 ivValue = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(newIvValue, ivValue);


        // It should still work: 1 day and 4 hours passed from last update
        vm.warp(block.timestamp + 4 hours);
        marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(newIvValue, ivValue);

        // It should revert: 1 day, 4 hours and 5 minute passed from the last update. 
        vm.warp(block.timestamp + 5 minutes);
        vm.expectRevert(abi.encodeWithSelector(MarketOracle.StaleOracleValue.selector, baseToken, sideToken, timeWindow));
        marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);

    }

    /**
     * Test Get Implied volatility with weekly frequency of update.
     * The value's keeped before 7 days plus the max_delay set for the given tokens (default 4 hours)
     */
    function testGetImpliedVolatilityOfWeeklyBeforeAndAfterDelay() public {
        uint256 timeWindow = 86400 * 7;
        uint256 newIvValue = 5e18;

        vm.prank(admin);
        marketOracle.setImpliedVolatility(baseToken, sideToken, timeWindow, newIvValue);

        // It should still work: 7 day passed from last update
        vm.warp(block.timestamp + 7 days);
        uint256 ivValue = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(newIvValue, ivValue);


        // It should still work: 7 day and 4 hours passed from last update
        vm.warp(block.timestamp + 4 hours);
        marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(newIvValue, ivValue);

        // It should revert: 7 day, 4 hours and 5 minute passed from the last update. 
        vm.warp(block.timestamp + 5 minutes);
        vm.expectRevert(abi.encodeWithSelector(MarketOracle.StaleOracleValue.selector, baseToken, sideToken, timeWindow));
        marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
    }

    function testGetImpliedVolatilityOfNotSetTokenPair() public {
        uint256 timeWindow = 86400;

        uint256 ivValue = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(0.5e18, ivValue);
    }

}