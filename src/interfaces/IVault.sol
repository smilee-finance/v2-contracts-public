// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IVault {
    function getPortfolio() external view returns (uint256 baseTokenAmount, uint256 sideTokenAmount);

    function triggerEpochChange() external;
}