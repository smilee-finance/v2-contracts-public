// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AmountsMath} from "./AmountsMath.sol";

/// @title Time utils to compute years or days in wads
library WadTime {
    using AmountsMath for uint256;

    error InvalidInput();

    /**
        @notice Gives the number of days corresponding to a given fraction
        @param n The numerator of the fraction
        @param d The denominator of the fraction
        @return ndays The number of days in wads
     */
    function daysFraction(uint256 n, uint256 d) public pure returns (uint256 ndays) {
        if (d == 0) {
            revert InvalidInput();
        }
        return (n).wadd() / d;
    }

    /**
        @notice Gives the number of days corresponding to a given period
        @param start The starting timestamp of the reference period
        @param end The end timestamp of the reference period
        @return ndays The number of days between start and end in wads
     */
    function daysFromTs(uint256 start, uint256 end) public pure returns (uint256 ndays) {
        if (start > end) {
            revert InvalidInput();
        }
        return (end - start).wadd() / 1 days;
    }

    /**
        @notice Gives the number of years corresponding to the given number of days (18 decimals)
        @param d The number of days in wads
        @return nYears_ number of years in wads
     */
    function nYears(uint256 d) public pure returns (uint256 nYears_) {
        return d / 365;
    }
}
