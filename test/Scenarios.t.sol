// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {IG} from "../src/IG.sol";
import {TestnetPriceOracle} from "../src/testnet/TestnetPriceOracle.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {Utils} from "./utils/Utils.sol";

contract TestScenarios is Test {
    address internal _admin;
    address internal _liquidityProvider;
    address internal _trader;
    AddressProvider internal _ap;
    MockedVault internal _vault;
    MockedIG internal _dvp;
    TestnetPriceOracle internal _oracle;
    uint256 internal _toleranceOnPercentage;
    uint256 internal _toleranceOnAmount;

    struct StartEpochPreConditions {
        uint256 sideTokenPrice;
        uint256 impliedVolatility;
        uint256 riskFreeRate;
        uint256 tradeVolatilityUtilizationRateFactor;
        uint256 tradeVolatilityTimeDecay;
        uint256 sigmaMultiplier;
    }

    struct StartEpochPostConditions {
        uint256 baseTokenAmount;
        uint256 sideTokenAmount;
        uint256 strike;
        uint256 kA;
        uint256 kB;
        uint256 theta;
        int256 limInf;
        int256 limSup;
    }

    struct StartEpoch {
        StartEpochPreConditions pre;
        uint256 v0;
        StartEpochPostConditions post;
    }

    struct TradePreConditions {
        uint256 sideTokenPrice;
        uint256 volatility;
        uint256 riskFreeRate;
        uint256 baseTokenAmount;
        uint256 sideTokenAmount;
        uint256 utilizationRate;
        uint256 availableNotionalBear;
        uint256 availableNotionalBull;
    }

    struct TradePostConditions {
        uint256 marketValue; // premium/payoff
        uint256 volatility;
        uint256 baseTokenAmount;
        uint256 sideTokenAmount;
        uint256 utilizationRate;
        uint256 availableNotionalBear;
        uint256 availableNotionalBull;
    }

    struct Trade {
        TradePreConditions pre;
        bool isMint;
        uint256 amount; // notional minted/burned
        bool strategy;
        uint256 epochOfBurnedPosition;
        TradePostConditions post;
    }

    constructor() {
        _admin = address(0x1);
        _liquidityProvider = address(0x2);
        _trader = address(0x3);

        // NOTE: there is some precision loss somewhere...
        _toleranceOnPercentage = 1e14; // 0.0001 %
        _toleranceOnAmount = 1e11; // 0.0000001 (Wad)
    }

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.prank(_admin);
        _ap = new AddressProvider();

        _vault = MockedVault(VaultUtils.createVault(EpochFrequency.WEEKLY, _ap, _admin, vm));

        _oracle = TestnetPriceOracle(_ap.priceOracle());

        vm.startPrank(_admin);
        _dvp = new MockedIG(address(_vault), address(_ap));
        TestnetRegistry(_ap.registry()).registerDVP(address(_dvp));
        MockedVault(_vault).setAllowedDVP(address(_dvp));
        vm.stopPrank();

        _dvp.rollEpoch();
    }

    function testScenario1() public {
        // NOTE: values taken from the "Test" sheet of the "CL_Delta_Hedging_v2.xlsx" file
        // TBD: use position manager for easing the tests
        StartEpoch memory t0 = StartEpoch({
            pre: StartEpochPreConditions({
                sideTokenPrice: 1900e18, // 1'900
                impliedVolatility: 70e16, // 70%
                riskFreeRate: 3e16, // 3%
                tradeVolatilityUtilizationRateFactor: 2e18, // 2
                tradeVolatilityTimeDecay: 25e16, // 0.25
                sigmaMultiplier: 3e18 // 3
            }),
            v0: 100000e18, // 100'000
            post: StartEpochPostConditions({
                baseTokenAmount: 50000e18, // 50'000
                sideTokenAmount: 2631578947e10, // 26.31578947
                strike: 1900e18, // 1'900
                kA: 14205377328e11, // 1'420.5377328
                kB: 25412911721e11, // 2'541.2911721
                theta: 2706632e11, // 0.2706632
                limInf: -304345e9, // -0.000304345
                limSup: 263158e9 // 0.000263158
            })
        });
        _checkStartEpoch(t0);

        // TBD: find a way to better handle the elapsed time
        Utils.skipDay(false, vm); // 6 days to maturity

        Trade memory t1 = Trade({
            pre: TradePreConditions({
                sideTokenPrice: 2000e18, // 2'000
                volatility: 6750e14, // 67.50 %
                riskFreeRate: 3e16, // 3%
                baseTokenAmount: 50000e18, // 50'000
                sideTokenAmount: 2631578947e10, // 26.31578947
                utilizationRate: 0, // 0 %
                availableNotionalBear: 50000e18, // 50'000
                availableNotionalBull: 50000e18 // 50'000
            }),
            isMint: true,
            amount: 30000e18, // 30'000
            strategy: OptionStrategy.PUT, // Bear
            epochOfBurnedPosition: 0, // ignored
            post: TradePostConditions({
                marketValue: 738629e14, // 73.8629
                volatility: 693225e12, // 69.3225 %
                baseTokenAmount: 6190556e16, // 61'905.56
                sideTokenAmount: 2039994113e10, // 20.39994113
                utilizationRate: 3e17, // 30 %
                availableNotionalBear: 20000e18, // 20'000
                availableNotionalBull: 50000e18 // 50'000
            })
        });
        _checkTrade(t1);

        // ToDo: check burn market value after time (and maybe changed market conditions)

        // ToDo: check payoff after maturity
    }

    function _checkStartEpoch(StartEpoch memory t0) internal {
        VaultUtils.addVaultDeposit(_liquidityProvider, t0.v0, _admin, address(_vault), vm);

        vm.startPrank(_admin);
        _oracle.setTokenPrice(_vault.sideToken(), t0.pre.sideTokenPrice);
        _oracle.setImpliedVolatility(t0.pre.impliedVolatility);
        _oracle.setRiskFreeRate(t0.pre.riskFreeRate);

        _dvp.setTradeVolatilityUtilizationRateFactor(t0.pre.tradeVolatilityUtilizationRateFactor);
        _dvp.setTradeVolatilityTimeDecay(t0.pre.tradeVolatilityTimeDecay);
        _dvp.setSigmaMultiplier(t0.pre.sigmaMultiplier);
        vm.stopPrank();

        Utils.skipWeek(true, vm);
        _dvp.rollEpoch();

        (uint256 baseTokenAmount, uint256 sideTokenAmount) = _vault.balances();
        assertEq(t0.post.baseTokenAmount, baseTokenAmount); // TMP for math precision
        assertApproxEqAbs(t0.post.baseTokenAmount, baseTokenAmount, _toleranceOnAmount);
        assertApproxEqAbs(t0.post.sideTokenAmount, sideTokenAmount, _toleranceOnAmount);
        assertApproxEqAbs(t0.post.strike, _dvp.currentStrike(), _toleranceOnAmount);
        IG.FinanceParameters memory financeParams = _dvp.getCurrentFinanceParameters();
        assertApproxEqAbs(t0.post.kA, financeParams.kA, _toleranceOnAmount);
        assertApproxEqAbs(t0.post.kB, financeParams.kB, _toleranceOnAmount);
        assertApproxEqAbs(t0.post.theta, financeParams.theta, _toleranceOnAmount);
        assertApproxEqAbs(t0.post.limInf, financeParams.limInf, _toleranceOnAmount);
        assertApproxEqAbs(t0.post.limSup, financeParams.limSup, _toleranceOnAmount);
        // ToDo: add alphas
    }

    function _checkTrade(Trade memory t) internal {
        // pre-conditions:
        vm.startPrank(_admin);
        _oracle.setRiskFreeRate(t.pre.riskFreeRate);
        _oracle.setTokenPrice(_vault.sideToken(), t.pre.sideTokenPrice);
        vm.stopPrank();

        (uint256 baseTokenAmount, uint256 sideTokenAmount) = _vault.balances();
        assertApproxEqAbs(t.pre.baseTokenAmount, baseTokenAmount, _toleranceOnAmount);
        assertApproxEqAbs(t.pre.sideTokenAmount, sideTokenAmount, _toleranceOnAmount);

        assertEq(t.pre.utilizationRate, _dvp.getUtilizationRate());
        (, , uint256 availableBearNotional, uint256 availableBullNotional) = _dvp.notional();
        assertEq(t.pre.availableNotionalBear, availableBearNotional);
        assertEq(t.pre.availableNotionalBull, availableBullNotional);
        uint256 strike = _dvp.currentStrike();
        assertApproxEqAbs(t.pre.volatility, _dvp.getPostTradeVolatility(strike, 0), _toleranceOnPercentage);

        // actual trade:
        uint256 marketValue;
        if (t.isMint) {
            marketValue = _dvp.premium(strike, t.strategy, t.amount);
            TokenUtils.provideApprovedTokens(_admin, _vault.baseToken(), _trader, address(_dvp), marketValue, vm);
            vm.prank(_trader);
            marketValue = _dvp.mint(_trader, strike, t.strategy, t.amount);
            // TBD: check slippage on market value
        } else {
            vm.prank(_trader);
            marketValue = _dvp.burn(t.epochOfBurnedPosition, _trader, strike, t.strategy, t.amount);
        }

        // post-conditions:
        assertEq(t.post.marketValue, marketValue);
        assertEq(t.post.utilizationRate, _dvp.getUtilizationRate());
        (, , availableBearNotional, availableBullNotional) = _dvp.notional();
        assertEq(t.post.availableNotionalBear, availableBearNotional);
        assertEq(t.post.availableNotionalBull, availableBullNotional);
        assertApproxEqAbs(t.post.volatility, _dvp.getPostTradeVolatility(strike, 0), _toleranceOnPercentage);

        (baseTokenAmount, sideTokenAmount) = _vault.balances();
        assertApproxEqAbs(t.post.baseTokenAmount, baseTokenAmount, _toleranceOnAmount);
        assertApproxEqAbs(t.post.sideTokenAmount, sideTokenAmount, _toleranceOnAmount);
    }
}
