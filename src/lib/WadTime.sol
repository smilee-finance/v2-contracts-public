// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ud, convert} from "@prb/math/UD60x18.sol";

/// @title Time utils to compute years or days in wads
library WadTime {

    error InvalidInput();

    // /**
    //     @notice Gives the number of days corresponding to a given fraction
    //     @param n The numerator of the fraction
    //     @param d The denominator of the fraction
    //     @return ndays The number of days in wads
    //  */
    // function daysFraction(uint256 n, uint256 d) public pure returns (uint256 ndays) {
    //     if (d == 0) {
    //         revert InvalidInput();
    //     }
    //     return convert(n).div(convert(d)).unwrap();
    // }

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
        return convert(end - start).div(convert(1 days)).unwrap();
    }

    /**
        @notice Gives the number of years corresponding to the given number of days (18 decimals)
        @param d The number of days in wads
        @return nYears_ number of years in wads
     */
    function nYears(uint256 d) public pure returns (uint256 nYears_) {
        return ud(d).div(convert(365)).unwrap();
    }
}
