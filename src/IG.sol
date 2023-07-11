// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVP} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IToken} from "./interfaces/IToken.sol";
import {IVault} from "./interfaces/IVault.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";
import {DVPType} from "./lib/DVPType.sol";
import {Finance} from "./lib/Finance.sol";
import {Notional} from "./lib/Notional.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {SignedMath} from "./lib/SignedMath.sol";
import {WadTime} from "./lib/WadTime.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {DVP} from "./DVP.sol";
import {EpochControls} from "./EpochControls.sol";

contract IG is DVP {
    using AmountsMath for uint256;
    using Notional for Notional.Info;

    // ToDo: review
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
    // ToDo: review
    FinanceParameters internal _currentFinanceParameters;

    constructor(address vault_, address addressProvider_) DVP(vault_, DVPType.IG, addressProvider_) {
        _currentFinanceParameters.sigmaMultiplier = AmountsMath.wrap(2);
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
        (uint256 igDBull, uint256 igDBear) = Finance.igPrices(_getFinanceParameters(strike, int256(amount)));

        // Convert base token notional to Wad for computations:
        uint8 decimals = IToken(baseToken).decimals();
        amount = AmountsMath.wrapDecimals(amount, decimals);

        if (strategy == OptionStrategy.CALL) {
            return AmountsMath.unwrapDecimals(amount.wmul(igDBull), decimals);
        } else {
            return AmountsMath.unwrapDecimals(amount.wmul(igDBear), decimals);
        }
    }

    /// @inheritdoc DVP
    function _deltaHedgePosition(uint256 strike, bool strategy, int256 notional) internal virtual override {
        // ToDo: review and complete formulas
        // TBD: use totalNotional := _liquidity.initial - (notional + _liquidity.used);
        (int256 igDBull, int256 igDBear) = Finance.igDeltas(_getFinanceParameters(strike, notional));

        // Convert base token notional to Wad for computations:
        uint8 decimals = IToken(baseToken).decimals();
        uint256 notionalWad = AmountsMath.wrapDecimals(SignedMath.abs(notional), decimals);

        bool positive = true;
        uint256 sideTokensAmount;
        if (strategy == OptionStrategy.CALL) {
            sideTokensAmount = notionalWad.wmul(SignedMath.abs(igDBull));
            if (igDBull < 0) {
                positive = false;
            }
        } else {
            sideTokensAmount = notionalWad.wmul(SignedMath.abs(igDBear));
            if (igDBear < 0) {
                positive = false;
            }
        }

        // Convert Wad amount to side tokens amount:
        decimals = IToken(sideToken).decimals();
        sideTokensAmount = AmountsMath.unwrapDecimals(sideTokensAmount, decimals);

        IVault(vault).deltaHedge(SignedMath.revabs(sideTokensAmount, positive));
    }

    function _getFinanceParameters(uint256 strike, int256 notional) internal view returns (Finance.DeltaPriceParams memory) {
        IMarketOracle marketOracle = IMarketOracle(_getMarketOracle());
        IPriceOracle priceOracle = IPriceOracle(_getPriceOracle());

        return Finance.DeltaPriceParams(
            AmountsMath.wrapDecimals(marketOracle.getRiskFreeRate(sideToken, baseToken), marketOracle.decimals()),
            _getTradeVolatility(strike, notional),
            strike,
            AmountsMath.wrapDecimals(priceOracle.getPrice(sideToken, baseToken), priceOracle.decimals()),
            WadTime.nYears(WadTime.daysFromTs(block.timestamp, currentEpoch)),
            _currentFinanceParameters.kA,
            _currentFinanceParameters.kB,
            _currentFinanceParameters.theta,
            _currentFinanceParameters.limSup,
            _currentFinanceParameters.limInf,
            _currentFinanceParameters.alphaA,
            _currentFinanceParameters.alphaB
        );
    }

    /// @inheritdoc DVP
    function _payoffPerc(uint256 strike, bool strategy) internal view virtual override returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(_getPriceOracle());
        uint256 tokenPrice = AmountsMath.wrapDecimals(priceOracle.getPrice(sideToken, baseToken), priceOracle.decimals());

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

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        if (_lastRolledEpoch() != 0) {
            // ToDo: check if vault is dead

            {
                // Update strike price:
                // NOTE: both amounts are after equal weight rebalance, hence we can just compute their ratio.
                (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
                baseTokenAmount = AmountsMath.wrapDecimals(baseTokenAmount, IToken(baseToken).decimals());
                sideTokenAmount = AmountsMath.wrapDecimals(sideTokenAmount, IToken(sideToken).decimals());
                // TBD: check division by zero
                currentStrike = sideTokenAmount.wdiv(baseTokenAmount);
            }

            // ToDo: review
            IMarketOracle marketOracle = IMarketOracle(_getMarketOracle());
            uint256 baselineVolatility = AmountsMath.wrapDecimals(marketOracle.getImpliedVolatility(baseToken, sideToken, currentStrike, epochFrequency), marketOracle.decimals());
            uint256 yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(_lastRolledEpoch(), currentEpoch));
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

    /// @inheritdoc DVP
    function _getUtilizationRateFactors() internal view virtual override returns (uint256 used, uint256 total) {
        Notional.Info storage liquidity = _liquidity[currentEpoch];

        used += liquidity.getUsed(currentStrike, OptionStrategy.CALL);
        used += liquidity.getUsed(currentStrike, OptionStrategy.PUT);

        total += liquidity.getInitial(currentStrike, OptionStrategy.CALL);
        total += liquidity.getInitial(currentStrike, OptionStrategy.PUT);
    }

}
