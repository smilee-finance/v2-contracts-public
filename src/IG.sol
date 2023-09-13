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
import {FinanceIGDelta} from "./lib/FinanceIGDelta.sol";
import {FinanceIGPayoff} from "./lib/FinanceIGPayoff.sol";
import {FinanceIGPrice} from "./lib/FinanceIGPrice.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {Notional} from "./lib/Notional.sol";
import {SignedMath} from "./lib/SignedMath.sol";
import {WadTime} from "./lib/WadTime.sol";
import {DVP} from "./DVP.sol";
import {EpochControls} from "./EpochControls.sol";

contract IG is DVP {
    using AmountsMath for uint256;
    using Notional for Notional.Info;

    error StrikeDoesNotMatch();

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
        uint256 amountUp,
        uint256 amountDown,
        uint256 expectedPremium,
        uint256 maxSlippage
    ) external override returns (uint256 premium_) {
        strike;
        Notional.Amount memory amount_ = Notional.Amount({up: amountUp, down: amountDown});

        premium_ = _mint(recipient, currentStrike, amount_, expectedPremium, maxSlippage);
    }

    /// @inheritdoc IDVP
    function burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown,
        uint256 expectedMarketValue,
        uint256 maxSlippage
    ) external override returns (uint256 paidPayoff) {
        Notional.Amount memory amount_ = Notional.Amount({up: amountUp, down: amountDown});

        paidPayoff = _burn(epoch, recipient, strike, amount_, expectedMarketValue, maxSlippage);
    }

    /// @inheritdoc IDVP
    function premium(
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) public view virtual override epochInitialized returns (uint256 premium_) {
        strike;
        uint256 swapPrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
        Notional.Amount memory amount_ = Notional.Amount({up: amountUp, down: amountDown});

        premium_ = _getMarketValue(currentStrike, amount_, true, swapPrice);
    }

    /// @inheritdoc DVP
    function _getMarketValue(
        uint256 strike,
        Notional.Amount memory amount,
        bool tradeIsBuy,
        uint256 swapPrice
    ) internal view virtual override returns (uint256 marketValue) {
        FinanceIGPrice.Parameters memory params;
        {
            params.r = IMarketOracle(_getMarketOracle()).getRiskFreeRate(sideToken, baseToken);
            params.sigma = getPostTradeVolatility(strike, amount, tradeIsBuy);
            params.k = strike;
            params.s = swapPrice;
            params.tau = WadTime.nYears(WadTime.daysFromTs(block.timestamp, currentEpoch));
            params.ka = _currentFinanceParameters.kA;
            params.kb = _currentFinanceParameters.kB;
            params.teta = _currentFinanceParameters.theta;
        }
        (uint256 igPBull, uint256 igPBear) = FinanceIGPrice.igPrices(params);

        amount.up = AmountsMath.wrapDecimals(amount.up, _baseTokenDecimals);
        amount.down = AmountsMath.wrapDecimals(amount.down, _baseTokenDecimals);

        // igP multiplies a notional computed as follow:
        // V0 * user% = V0 * amount / initial(strategy) = V0 * amount / (V0/2) = amount * 2
        marketValue = 2 * amount.up.wmul(igPBull).add(amount.down.wmul(igPBear));
        marketValue = AmountsMath.unwrapDecimals(marketValue, _baseTokenDecimals);
    }

    function notional()
        public
        view
        returns (uint256 bearNotional, uint256 bullNotional, uint256 bearAvailNotional, uint256 bullAvailNotional)
    {
        Notional.Info storage liquidity = _liquidity[currentEpoch];
        return liquidity.aggregatedInfo(currentStrike);
    }

    // NOTE: public for frontend usage
    // TODO: add a modifier to check lastRolledEpoch is < currentEpoch
    /**
        @notice Get the estimated implied volatility from a given trade.
        @param strike The trade strike.
        @param amount The trade notional (positive for buy, negative for sell).
        @return sigma The estimated implied volatility.
        @dev The oracle must provide an updated baseline volatility, computed just before the start of the epoch.
     */
    function getPostTradeVolatility(
        uint256 strike,
        Notional.Amount memory amount,
        bool tradeIsBuy
    ) public view returns (uint256 sigma) {
        uint256 baselineVolatility = _currentFinanceParameters.sigmaZero;

        uint256 U = _liquidity[currentEpoch].postTradeUtilizationRate(
            currentStrike,
            AmountsMath.wrapDecimals(amount.up + amount.down, _baseTokenDecimals),
            tradeIsBuy
        );
        uint256 t0 = lastRolledEpoch();
        uint256 T = currentEpoch - t0;

        return
            FinanceIGPrice.tradeVolatility(
                FinanceIGPrice.TradeVolatilityParams(
                    baselineVolatility,
                    _tradeVolatilityUtilizationRateFactor,
                    _tradeVolatilityTimeDecay,
                    U,
                    T,
                    t0
                )
            );
    }

    // TBD: wrap parameters in a "Trade" struct
    /// @inheritdoc DVP
    function _deltaHedgePosition(
        uint256 strike,
        Notional.Amount memory amount,
        bool tradeIsBuy
    ) internal virtual override returns (uint256 swapPrice) {
        FinanceIGDelta.DeltaHedgeParameters memory params;
        uint256 oraclePrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);

        // ToDo: review FinanceIGDelta.DeltaHedgeParameters (add tradeIsBuy ?)
        params.notionalUp = SignedMath.revabs(amount.up, tradeIsBuy);
        params.notionalDown = SignedMath.revabs(amount.down, tradeIsBuy);

        uint256 postTradeVol = getPostTradeVolatility(strike, amount, tradeIsBuy);

        {
            uint256 yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(block.timestamp, currentEpoch));
            (_currentFinanceParameters.alphaA, _currentFinanceParameters.alphaB) = FinanceIGDelta._alfas(
                strike,
                _currentFinanceParameters.kA,
                _currentFinanceParameters.kB,
                postTradeVol,
                yearsToMaturity
            );
        }

        {
            FinanceIGDelta.Parameters memory deltaParams;
            {
                deltaParams.sigma = postTradeVol;
                deltaParams.k = strike;
                deltaParams.s = oraclePrice;
                deltaParams.tau = WadTime.nYears(WadTime.daysFromTs(block.timestamp, currentEpoch));
                deltaParams.limSup = _currentFinanceParameters.limSup;
                deltaParams.limInf = _currentFinanceParameters.limInf;
                deltaParams.alfa1 = _currentFinanceParameters.alphaA;
                deltaParams.alfa2 = _currentFinanceParameters.alphaB;
            }

            (params.igDBull, params.igDBear) = FinanceIGDelta.igDeltas(deltaParams);

            params.strike = strike;
            (, params.sideTokensAmount) = IVault(vault).balances();

            params.baseTokenDecimals = _baseTokenDecimals;
            params.sideTokenDecimals = _sideTokenDecimals;
            Notional.Info storage liquidity = _liquidity[currentEpoch];
            (
                params.initialLiquidityBear,
                params.initialLiquidityBull,
                params.availableLiquidityBear,
                params.availableLiquidityBull
            ) = liquidity.aggregatedInfo(strike);

            params.theta = _currentFinanceParameters.theta;
            params.kb = _currentFinanceParameters.kB;
        }

        int256 tokensToSwap = FinanceIGDelta.h(params);
        if (tokensToSwap == 0) {
            return oraclePrice;
        }

        // NOTE: We negate the value because the protocol will sell side tokens when `h` is positive.
        uint256 exchangedBaseTokens = IVault(vault).deltaHedge(-tokensToSwap);
        exchangedBaseTokens = AmountsMath.wrapDecimals(exchangedBaseTokens, _baseTokenDecimals);

        swapPrice = exchangedBaseTokens.wdiv(
            AmountsMath.wrapDecimals(SignedMath.abs(tokensToSwap), _sideTokenDecimals)
        );
    }

    /// @inheritdoc DVP
    function _residualPayoffPerc(uint256 strike, bool strategy) internal view virtual override returns (uint256) {
        (uint256 igPOBull, uint256 igPOBear) = FinanceIGPayoff.igPayoffPerc(
            IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken),
            strike,
            _currentFinanceParameters.kA,
            _currentFinanceParameters.kB,
            _currentFinanceParameters.theta
        );
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
        if (lastRolledEpoch() != 0) {
            // ToDo: check if vault is dead

            {
                // Update strike price:
                // NOTE: both amounts are after equal weight rebalance, hence we can just compute their ratio.
                (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
                baseTokenAmount = AmountsMath.wrapDecimals(baseTokenAmount, _baseTokenDecimals);
                sideTokenAmount = AmountsMath.wrapDecimals(sideTokenAmount, _sideTokenDecimals);
                // ToDo: add test where we roll epochs without deposit
                // check division by zero
                if (baseTokenAmount == 0 || sideTokenAmount == 0) {
                    currentStrike = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
                } else {
                    currentStrike = baseTokenAmount.wdiv(sideTokenAmount);
                }
            }

            {
                // ToDo: review
                _currentFinanceParameters.sigmaZero = IMarketOracle(_getMarketOracle()).getImpliedVolatility(
                    baseToken,
                    sideToken,
                    currentStrike,
                    epochFrequency
                );
                uint256 yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(lastRolledEpoch(), currentEpoch));
                (_currentFinanceParameters.kA, _currentFinanceParameters.kB) = FinanceIGPrice.liquidityRange(
                    FinanceIGPrice.LiquidityRangeParams(
                        currentStrike,
                        _currentFinanceParameters.sigmaZero,
                        _currentFinanceParameters.sigmaMultiplier,
                        yearsToMaturity
                    )
                );

                // Multiply baselineVolatility for a safety margin of 0.9 after have calculated kA and Kb.
                _currentFinanceParameters.sigmaZero = _currentFinanceParameters.sigmaZero.wmul(0.9e18);

                _currentFinanceParameters.theta = FinanceIGPrice._teta(
                    currentStrike,
                    _currentFinanceParameters.kA,
                    _currentFinanceParameters.kB
                );

                uint256 v0 = IVault(vault).v0();
                (_currentFinanceParameters.limSup, _currentFinanceParameters.limInf) = FinanceIGDelta.lims(
                    currentStrike,
                    _currentFinanceParameters.kA,
                    _currentFinanceParameters.kB,
                    _currentFinanceParameters.theta,
                    v0
                );
            }
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
}
