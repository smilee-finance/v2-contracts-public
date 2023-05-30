// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IVault} from "../../src/interfaces/IVault.sol";
import {IG} from "../../src/IG.sol";

//ToDo: Add comments
contract MockedIG is IG {
    bool internal _fakePremium;
    bool internal _fakePayoff;

    bool internal _fakeDeltaHedge;

    uint256 internal _optionPrice; // expressed in basis point (1% := 100)
    uint256 internal _payoffPercentage; // expressed in basis point (1% := 100)

    constructor(address vault_, address addressProvider_) IG(vault_, addressProvider_) {}

    function setOptionPrice(uint256 value) public {
        _optionPrice = value;
        _fakePremium = true;
    }

    function setPayoffPerc(uint256 value) public {
        _payoffPercentage = value;
        _fakePayoff = true;
    }

    function useRealPremium() public {
        _fakePremium = false;
    }

    function useFakeDeltaHedge() public {
        _fakeDeltaHedge = true;
    }

    function useRealDeltaHedge() public {
        _fakeDeltaHedge = false;
    }

    function useRealPercentage() public {
        _fakePayoff = false;
    }

    function premium(uint256 strike, bool strategy, uint256 amount) public view override returns (uint256) {
        if (_fakePremium) {
            return (amount * _optionPrice) / 10000;
        }
        return super.premium(strike, strategy, amount);
    }

    function _payoffPerc(uint256 strike, bool strategy) internal view virtual override returns (uint256 percentage) {
        if (_fakePayoff) {
            return _payoffPercentage;
        }
        return super._payoffPerc(strike, strategy);
    }

    function _deltaHedge(uint256 strike, bool strategy, uint256 amount) internal override {
        if (_fakeDeltaHedge) {
            IVault(vault).deltaHedge(-int256(amount / 4));
            return;
        }
        super._deltaHedge(strike, strategy, amount);
    }
}
