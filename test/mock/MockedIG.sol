// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IVault} from "../../src/interfaces/IVault.sol";
import {AmountsMath} from "../../src/lib/AmountsMath.sol";
import {Notional} from "../../src/lib/Notional.sol";
import {OptionStrategy} from "../../src/lib/OptionStrategy.sol";
import {Position} from "../../src/lib/Position.sol";
import {SignedMath} from "../../src/lib/SignedMath.sol";
import {IG} from "../../src/IG.sol";

//ToDo: Add comments
contract MockedIG is IG {
    using AmountsMath for uint256;

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

    function premium(uint256 strike, uint256 amountUp, uint256 amountDown) public view override returns (uint256) {
        if (_fakePremium) {
            return ((amountUp + amountDown) * _optionPrice) / 10000;
        }
        return super.premium(strike, amountUp, amountDown);
    }

    function _getMarketValue(uint256 strike, Notional.Amount memory amount, bool tradeIsBuy, uint256 swapPrice) internal view virtual override returns (uint256) {
        if (_fakePremium || _fakePayoff) {
            // ToDo: review
            uint256 amountAbs = amount.up + amount.down;
            if (_fakePremium) {
                return (amountAbs * _optionPrice) / 10000;
            }
            if (_fakePayoff) {
                return amountAbs * _payoffPercentage;
            }
        }

        return super._getMarketValue(strike, amount, tradeIsBuy, swapPrice);
    }

    function _residualPayoffPerc(uint256 strike, bool strategy) internal view virtual override returns (uint256 percentage) {
        if (_fakePayoff) {
            return _payoffPercentage;
        }
        return super._residualPayoffPerc(strike, strategy);
    }

    function _deltaHedgePosition(uint256 strike, Notional.Amount memory amount, bool tradeIsBuy) internal override returns (uint256 swapPrice) {
        if (_fakeDeltaHedge) {
            IVault(vault).deltaHedge(-int256((amount.up + amount.down) / 4));
            return 1e18;
        }
        return super._deltaHedgePosition(strike, amount, tradeIsBuy);
    }

    // ToDo: review usage
    function positions(
        bytes32 positionID
    ) public view returns (uint256 amount, bool strategy, uint256 strike, uint256 epoch) {
        Position.Info storage position = _epochPositions[currentEpoch][positionID];
        strategy = (position.amountUp > 0) ? OptionStrategy.CALL : OptionStrategy.PUT;
        amount = (strategy) ? position.amountUp : position.amountDown;

        return (amount, strategy, position.strike, position.epoch);
    }

    function getUtilizationRate() public view returns (uint256) {
        (uint256 used, uint256 total) = _getUtilizationRateFactors();

        used = AmountsMath.wrapDecimals(used, _baseTokenDecimals);
        total = AmountsMath.wrapDecimals(total, _baseTokenDecimals);

        return used.wdiv(total);
    }

    function getCurrentFinanceParameters() public view returns (FinanceParameters memory) {
        return _currentFinanceParameters;
    }

    function setSigmaMultiplier(uint256 value) public {
        _currentFinanceParameters.sigmaMultiplier = value;
    }
}
