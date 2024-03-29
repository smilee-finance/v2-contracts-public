// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IMutableToken {

    /**
        @notice Allows an admin to replace a token to something akin to it
        @param from The contract address of the original token
        @param to The contract address of the new token
     */
    function changeToken(address from, address to) external;

}
