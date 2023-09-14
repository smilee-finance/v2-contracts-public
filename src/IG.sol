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
import {Epoch, EpochController} from "./lib/EpochController.sol";
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
    using EpochController for Epoch;

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

    /// @dev mutable parameter for the computation of the trade volatility
    uint256 internal _tradeVolatilityUtilizationRateFactor;
    /// @dev mutable parameter for the computation of the trade volatility
    uint256 internal _tradeVolatilityTimeDecay;

    constructor(address vault_, address addressProvider_) DVP(vault_, DVPType.IG, addressProvider_) {
        _currentFinanceParameters.sigmaMultiplier = 2e18;
        _tradeVolatilityUtilizationRateFactor = 2e18;
        _tradeVolatilityTimeDecay = 0.25e18;
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
    ) public view virtual override returns (uint256 premium_) {
        strike;
        if (!getEpoch().isInitialized()) {
            revert EpochNotInitialized();
        }
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
        // TBD: move everything to the FinanceIGPrice library
        FinanceIGPrice.Parameters memory params;
        {
            params.r = IMarketOracle(_getMarketOracle()).getRiskFreeRate(sideToken, baseToken);
            params.sigma = getPostTradeVolatility(strike, amount, tradeIsBuy);
            params.k = strike;
            params.s = swapPrice;
            params.tau = WadTime.nYears(WadTime.daysFromTs(block.timestamp, getEpoch().current));
            params.ka = _currentFinanceParameters.kA;
            params.kb = _currentFinanceParameters.kB;
            params.teta = _currentFinanceParameters.theta;
        }
        (uint256 igPBull, uint256 igPBear) = FinanceIGPrice.igPrices(params);

        marketValue = FinanceIGPrice.getMarketValue(amount.up, igPBull,  amount.down, igPBear, _baseTokenDecimals);
    }

    // ToDo: review
    function notional()
        public
        view
        returns (uint256 bearNotional, uint256 bullNotional, uint256 bearAvailNotional, uint256 bullAvailNotional)
    {
        Notional.Info storage liquidity = _liquidity[getEpoch().current];
        return liquidity.aggregatedInfo(currentStrike);
    }

    // NOTE: public for frontend usage
    // TODO: add a modifier to check lastRolledEpoch is < epoch.current
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
        Epoch memory epoch = getEpoch();

        uint256 U = _liquidity[epoch.current].postTradeUtilizationRate(
            currentStrike,
            AmountsMath.wrapDecimals(amount.up + amount.down, _baseTokenDecimals),
            tradeIsBuy
        );
        uint256 t0 = epoch.lastRolled();
        uint256 T = epoch.current - t0;

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
            uint256 yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(block.timestamp, getEpoch().current));
            (_currentFinanceParameters.alphaA, _currentFinanceParameters.alphaB) = FinanceIGDelta.alfas(
                strike,
                _currentFinanceParameters.kA,
                _currentFinanceParameters.kB,
                postTradeVol,
                yearsToMaturity
            );
        }

        {
            uint256 currentEpoch = getEpoch().current;
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

            (params.igDBull, params.igDBear) = FinanceIGDelta.deltaHedgePercentages(deltaParams);

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

        int256 tokensToSwap = FinanceIGDelta.deltaHedgeAmount(params);
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
    function _residualPayoffPerc(uint256 strike) internal view virtual override returns (uint256, uint256) {
        return FinanceIGPayoff.igPayoffPerc(
            IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken),
            strike,
            _currentFinanceParameters.kA,
            _currentFinanceParameters.kB,
            _currentFinanceParameters.theta
        );
    }

    /// @inheritdoc DVP
    function _residualPayoff() internal view virtual override returns (uint256 residualPayoff) {
        Notional.Info storage liquidity = _liquidity[getEpoch().current];

        (uint256 pCall, uint256 pPut) = liquidity.getAccountedPayoffs(currentStrike);

        residualPayoff = pCall + pPut;
    }

    /// @inheritdoc DVP
    function _accountResidualPayoffs() internal virtual override {
        _accountResidualPayoff(currentStrike);
    }

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        Epoch memory epoch = getEpoch();
        // TBD: use a better if condition or explain it
        if (epoch.previous != 0) {
            // ToDo: check if vault is dead

            {
                // Update strike price:
                // NOTE: both amounts are after equal weight rebalance, hence we can just compute their ratio.
                (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
                // ToDo: add test where we roll epochs without deposit
                // check division by zero
                if (baseTokenAmount == 0 || sideTokenAmount == 0) {
                    currentStrike = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
                } else {
                    baseTokenAmount = AmountsMath.wrapDecimals(baseTokenAmount, _baseTokenDecimals);
                    sideTokenAmount = AmountsMath.wrapDecimals(sideTokenAmount, _sideTokenDecimals);

                    currentStrike = baseTokenAmount.wdiv(sideTokenAmount);
                }
            }

            {
                // ToDo: review
                _currentFinanceParameters.sigmaZero = IMarketOracle(_getMarketOracle()).getImpliedVolatility(
                    baseToken,
                    sideToken,
                    currentStrike,
                    epoch.frequency
                );
                // ToDo: test what happens when epoch.previous is not equal to block.timestamp
                uint256 yearsToMaturity = WadTime.nYears(WadTime.daysFromTs(epoch.previous, epoch.current));
                (_currentFinanceParameters.kA, _currentFinanceParameters.kB) = FinanceIGPrice.liquidityRange(
                    FinanceIGPrice.LiquidityRangeParams(
                        currentStrike,
                        _currentFinanceParameters.sigmaZero,
                        _currentFinanceParameters.sigmaMultiplier,
                        yearsToMaturity
                    )
                );

                // Multiply baselineVolatility for a safety margin of 0.9 after have calculated kA and Kb.
                _currentFinanceParameters.sigmaZero = (_currentFinanceParameters.sigmaZero * 90) / 100;

                _currentFinanceParameters.theta = FinanceIGPrice._teta(
                    currentStrike,
                    _currentFinanceParameters.kA,
                    _currentFinanceParameters.kB
                );

                (_currentFinanceParameters.limSup, _currentFinanceParameters.limInf) = FinanceIGDelta.lims(
                    currentStrike,
                    _currentFinanceParameters.kA,
                    _currentFinanceParameters.kB,
                    _currentFinanceParameters.theta,
                    IVault(vault).v0()
                );
            }
        }

        super._afterRollEpoch();
    }

    /// @inheritdoc DVP
    function _allocateLiquidity(uint256 initialCapital) internal virtual override {
        Notional.Info storage liquidity = _liquidity[getEpoch().current];

        // The impermanent gain DVP only has one strike:
        liquidity.setup(currentStrike);

        // The initialCapital is split 50:50 on the two strategies:
        uint256 halfInitialCapital = initialCapital / 2;
        liquidity.setInitial(currentStrike, OptionStrategy.CALL, halfInitialCapital);
        liquidity.setInitial(currentStrike, OptionStrategy.PUT, initialCapital - halfInitialCapital);
    }

    /// @dev must be defined in Wad
    function setTradeVolatilityUtilizationRateFactor(uint256 utilizationRateFactor) external onlyOwner {
        // ToDo: make the change effective from the next epoch
        _tradeVolatilityUtilizationRateFactor = utilizationRateFactor;
    }

    /// @dev must be defined in Wad
    function setTradeVolatilityTimeDecay(uint256 timeDecay) external onlyOwner {
        // ToDo: make the change effective from the next epoch
        _tradeVolatilityTimeDecay = timeDecay;
    }
}
