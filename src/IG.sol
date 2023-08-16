// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
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
    ) external override returns (uint256 premium_) {
        strike;
        premium_ = _mint(recipient, currentStrike, strategy, amount);
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
    function premium(
        uint256 strike,
        bool strategy,
        uint256 amount
    ) public view virtual override returns (uint256 premium_) {
        strike;
        uint256 swapPrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);

        premium_ = _getMarketValue(currentStrike, strategy, int256(amount), swapPrice);
    }

    /// @inheritdoc DVP
    function _getMarketValue(
        uint256 strike,
        bool strategy,
        int256 amount,
        uint256 swapPrice
    ) internal view virtual override returns (uint256 marketValue) {
        FinanceIGPrice.Parameters memory params;
        {
            params.r = IMarketOracle(_getMarketOracle()).getRiskFreeRate(sideToken, baseToken);
            params.sigma = getPostTradeVolatility(strike, amount);
            params.k = strike;
            params.s = swapPrice;
            params.tau = WadTime.nYears(WadTime.daysFromTs(block.timestamp, currentEpoch));
            params.ka = _currentFinanceParameters.kA;
            params.kb = _currentFinanceParameters.kB;
            params.teta = _currentFinanceParameters.theta;
        }

        (uint256 igPBull, uint256 igPBear) = FinanceIGPrice.igPrices(params);

        uint256 amountWad = AmountsMath.wrapDecimals(SignedMath.abs(amount), _baseTokenDecimals);
        // igP multiplies a notional computed as follow:
        // V0 * user% = V0 * amount / initial(strategy) = V0 * amount / (V0/2) = amount * 2
        if (strategy == OptionStrategy.CALL) {
            marketValue = amountWad.wmul(2e18).wmul(igPBull);
        } else {
            marketValue = amountWad.wmul(2e18).wmul(igPBear);
        }
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
    // TODO: add a modifier to check _lastRolledEpoch is < currentEpoch
    /**
        @notice Get the estimated implied volatility from a given trade.
        @param strike The trade strike.
        @param amount The trade notional (positive for buy, negative for sell).
        @return sigma The estimated implied volatility.
        @dev The oracle must provide an updated baseline volatility, computed just before the start of the epoch.
     */
    function getPostTradeVolatility(uint256 strike, int256 amount) public view returns (uint256 sigma) {
        uint256 baselineVolatility = IMarketOracle(_getMarketOracle()).getImpliedVolatility(
            baseToken,
            sideToken,
            strike,
            epochFrequency
        );
        uint256 U = _getPostTradeUtilizationRate(amount);
        uint256 t0 = _lastRolledEpoch();
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

    // TBD: move into library
    // TBD: inline
    /**
        @notice Preview the utilization rate that will result from a given trade.
        @param amount The trade notional (positive for buy, negative for sell).
        @return utilizationRate The post-trade utilization rate.
     */
    function _getPostTradeUtilizationRate(int256 amount) internal view returns (uint256 utilizationRate) {
        (uint256 used, uint256 total) = _getUtilizationRateFactors();
        if (used == 0 || total == 0) {
            return 0;
        }
        uint256 amountWad = AmountsMath.wrapDecimals(SignedMath.abs(amount), _baseTokenDecimals);

        // TBD: check division by zero
        if (amount >= 0) {
            return (used.add(amountWad)).wdiv(total);
        } else {
            return (used.sub(amountWad)).wdiv(total);
        }
    }

    /// @inheritdoc DVP
    function _deltaHedgePosition(
        uint256 strike,
        bool strategy,
        int256 notional_
    ) internal virtual override returns (uint256 swapPrice) {
        FinanceIGDelta.DeltaHedgeParameters memory params;
        uint256 oraclePrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);

        uint256 postTradeVol = getPostTradeVolatility(strike, notional_);

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

            // console.log("Notional_ Amount");
            // console.logInt(notional_);

            params.notionalUp = notional_;
            params.notionalDown = 0;
            if (strategy == OptionStrategy.PUT) {
                params.notionalDown = params.notionalUp;
                params.notionalUp = 0;
            }
            params.baseTokenDecimals = _baseTokenDecimals;
            params.sideTokenDecimals = _sideTokenDecimals;
            Notional.Info storage liquidity = _liquidity[currentEpoch];
            (
                params.initialLiquidityBear,
                params.initialLiquidityBull,
                params.availableLiquidityBear,
                params.availableLiquidityBull
            ) = liquidity.aggregatedInfo(strike);
        }

        int256 tokensToSwap = FinanceIGDelta.h(params);
        // console.log("TokenToSwap");
        // console.logInt(tokensToSwap);

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
        if (_lastRolledEpoch() != 0) {
            // ToDo: check if vault is dead

            {
                // Update strike price:
                // NOTE: both amounts are after equal weight rebalance, hence we can just compute their ratio.
                (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
                // console.log("baseTokenAmountBefore", baseTokenAmount);
                baseTokenAmount = AmountsMath.wrapDecimals(baseTokenAmount, _baseTokenDecimals);
                sideTokenAmount = AmountsMath.wrapDecimals(sideTokenAmount, _sideTokenDecimals);
                // console.log("baseTokenAmount", baseTokenAmount);
                // console.log("sideTokenAmount", sideTokenAmount);
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
                uint256 yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(_lastRolledEpoch(), currentEpoch));
                (_currentFinanceParameters.kA, _currentFinanceParameters.kB) = FinanceIGPrice.liquidityRange(
                    FinanceIGPrice.LiquidityRangeParams(
                        currentStrike,
                        _currentFinanceParameters.sigmaZero,
                        _currentFinanceParameters.sigmaMultiplier,
                        yearsToMaturity
                    )
                );

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

    /// @inheritdoc DVP
    function _getUtilizationRateFactors() internal view virtual override returns (uint256 used, uint256 total) {
        Notional.Info storage liquidity = _liquidity[currentEpoch];

        used += liquidity.getUsed(currentStrike, OptionStrategy.CALL);
        used += liquidity.getUsed(currentStrike, OptionStrategy.PUT);

        total += liquidity.getInitial(currentStrike, OptionStrategy.CALL);
        total += liquidity.getInitial(currentStrike, OptionStrategy.PUT);
    }
}
