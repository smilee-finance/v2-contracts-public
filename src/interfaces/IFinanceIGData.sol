// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IDVPImmutables} from "@project/interfaces/IDVPImmutables.sol";
import {FinanceParameters} from "@project/lib/FinanceIG.sol";

/**
    @title Single entry point for earn positions creation.
    @notice Allows to access vaults from a a single contract. Only for UX
            purposes, does not manage created positions.
 */
interface IFinanceIGData is IDVPImmutables {
    function financeParameters() external view returns (FinanceParameters memory financeParameters);
}
