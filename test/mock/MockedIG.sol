// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Position} from "../../src/lib/Position.sol";
import {IG} from "../../src/IG.sol";

contract MockedIG is IG {
    bool internal _fakePremium;
    bool internal _fakePayoff;
    uint256 internal _optionPrice; // expressed in basis point (1% := 100)
    uint256 internal _payoffPerc; // expressed in basis point (1% := 100)

    constructor(address vault_) IG(vault_) {}

    function setOptionPrice(uint256 value) public {
        _optionPrice = value;
        _fakePremium = true;
    }
    
    function setPayoffPerc(uint256 value) public {
        _payoffPerc = value;
        _fakePayoff = true;
    }

    function useRealPremium() public {
        _fakePremium = false;
    }

    function premium(uint256 strike, bool strategy, uint256 amount) public view override returns (uint256) {
        if (_fakePremium) {
            return (amount * _optionPrice) / 10000;
        }
        return super.premium(strike, strategy, amount);
    }

    function payoff(uint256 epoch, uint256 strike, bool strategy) public view override returns (uint256) {
        Position.Info memory position = _getPosition(epoch, Position.getID(msg.sender, strategy, strike));

        if (_fakePayoff) {
            return (position.amount * _payoffPerc) / 10000;
        }
        return super.payoff(epoch, strike, strategy);
    }
}
