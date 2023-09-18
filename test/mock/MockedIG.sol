// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IVault} from "../../src/interfaces/IVault.sol";
import {Amount} from "../../src/lib/Amount.sol";
import {AmountsMath} from "../../src/lib/AmountsMath.sol";
import {FinanceParameters} from "../../src/lib/FinanceIG.sol";
import {Notional} from "../../src/lib/Notional.sol";
import {OptionStrategy} from "../../src/lib/OptionStrategy.sol";
import {Position} from "../../src/lib/Position.sol";
import {SignedMath} from "../../src/lib/SignedMath.sol";
import {IG} from "../../src/IG.sol";
import {Epoch, EpochController} from "../../src/lib/EpochController.sol";

//ToDo: Add comments
contract MockedIG is IG {
    using AmountsMath for uint256;
    using Notional for Notional.Info;
    using EpochController for Epoch;

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

    function _getMarketValue(uint256 strike, Amount memory amount, bool tradeIsBuy, uint256 swapPrice) internal view virtual override returns (uint256) {
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

    function _residualPayoffPerc(uint256 strike) internal view virtual override returns (uint256 percentageCall, uint256 percentagePut) {
        if (_fakePayoff) {
            return (_payoffPercentage, _payoffPercentage);
        }
        return super._residualPayoffPerc(strike);
    }

    function _deltaHedgePosition(uint256 strike, Amount memory amount, bool tradeIsBuy) internal override returns (uint256 swapPrice) {
        if (_fakeDeltaHedge) {
            IVault(vault).deltaHedge(-int256((amount.up + amount.down) / 4));
            return 1e18;
        }
        return super._deltaHedgePosition(strike, amount, tradeIsBuy);
    }

    // ToDo: review usage
    function positions(
        bytes32 positionID
    ) public view returns (uint256 amount, bool strategy, uint256 strike, uint256 epoch_) {
        Position.Info storage position = _epochPositions[getEpoch().current][positionID];
        strategy = (position.amountUp > 0) ? OptionStrategy.CALL : OptionStrategy.PUT;
        amount = (strategy) ? position.amountUp : position.amountDown;

        return (amount, strategy, position.strike, position.epoch);
    }

    function getUtilizationRate() public view returns (uint256) {
        (uint256 used, uint256 total) = _liquidity[getEpoch().current].utilizationRateFactors(_financeParameters.currentStrike);

        used = AmountsMath.wrapDecimals(used, _baseTokenDecimals);
        total = AmountsMath.wrapDecimals(total, _baseTokenDecimals);

        return used.wdiv(total);
    }

    function getCurrentFinanceParameters() public view returns (FinanceParameters memory) {
        return _financeParameters;
    }

    function setSigmaMultiplier(uint256 value) public {
        _financeParameters.sigmaMultiplier = value;
    }

    /**
        @notice Get number of past and current epochs
        @return number The number of past and current epochs
     */
    function getNumberOfEpochs() external view returns(uint256 number) {
        number = getEpoch().numberOfRolledEpochs;
    }

    /**
        @dev Second last timestamp
     */
    function lastRolledEpoch() public view returns (uint256 lastEpoch) {
        lastEpoch = getEpoch().previous;
    }

    function currentEpoch() external view returns (uint256) {
        return getEpoch().current;
    }

}
