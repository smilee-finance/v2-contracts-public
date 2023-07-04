// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVP} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IVault} from "./interfaces/IVault.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";
import {DVPType} from "./lib/DVPType.sol";
import {Finance} from "./lib/Finance.sol";
import {Notional} from "./lib/Notional.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {WadTime} from "./lib/WadTime.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {DVP} from "./DVP.sol";

contract IG is DVP {
    using AmountsMath for uint256;
    using Notional for Notional.Info;

    struct FinanceParameters {
        uint256 kA;
        uint256 kB;
        uint256 theta;
        int256 alphaA;
        int256 alphaB;
        int256 limSup;
        int256 limInf;
        uint256 sigmaZero;
        uint256 sigmaMultiplier;
    }

    /// @notice Common strike price for all impermanent gain positions in this DVP, set at epoch start
    uint256 public currentStrike;
    FinanceParameters internal _currentFinanceParameters;

    constructor(address vault_, address addressProvider_) DVP(vault_, DVPType.IG, addressProvider_) {
        _currentFinanceParameters.sigmaMultiplier = 2;
    }

    /// @inheritdoc IDVP
    function mint(
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) external override returns (uint256 leverage) {
        strike;
        leverage = _mint(recipient, currentStrike, strategy, amount);
    }

    /// @inheritdoc IDVP
    function burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) external override returns (uint256 paidPayoff) {
        paidPayoff = _burn(epoch, recipient, strike, strategy, amount);
    }

    /// @inheritdoc IDVP
    function premium(uint256 strike, bool strategy, uint256 amount) public view virtual override returns (uint256) {
        // ToDo: review
        IMarketOracle marketOracle = IMarketOracle(_getMarketOracle());
        (uint256 igDBull, uint256 igDBear) = Finance.igPrices(Finance.DeltaPriceParams(
            marketOracle.getRiskFreeRate(sideToken, baseToken),
            _getTradeVolatility(strike, int256(amount)),
            strike,
            IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken),
            WadTime.nYears(WadTime.daysFromTs(block.timestamp, currentEpoch)),
            _currentFinanceParameters.kA,
            _currentFinanceParameters.kB,
            _currentFinanceParameters.theta,
            _currentFinanceParameters.limSup,
            _currentFinanceParameters.limInf,
            _currentFinanceParameters.alphaA,
            _currentFinanceParameters.alphaB
        ));

        if (strategy == OptionStrategy.CALL) {
            return amount.wmul(igDBull);
        } else {
            return amount.wmul(igDBear);
        }
    }

    /// @inheritdoc DVP
    function _payoffPerc(uint256 strike, bool strategy) internal view virtual override returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(_getPriceOracle());
        uint256 tokenPrice = priceOracle.getPrice(sideToken, baseToken);
        // ToDo: review
        (uint256 igPOBull, uint256 igPOBear) = Finance.igPayoffPerc(tokenPrice, strike, _currentFinanceParameters.kA, _currentFinanceParameters.kB, _currentFinanceParameters.theta);
        if (strategy == OptionStrategy.CALL) {
            return igPOBull;
        } else {
            return igPOBear;
        }
    }

    /// @inheritdoc DVP
    function _residualPayoff() internal view virtual override returns (uint256 residualPayoff) {
        Notional.Info storage liquidity = _liquidity[currentEpoch];

        uint256 pCall = liquidity.getAccountedPayoff(currentStrike, OptionStrategy.CALL);
        uint256 pPut = liquidity.getAccountedPayoff(currentStrike, OptionStrategy.PUT);

        residualPayoff = pCall + pPut;
    }

    /// @inheritdoc DVP
    function _accountResidualPayoffs() internal virtual override {
        _accountResidualPayoff(currentStrike, OptionStrategy.CALL);
        _accountResidualPayoff(currentStrike, OptionStrategy.PUT);
    }

    function _afterRollEpoch() internal virtual override {
        if (_lastRolledEpoch() != 0) {
            // Update strike price:
            // NOTE: both amounts are after equal weight rebalance, hence we can just compute their ratio.
            (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
            // ToDo: fix decimals
            // ToDo: check division by zero
            // ----- TBD: check if vault is dead
            currentStrike = sideTokenAmount.wdiv(baseTokenAmount);

            // ToDo: review
            uint256 baselineVolatility = IMarketOracle(_getMarketOracle()).getImpliedVolatility(baseToken, sideToken, currentStrike, epochFrequency);
            uint256 daysToMaturity = WadTime.daysFromTs(_lastRolledEpoch(), currentEpoch);
            uint256 yearsToMaturity = WadTime.nYears(daysToMaturity);
            (uint256 kA, uint256 kB) = Finance.liquidityRange(currentStrike, baselineVolatility, _currentFinanceParameters.sigmaMultiplier, yearsToMaturity);
            (int256 alphaA, int256 alphaB) = Finance._alfas(currentStrike, kA, kB, baselineVolatility, yearsToMaturity);
            uint256 theta = Finance._teta(currentStrike, kA, kB);
            (int256 limSup, int256 limInf) = Finance.lims(currentStrike, kA, kB, theta);
            _currentFinanceParameters.sigmaZero = baselineVolatility;
            _currentFinanceParameters.kA = kA;
            _currentFinanceParameters.kB = kB;
            _currentFinanceParameters.theta = theta;
            _currentFinanceParameters.alphaA = alphaA;
            _currentFinanceParameters.alphaB = alphaB;
            _currentFinanceParameters.limSup = limSup;
            _currentFinanceParameters.limInf = limInf;
        }

        super._afterRollEpoch();
    }

    /// @inheritdoc DVP
    function _allocateLiquidity(uint256 initialCapital) internal virtual override {
        Notional.Info storage liquidity = _liquidity[currentEpoch];

        // The impermanent gain DVP only has one strike:
        liquidity.setup(currentStrike);

        // The initialCapital is split 50:50 on the two strategies:
        uint256 halfInitialCapital = initialCapital / 2;
        liquidity.setInitial(currentStrike, OptionStrategy.CALL, halfInitialCapital);
        liquidity.setInitial(currentStrike, OptionStrategy.PUT, initialCapital - halfInitialCapital);
    }

    function _getUtilizationRateFactors() internal view virtual override returns (uint256 used, uint256 total) {
        // TBD: review decimals
        Notional.Info storage liquidity = _liquidity[currentEpoch];

        used += liquidity.getUsed(currentStrike, OptionStrategy.CALL);
        used += liquidity.getUsed(currentStrike, OptionStrategy.PUT);

        total += liquidity.getInitial(currentStrike, OptionStrategy.CALL);
        total += liquidity.getInitial(currentStrike, OptionStrategy.PUT);
    }

}
