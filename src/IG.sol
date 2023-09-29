// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IDVP} from "./interfaces/IDVP.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Amount, AmountHelper} from "./lib/Amount.sol";
import {DVPType} from "./lib/DVPType.sol";
import {Epoch} from "./lib/EpochController.sol";
import {Finance} from "./lib/Finance.sol";
import {FinanceParameters, FinanceIG} from "./lib/FinanceIG.sol";
import {Notional} from "./lib/Notional.sol";
import {DVP} from "./DVP.sol";
import {EpochControls} from "./EpochControls.sol";

contract IG is DVP {
    using AmountHelper for Amount;
    using Notional for Notional.Info;

    FinanceParameters internal _financeParameters;

    error OutOfAllowedRange();

    constructor(address vault_, address addressProvider_) DVP(vault_, DVPType.IG, addressProvider_) {
        _financeParameters.sigmaMultiplier = 3e18; // ToDo: let the deployer provide it
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

        uint256 price = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
        Amount memory amount_ = Amount({up: amountUp, down: amountDown});

        premium_ = _getMarketValue(_financeParameters.currentStrike, amount_, true, price);
        fee = IFeeManager(_getFeeManager()).tradeFee(amountUp + amountDown, premium_, _baseTokenDecimals, false);
        premium_ += fee;
    }

    /// @inheritdoc IDVP
    function getUtilizationRate() public view returns (uint256) {
        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];
        (uint256 used, uint256 total) = liquidity.utilizationRateFactors(_financeParameters.currentStrike);

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
            _financeParameters,
            amount,
            getPostTradeVolatility(strike, amount, tradeIsBuy),
            swapPrice,
            IMarketOracle(_getMarketOracle()).getRiskFreeRate(sideToken, baseToken),
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

        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];
        uint256 ur = liquidity.postTradeUtilizationRate(
            _financeParameters.currentStrike,
            amount,
            tradeIsBuy,
            _baseTokenDecimals
        );
        uint256 t0 = getEpoch().previous;

        return FinanceIG.getPostTradeVolatility(_financeParameters, ur, t0);
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

        // Compute swap price:
        swapPrice = Finance.getSwapPrice(tokensToSwap, exchangedBaseTokens, _sideTokenDecimals, _baseTokenDecimals);
    }

    /// @inheritdoc DVP
    function _residualPayoffPerc(
        uint256 strike,
        uint256 price
    ) internal view virtual override returns (uint256, uint256) {
        strike;
        return FinanceIG.getPayoffPercentages(_financeParameters, price);
    }

    /// @inheritdoc DVP
    function _residualPayoff() internal view virtual override returns (uint256 residualPayoff) {
        Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];

        residualPayoff = liquidity.getAccountedPayoff(_financeParameters.currentStrike).getTotal();
    }

    /// @inheritdoc DVP
    function _accountResidualPayoffs(uint256 price) internal virtual override {
        _accountResidualPayoff(_financeParameters.currentStrike, price);
    }

    function _beforeRollEpoch() internal virtual override {
        super._beforeRollEpoch();
        uint256 previousStrike = _financeParameters.currentStrike;
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
            // Need to get residual payoff of the previous strike (because strike has already been updated)
            Notional.Info storage liquidity = _liquidity[_financeParameters.maturity];
            uint256 residualPayoff = liquidity.getAccountedPayoff(previousStrike).getTotal();
            _accountResidualPayoff(previousStrike, _financeParameters.currentStrike);
            IVault(vault).adjustReservedPayoff(residualPayoff);
        }
    }

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        Epoch memory epoch = getEpoch();
        // TBD: check if vault is dead

        _financeParameters.maturity = epoch.current;

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
    function setSigmaMultiplier(uint256 value) external {
        _checkRole(ROLE_ADMIN);
        // ToDo: make the change effective after a given amount of time
        _financeParameters.sigmaMultiplier = value;
    }

    /// @dev must be defined in Wad
    function setTradeVolatilityUtilizationRateFactor(uint256 value) external {
        _checkRole(ROLE_ADMIN);
        // ToDo: make the change effective after a given amount of time
        if (value < 1e18 || value > 5e18) {
            revert OutOfAllowedRange();
        }

        _financeParameters.tradeVolatilityUtilizationRateFactor = value;
    }

    /// @dev must be defined in Wad
    function setTradeVolatilityTimeDecay(uint256 value) external {
        _checkRole(ROLE_ADMIN);
        // ToDo: make the change effective after a given amount of time
        if (value > 0.5e18) {
            revert OutOfAllowedRange();
        }

        _financeParameters.tradeVolatilityTimeDecay = value;
    }
}
