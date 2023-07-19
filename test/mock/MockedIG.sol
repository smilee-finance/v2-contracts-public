// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IVault} from "../../src/interfaces/IVault.sol";
import {Position} from "../../src/lib/Position.sol";
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

    function _premium(uint256 strike, bool strategy, uint256 amount, uint256 swapPrice) internal view virtual override returns (uint256) {
        if (_fakePremium) {
            return (amount * _optionPrice) / 10000;
        }
        return super._premium(strike, strategy, amount, swapPrice);
    }

    function _payoffPerc(uint256 strike, bool strategy) internal view virtual override returns (uint256 percentage) {
        if (_fakePayoff) {
            return _payoffPercentage;
        }
        return super._payoffPerc(strike, strategy);
    }

    function _deltaHedgePosition(uint256 strike, bool strategy, int256 amount) internal override returns (uint256 swapPrice) {
        if (_fakeDeltaHedge) {
            IVault(vault).deltaHedge(-int256(amount / 4));
            return 1e18;
        }
        return super._deltaHedgePosition(strike, strategy, amount);
    }

    // ToDo: review usage
    function positions(
        bytes32 positionID
    ) public view returns (uint256 amount, bool strategy, uint256 strike, uint256 epoch) {
        Position.Info storage position = _epochPositions[currentEpoch][positionID];

        return (position.amount, position.strategy, position.strike, position.epoch);
    }
}
