// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IG} from "../../src/IG.sol";

contract MockedIG is IG {
    bool internal _fakePremium;
    uint256 internal _optionPrice; // expressed in basis point (1% := 100)

    constructor(
        address vault_
    ) IG(vault_) {}

    function setOptionPrice(uint256 value) public {
        _optionPrice = value;
        _fakePremium = true;
    }

    function useRealPremium() public {
        _fakePremium = false;
    }

    function _premium(uint256 strike, bool strategy, uint256 amount) internal view override returns (uint256) {
        if (_fakePremium) {
            return amount * _optionPrice / 10000;
        }
        return super._premium(strike, strategy, amount);
    }
}
