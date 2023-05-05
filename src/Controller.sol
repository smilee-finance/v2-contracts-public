// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IExchange} from "./interfaces/IExchange.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IDVP} from "./interfaces/IDVP.sol";

contract Controller {
    IExchange internal exchange;

    /**
        @notice Contract constructor
        @param exchange_ The address of the Exchange contract
     */
    constructor(address exchange_) {
        exchange = IExchange(exchange_);
    }
}
