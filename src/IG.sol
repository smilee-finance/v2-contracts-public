// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IDVP} from "./interfaces/IDVP.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Amount, AmountHelper} from "./lib/Amount.sol";
import {DVPType} from "./lib/DVPType.sol";
import {Epoch, EpochController} from "./lib/EpochController.sol";
import {Finance} from "./lib/Finance.sol";
import {FinanceParameters, FinanceIG, TimeLockedFinanceValues} from "./lib/FinanceIG.sol";
import {Notional} from "./lib/Notional.sol";
import {DVP} from "./DVP.sol";
import {EpochControls} from "./EpochControls.sol";

contract IG is DVP {
    using AmountHelper for Amount;
    using EpochController for Epoch;
    using Notional for Notional.Info;

    FinanceParameters public financeParameters;

    // Used by TheGraph for frontend needs:
    event EpochStrike(uint256 epoch, uint256 strike);

    constructor(address vault_, address addressProvider_) DVP(vault_, DVPType.IG, addressProvider_) {
        _setParameters(
            TimeLockedFinanceValues({
                sigmaMultiplier: 3e18,
                tradeVolatilityUtilizationRateFactor: 2e18,
                tradeVolatilityTimeDecay: 0.25e18,
                volatilityPriceDiscountFactor: 0.9e18,
                useOracleImpliedVolatility: true
            })
        );
    }

    /// @notice Common strike price for all impermanent gain positions in this DVP, set at epoch start
    function currentStrike() external view returns (uint256 strike_) {
        strike_ = financeParameters.currentStrike;
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
        Amount memory amount_ = Amount({up: amountUp, down: amountDown});

        premium_ = _mint(recipient, financeParameters.currentStrike, amount_, expectedPremium, maxSlippage);
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
        Amount memory amount_ = Amount({up: amountUp, down: amountDown});

        paidPayoff = _burn(epoch, recipient, strike, amount_, expectedMarketValue, maxSlippage);
    }

    /// @inheritdoc IDVP
    function premium(
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) public view virtual override returns (uint256 premium_, uint256 fee) {
        strike;

        uint256 price = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
        Amount memory amount_ = Amount({up: amountUp, down: amountDown});

        premium_ = _getMarketValue(financeParameters.currentStrike, amount_, true, price);
        (fee, ) = IFeeManager(_getFeeManager()).tradeBuyFee(
            address(this),
            getEpoch().current,
            amountUp + amountDown,
            premium_,
            _baseTokenDecimals
        );
        premium_ += fee;
    }

    /// @inheritdoc IDVP
    function getUtilizationRate() public view returns (uint256) {
        Notional.Info storage liquidity = _liquidity[financeParameters.maturity];
        (uint256 used, uint256 total) = liquidity.utilizationRateFactors(financeParameters.currentStrike);

        return Finance.getUtilizationRate(used, total, _baseTokenDecimals);
    }

    /// @inheritdoc DVP
    function _getMarketValue(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy,
        uint256 swapPrice
    ) internal view virtual override returns (uint256 marketValue) {
        marketValue = FinanceIG.getMarketValue(
            financeParameters,
            amount,
            getPostTradeVolatility(strike, amount, tradeIsBuy),
            swapPrice,
            IMarketOracle(_getMarketOracle()).getRiskFreeRate(baseToken),
            _baseTokenDecimals
        );
    }

    function notional()
        external
        view
        returns (uint256 bearNotional, uint256 bullNotional, uint256 bearAvailNotional, uint256 bullAvailNotional)
    {
        Notional.Info storage liquidity = _liquidity[financeParameters.maturity];

        Amount memory initial = liquidity.getInitial(financeParameters.currentStrike);
        Amount memory available = liquidity.available(financeParameters.currentStrike);

        return (initial.down, initial.up, available.down, available.up);
    }

    // NOTE: public for frontend usage
    /**
        @notice Get the estimated implied volatility from a given trade.
        @param strike The trade strike.
        @param amount The trade notional.
        @param tradeIsBuy positive for buy, negative for sell.
        @return sigma The estimated implied volatility.
        @dev The oracle must provide an updated baseline volatility, computed just before the start of the epoch.
        @dev it reverts if there's no previous epoch
     */
    function getPostTradeVolatility(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy
    ) public view returns (uint256 sigma) {
        strike;

        Notional.Info storage liquidity = _liquidity[financeParameters.maturity];
        uint256 ur = liquidity.postTradeUtilizationRate(
            financeParameters.currentStrike,
            amount,
            tradeIsBuy,
            _baseTokenDecimals
        );
        uint256 t0 = getEpoch().previous;

        return FinanceIG.getPostTradeVolatility(financeParameters, ur, t0);
    }

    /// @inheritdoc DVP
    function _deltaHedgePosition(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy
    ) internal virtual override returns (uint256 swapPrice) {
        uint256 oraclePrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
        uint256 postTradeVol = getPostTradeVolatility(strike, amount, tradeIsBuy);

        Notional.Info storage liquidity = _liquidity[financeParameters.maturity];

        // Also update the epoch volatility with the postTradeVol:
        FinanceIG.updateAverageVolatility(financeParameters, amount, postTradeVol, _baseTokenDecimals);

        Amount memory availableLiquidity = liquidity.available(strike);
        (, uint256 sideTokensAmount) = IVault(vault).balances();

        int256 tokensToSwap = FinanceIG.getDeltaHedgeAmount(
            financeParameters,
            amount,
            tradeIsBuy,
            postTradeVol,
            oraclePrice,
            sideTokensAmount,
            availableLiquidity,
            _baseTokenDecimals,
            _sideTokenDecimals
        );

        if (tokensToSwap == 0) {
            return oraclePrice;
        }

        // NOTE: We negate the value because the protocol will sell side tokens when `h` is positive.
        uint256 exchangedBaseTokens = IVault(vault).deltaHedge(-tokensToSwap);

        // Compute swap price:
        swapPrice = Finance.getSwapPrice(tokensToSwap, exchangedBaseTokens, _sideTokenDecimals, _baseTokenDecimals);
    }

    /// @inheritdoc DVP
    function _residualPayoffPerc(
        uint256 strike,
        uint256 price
    ) internal view virtual override returns (uint256, uint256) {
        strike;
        return FinanceIG.getPayoffPercentages(financeParameters, price);
    }

    /// @inheritdoc DVP
    function _residualPayoff() internal view virtual override returns (uint256 residualPayoff) {
        Notional.Info storage liquidity = _liquidity[financeParameters.maturity];

        residualPayoff = liquidity.getAccountedPayoff(financeParameters.currentStrike).getTotal();
    }

    /// @inheritdoc DVP
    function _accountResidualPayoffs(uint256 price) internal virtual override {
        _accountResidualPayoff(financeParameters.currentStrike, price);
    }

    function _beforeRollEpoch() internal virtual override {
        bool noLockedLiquidity = IVault(vault).v0() == 0;

        super._beforeRollEpoch();

        // happens when rolling first time, no need to adjust payoff
        if (noLockedLiquidity) {
            return;
        }

        uint256 nextStrike;
        {
            (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
            uint256 oraclePrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
            nextStrike = FinanceIG.getStrike(
                oraclePrice,
                baseTokenAmount,
                sideTokenAmount,
                _baseTokenDecimals,
                _sideTokenDecimals
            );
        }

        {
            // Need to get residual payoff of the previous strike (because strike has already been updated)
            Notional.Info storage liquidity = _liquidity[financeParameters.maturity];
            _accountResidualPayoff(financeParameters.currentStrike, nextStrike);
            uint256 residualPayoff = liquidity.getAccountedPayoff(financeParameters.currentStrike).getTotal();
            IVault(vault).adjustReservedPayoff(residualPayoff);
        }
    }

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        Epoch memory epoch = getEpoch();

        financeParameters.maturity = epoch.current;

        {
            // Update strike price:
            (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
            uint256 oraclePrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
            FinanceIG.updateStrike(
                financeParameters,
                oraclePrice,
                baseTokenAmount,
                sideTokenAmount,
                _baseTokenDecimals,
                _sideTokenDecimals
            );
        }
        emit EpochStrike(epoch.current, financeParameters.currentStrike);

        {
            uint256 iv = IMarketOracle(_getMarketOracle()).getImpliedVolatility(
                baseToken,
                sideToken,
                financeParameters.currentStrike,
                epoch.frequency
            );
            uint256 v0 = IVault(vault).v0();
            FinanceIG.updateParameters(financeParameters, iv, v0);
        }

        super._afterRollEpoch();

        // NOTE: initial liquidity is allocated by the DVP call
        Notional.Info storage liquidity = _liquidity[financeParameters.maturity];
        financeParameters.initialLiquidity = liquidity.getInitial(financeParameters.currentStrike);
    }

    /// @inheritdoc DVP
    function _allocateLiquidity(uint256 initialCapital) internal virtual override {
        // The initialCapital is split 50:50 on the two strategies:
        uint256 halfInitialCapital = initialCapital / 2;
        Amount memory allocation = Amount({up: halfInitialCapital, down: initialCapital - halfInitialCapital});

        Notional.Info storage liquidity = _liquidity[financeParameters.maturity];

        // The impermanent gain (IG) DVP only has one strike:
        liquidity.setInitial(financeParameters.currentStrike, allocation);
    }

    /// @dev parameters must be defined in Wad
    /// @dev aggregated in order to limit contract size
    function setParameters(TimeLockedFinanceValues calldata params) external {
        _checkRole(ROLE_ADMIN);
        _setParameters(params);
    }

    /// @dev parameters must be defined in Wad
    /// @dev aggregated in order to limit contract size
    function _setParameters(TimeLockedFinanceValues memory params) internal {
        uint256 timeToValidity = getEpoch().timeToNextEpoch();
        FinanceIG.updateTimeLockedParameters(financeParameters.timeLocked, params, timeToValidity);
    }
}
