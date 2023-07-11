// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IToken is IERC20 {

    /**
        @notice Returns the number of decimals used to get its user representation.
        @return number The number of decimals.
     */
    function decimals() external view returns (uint8 number);
}
