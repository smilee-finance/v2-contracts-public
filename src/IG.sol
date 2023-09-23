// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVP} from "./interfaces/IDVP.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Amount, AmountHelper} from "./lib/Amount.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";
import {DVPType} from "./lib/DVPType.sol";
import {Epoch, EpochController} from "./lib/EpochController.sol";
import {FinanceParameters, FinanceIG} from "./lib/FinanceIG.sol";
import {Notional} from "./lib/Notional.sol";
import {SignedMath} from "./lib/SignedMath.sol";
import {DVP} from "./DVP.sol";
import {EpochControls} from "./EpochControls.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

contract IG is DVP {
    using AmountHelper for Amount;
    using AmountsMath for uint256;
    using Notional for Notional.Info;
    using EpochController for Epoch;

    FinanceParameters internal _financeParameters;

    constructor(address vault_, address addressProvider_) DVP(vault_, DVPType.IG, addressProvider_) {
        _financeParameters.sigmaMultiplier = 2e18;
        _financeParameters.tradeVolatilityUtilizationRateFactor = 2e18;
        _financeParameters.tradeVolatilityTimeDecay = 0.25e18;
    }

    /// @notice Common strike price for all impermanent gain positions in this DVP, set at epoch start
    function currentStrike() external view returns (uint256 strike_) {
        strike_ = _financeParameters.currentStrike;
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

        premium_ = _mint(recipient, _financeParameters.currentStrike, amount_, expectedPremium, maxSlippage);
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
        _checkEpochInitialized();

        uint256 swapPrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
        Amount memory amount_ = Amount({up: amountUp, down: amountDown});

        premium_ = _getMarketValue(_financeParameters.currentStrike, amount_, true, swapPrice);
        fee = IFeeManager(_getFeeManager()).calculateTradeFee(
            amountUp + amountDown,
            premium_,
            _baseTokenDecimals,
            false
        );
        premium_ += fee;
    }

    /// @inheritdoc DVP
    function _getMarketValue(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy,
        uint256 swapPrice
    ) internal view virtual override returns (uint256 marketValue) {
        uint256 postTradeVolatility = getPostTradeVolatility(strike, amount, tradeIsBuy);
        uint256 riskFreeRate = IMarketOracle(_getMarketOracle()).getRiskFreeRate(sideToken, baseToken);

        marketValue = FinanceIG.getMarketValue(
            _financeParameters,
            amount,
            postTradeVolatility,
            swapPrice,
            riskFreeRate,
            _baseTokenDecimals
        );
    }

    function notional()
        public
        view
        returns (uint256 bearNotional, uint256 bullNotional, uint256 bearAvailNotional, uint256 bullAvailNotional)
    {
        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];

        Amount memory initial = liquidity.getInitial(_financeParameters.currentStrike);
        Amount memory available = liquidity.available(_financeParameters.currentStrike);

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
        _checkEpochInitialized();

        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];
        uint256 U = liquidity.postTradeUtilizationRate(
            _financeParameters.currentStrike,
            amount,
            tradeIsBuy,
            _baseTokenDecimals
        );
        uint256 t0 = getEpoch().previous;

        return FinanceIG.getPostTradeVolatility(_financeParameters, U, t0);
    }

    // TBD: wrap parameters in a "Trade" struct (there's an overlap with Position.Info)
    // ---- amount, isBuy, decimals, strike
    /// @inheritdoc DVP
    function _deltaHedgePosition(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy
    ) internal virtual override returns (uint256 swapPrice) {
        uint256 oraclePrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);

        uint256 postTradeVol = getPostTradeVolatility(strike, amount, tradeIsBuy);
        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];
        Amount memory availableLiquidity = liquidity.available(strike);
        (, uint256 sideTokensAmount) = IVault(vault).balances();

        int256 tokensToSwap = FinanceIG.getDeltaHedgeAmount(
            _financeParameters,
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

        // TBD: move in library
        // Compute swap price:
        exchangedBaseTokens = AmountsMath.wrapDecimals(exchangedBaseTokens, _baseTokenDecimals);
        swapPrice = exchangedBaseTokens.wdiv(
            AmountsMath.wrapDecimals(SignedMath.abs(tokensToSwap), _sideTokenDecimals)
        );
    }

    /// @inheritdoc DVP
    function _residualPayoffPerc(uint256 strike) internal view virtual override returns (uint256, uint256) {
        strike;
        uint256 oraclePrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
        return FinanceIG.getPayoffPercentages(_financeParameters, oraclePrice);
    }

    /// @inheritdoc DVP
    function _residualPayoff() internal view virtual override returns (uint256 residualPayoff) {
        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];
        Amount memory payoff = liquidity.getAccountedPayoff(_financeParameters.currentStrike);

        residualPayoff = payoff.getTotal();
    }

    /// @inheritdoc DVP
    function _accountResidualPayoffs() internal virtual override {
        _accountResidualPayoff(_financeParameters.currentStrike);
    }

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        Epoch memory epoch = getEpoch();
        // ToDo: add test where we roll epochs without deposit in the vault
        // ToDo: check if vault is dead

        _financeParameters.maturity = epoch.current;

        {
            // Update strike price:
            (uint256 baseTokenAmount, uint256 sideTokenAmount) = IVault(vault).balances();
            uint256 oraclePrice = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
            FinanceIG.updateStrike(
                _financeParameters,
                oraclePrice,
                baseTokenAmount,
                sideTokenAmount,
                _baseTokenDecimals,
                _sideTokenDecimals
            );
        }

        {
            // TBD: if there's no liquidity, we may avoid those computations
            uint256 iv = IMarketOracle(_getMarketOracle()).getImpliedVolatility(
                baseToken,
                sideToken,
                _financeParameters.currentStrike,
                epoch.frequency
            );
            uint256 v0 = IVault(vault).v0();
            FinanceIG.updateParameters(_financeParameters, iv, v0, epoch.previous);
        }

        super._afterRollEpoch();

        // NOTE: initial liquidity is allocated by the DVP call
        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];
        _financeParameters.initialLiquidity = liquidity.getInitial(_financeParameters.currentStrike);
    }

    /// @inheritdoc DVP
    function _allocateLiquidity(uint256 initialCapital) internal virtual override {
        // The initialCapital is split 50:50 on the two strategies:
        uint256 halfInitialCapital = initialCapital / 2;
        Amount memory allocation = Amount({up: halfInitialCapital, down: initialCapital - halfInitialCapital});

        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];

        // The impermanent gain (IG) DVP only has one strike:
        liquidity.setInitial(_financeParameters.currentStrike, allocation);
    }

    /// @dev must be defined in Wad
    function setTradeVolatilityUtilizationRateFactor(uint256 utilizationRateFactor) external onlyOwner {
        // ToDo: make the change effective from the next epoch
        _financeParameters.tradeVolatilityUtilizationRateFactor = utilizationRateFactor;
    }

    /// @dev must be defined in Wad
    function setTradeVolatilityTimeDecay(uint256 timeDecay) external onlyOwner {
        // ToDo: make the change effective from the next epoch
        _financeParameters.tradeVolatilityTimeDecay = timeDecay;
    }
}
