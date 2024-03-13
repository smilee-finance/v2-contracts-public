// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IPositionManager} from "@project/interfaces/IPositionManager.sol";
import {Amount, AmountHelper} from "@project/lib/Amount.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {FinanceParameters} from "@project/lib/FinanceIG.sol";
import {SignedMath} from "@project/lib/SignedMath.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {PositionManager} from "@project/periphery/PositionManager.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {Utils} from "./utils/Utils.sol";

contract TestScenariosJson is Test {
    using AmountHelper for Amount;

    address internal _admin;
    address internal _liquidityProvider;
    address internal _trader;
    AddressProvider internal _ap;
    FeeManager internal _feeManager;
    MockedVault internal _vault;
    MockedIG internal _dvp;
    TestnetPriceOracle internal _oracle;
    TestnetSwapAdapter internal _exchange;
    MarketOracle internal _marketOracle;
    PositionManager internal _pm;
    uint256 internal _toleranceOnPercentage;
    uint256 internal _tolerancePercentage;

    struct JsonPathType {
        string path;
        string varType;
    }

    // NOTE: fields must be in lexicographical order for parsing the JSON file
    struct StartEpochPreConditions {
        uint256 sideTokenPrice;
        uint256 impliedVolatility;
        uint256 riskFreeRate;
        uint256 tradeVolatilityUtilizationRateFactor;
        uint256 tradeVolatilityTimeDecay;
        uint256 sigmaMultiplier;
        uint256 capFee;
        uint256 capFeeMaturity;
        uint256 fee;
        uint256 feeMaturity;
        uint256 minFeeBeforeTimeThreshold;
        uint256 minFeeAfterTimeThreshold;
        uint256 exchangeSlippage;
        uint256 exchangeFeeTier;
        uint256 successFee;
    }

    struct StartEpochPostConditions {
        uint256 baseTokenAmount;
        uint256 sideTokenAmount;
        uint256 impliedVolatility;
        uint256 strike;
        uint256 kA;
        uint256 kB;
        uint256 theta;
    }

    struct StartEpoch {
        StartEpochPreConditions pre;
        uint256 deposit;
        uint256 duration;
        StartEpochPostConditions post;
    }

    struct TradePreConditions {
        uint256 availableNotionalBear;
        uint256 availableNotionalBull;
        uint256 baseTokenAmount;
        uint256 riskFreeRate;
        uint256 sideTokenAmount;
        uint256 sideTokenPrice;
        uint256 utilizationRate;
        uint256 volatility;
    }

    struct TradePostConditions {
        uint256 acceptedPremiumSlippage;
        uint256 availableNotionalBear;
        uint256 availableNotionalBull;
        uint256 baseTokenAmount;
        uint256 marketValue; // premium/payoff
        uint256 sideTokenAmount;
        uint256 utilizationRate;
        uint256 volatility;
    }

    struct Trade {
        uint256 amountDown; // notional minted/burned
        uint256 amountUp; // notional minted/burned
        uint256 elapsedTimeSeconds;
        uint256 epochOfBurnedPosition;
        bool isMint;
        TradePostConditions post;
        TradePreConditions pre;
        uint256 tokenID;
    }

    struct EndEpoch {
        uint256 baseTokenAmount;
        uint256 depositAmount;
        uint256 impliedVolatility;
        uint256 payoffBear;
        uint256 payoffBull;
        uint256 payoffNet;
        uint256 payoffTotal;
        uint256 sideTokenAmount;
        uint256 sideTokenPrice;
        uint256 v0;
        uint256 withdrawSharesAmount;
    }

    constructor() {
        _admin = address(0x1);
        _liquidityProvider = address(0x2);
        _trader = address(0x3);

        // NOTE: there is some precision loss somewhere...
        _toleranceOnPercentage = 0.001e18; // 0.1 %
        _tolerancePercentage = 0.0025e18; // 0.25%
    }

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.startPrank(_admin);
        _ap = new AddressProvider(0);
        _ap.grantRole(_ap.ROLE_ADMIN(), _admin);

        _pm = new PositionManager(address(_ap));
        _pm.grantRole(_pm.ROLE_ADMIN(), _admin);
        _ap.setDvpPositionManager(address(_pm));
        vm.stopPrank();
    }

    function _marketSetup(uint256 duration) internal {
        uint256 f = duration / 1e18 == 7
            ? EpochFrequency.WEEKLY
            : duration / 1e18 == 1
                ? EpochFrequency.DAILY
                : EpochFrequency.FOUR_WEEKS;

        // also creates exchange
        _vault = MockedVault(VaultUtils.createVault(f, _ap, _admin, vm));

        vm.startPrank(_admin);
        _vault.grantRole(_vault.ROLE_ADMIN(), _admin);
        _vault.setMaxDeposit(1_000_000_000 * 1e18);
        vm.stopPrank();

        _exchange = TestnetSwapAdapter(_ap.exchangeAdapter());
        _oracle = TestnetPriceOracle(_ap.priceOracle());
        _marketOracle = MarketOracle(_ap.marketOracle());
        _feeManager = FeeManager(_ap.feeManager());

        vm.startPrank(_admin);
        _dvp = new MockedIG(address(_vault), address(_ap));
        _dvp.grantRole(_dvp.ROLE_ADMIN(), _admin);
        _dvp.grantRole(_dvp.ROLE_EPOCH_ROLLER(), _admin);
        _vault.grantRole(_vault.ROLE_ADMIN(), _admin);

        _marketOracle.setDelay(_dvp.baseToken(), _dvp.sideToken(), _dvp.getEpoch().frequency, 0, true);

        MockedRegistry(_ap.registry()).registerDVP(address(_dvp));
        MockedVault(_vault).setAllowedDVP(address(_dvp));

        vm.stopPrank();
    }

    // One single Mint of a Bull option at the strike price.
    function testScenario1() public { _checkScenario("scenario_1", true); }

    // One Mint for each Bull and Bear option at the strike price.
    function testScenario2() public { _checkScenario("scenario_2", true); }

    // Buy and sell single options with little price deviation from the strike price.
    function testScenario3() public { _checkScenario("scenario_3", true); }

    // Buy and sell both Bull and Bear options (in the same trade) with little price deviation from the strike price.
    function testScenario4() public { _checkScenario("scenario_4", true); }

    // Buy and sell all the available notional (single and both Bull and Bear options trade) with huge price deviation from the strike price.
    function testScenario5() public { _checkScenario("scenario_5", true); }

    // Buy and sell all the available notional (both Bull and Bear options trade) with huge price deviation from the strike price.
    function testScenario6() public { _checkScenario("scenario_6", true); }

    // Buy Both options little by little, with an ever-increasing price over time, selling everything 1 day before maturity.
    function testScenario7() public { _checkScenario("scenario_7", true); }

    // Buy a Both option immediately, with an ever-decreasing price over time, selling little by little until maturity.
    function testScenario8() public { _checkScenario("scenario_8", true); }

    // Controls the behavior of all components over multiple epochs
    function testScenarioMultiEpoch01() public { _checkScenario("scenario_multi_1_e1", true); _checkScenario("scenario_multi_1_e2", false); }
    function testScenarioMultiEpoch02() public { _checkScenario("scenario_multi_2_e1", true); _checkScenario("scenario_multi_2_e2", false); }
    function testScenarioMultiEpoch03() public { _checkScenario("scenario_multi_3_e1", true); _checkScenario("scenario_multi_3_e2", false); }
    function testScenarioMultiEpoch04() public { _checkScenario("scenario_multi_4_e1", true); _checkScenario("scenario_multi_4_e2", false); }
    function testScenarioMultiEpoch05() public { _checkScenario("scenario_multi_5_e1", true); _checkScenario("scenario_multi_5_e2", false); }
    function testScenarioMultiEpoch06() public { _checkScenario("scenario_multi_6_e1", true); _checkScenario("scenario_multi_6_e2", false); }
    function testScenarioMultiEpoch07() public { _checkScenario("scenario_multi_7_e1", true); _checkScenario("scenario_multi_7_e2", false); }
    function testScenarioMultiEpoch08() public { _checkScenario("scenario_multi_8_e1", true); _checkScenario("scenario_multi_8_e2", false); }
    function testScenarioMultiEpoch09() public { _checkScenario("scenario_multi_9_e1", true); _checkScenario("scenario_multi_9_e2", false); }
    function testScenarioMultiEpoch10() public { _checkScenario("scenario_multi_10_e1", true); _checkScenario("scenario_multi_10_e2", false); }
    function testScenarioMultiEpoch11() public { _checkScenario("scenario_multi_11_e1", true); _checkScenario("scenario_multi_11_e2", false); }
    function testScenarioMultiEpoch12() public { _checkScenario("scenario_multi_12_e1", true); _checkScenario("scenario_multi_12_e2", false); }
    function testScenarioMultiEpoch13() public { _checkScenario("scenario_multi_13_e1", true); _checkScenario("scenario_multi_13_e2", false); }
    function testScenarioMultiEpoch14() public { _checkScenario("scenario_multi_14_e1", true); _checkScenario("scenario_multi_14_e2", false); }
    function testScenarioMultiEpoch15() public { _checkScenario("scenario_multi_15_e1", true); _checkScenario("scenario_multi_15_e2", false); }

    // function testScenarioLowKAHighVolatility() public {
    //     _checkScenario("scenario_low_ka_high_volatility", true);
    // }

    // function testScenarioKAZeroExtremeVolatility() public {
    //     _checkScenario("scenario_ka_zero_extreme_volatility", true);
    // }

    function testScenarioSlippage01() public { _checkScenario("slip_001_01", true); }
    function testScenarioSlippage02() public { _checkScenario("slip_001_02", true); }
    function testScenarioSlippage03() public { _checkScenario("slip_001_03", true); }
    function testScenarioSlippage04() public { _checkScenario("slip_001_04", true); }
    function testScenarioSlippage05() public { _checkScenario("slip_001_05", true); }
    function testScenarioSlippage06() public { _checkScenario("slip_001_06", true); }
    function testScenarioSlippage07() public { _checkScenario("slip_001_07", true); }
    function testScenarioSlippage09() public { _checkScenario("slip_001_09", true); }
    function testScenarioSlippage10() public { _checkScenario("slip_001_10", true); }
    function testScenarioSlippage11() public { _checkScenario("slip_001_11", true); }

    // kA -> 0, IG goes paused, cannot trade
    function testFailScenarioSlippage08() public { _checkScenario("slip_001_08", true); }

    function _checkScenario(string memory scenarioName, bool isFirstEpoch) internal {
        console.log(string.concat("Executing scenario: ", scenarioName));
        string memory scenariosJSON = _getTestsFromJson(scenarioName);


        console.log("- Checking start epoch");
        StartEpoch memory startEpoch = _getStartEpochFromJson(scenariosJSON);

        if (isFirstEpoch) {
            _marketSetup(startEpoch.duration);
        }

        _checkStartEpoch(startEpoch, isFirstEpoch);

        Trade[] memory trades = _getTradesFromJson(scenariosJSON);
        for (uint i = 0; i < trades.length; i++) {
            console.log("- Checking trade number", i + 1);
            _checkTrade(trades[i]);
        }

        console.log("- Checking end epoch");
        _checkEndEpoch(scenariosJSON);
    }

    function _checkStartEpoch(StartEpoch memory t0, bool isFirstEpoch) internal {
        vm.startPrank(_admin);
        _oracle.setTokenPrice(_vault.sideToken(), t0.pre.sideTokenPrice);
        _exchange.setSlippage(int256(t0.pre.exchangeSlippage + t0.pre.exchangeFeeTier), 0, 0);

        _marketOracle.setImpliedVolatility(
            _dvp.baseToken(),
            _dvp.sideToken(),
            _dvp.getEpoch().frequency,
            t0.pre.impliedVolatility
        );
        _marketOracle.setRiskFreeRate(_dvp.baseToken(), t0.pre.riskFreeRate);

        FeeManager.FeeParams memory params = FeeManager.FeeParams({
            timeToExpiryThreshold: 3600,
            minFeeBeforeTimeThreshold: t0.pre.minFeeBeforeTimeThreshold,
            minFeeAfterTimeThreshold: t0.pre.minFeeAfterTimeThreshold,
            successFeeTier: t0.pre.successFee,
            feePercentage: t0.pre.fee,
            capPercentage: t0.pre.capFee,
            maturityFeePercentage: t0.pre.feeMaturity,
            maturityCapPercentage: t0.pre.capFeeMaturity
        });
        _feeManager.setDVPFee(address(_dvp), params);

        _dvp.setTradeVolatilityUtilizationRateFactor(t0.pre.tradeVolatilityUtilizationRateFactor);
        _dvp.setTradeVolatilityTimeDecay(t0.pre.tradeVolatilityTimeDecay);
        _dvp.setSigmaMultiplier(t0.pre.sigmaMultiplier);
        _dvp.setUseOracleImpliedVolatility(false);
        vm.stopPrank();

        if (isFirstEpoch) {
            VaultUtils.addVaultDeposit(_liquidityProvider, t0.deposit, _admin, address(_vault), vm);
            Utils.skipWeek(true, vm);
            vm.prank(_admin);
            _dvp.rollEpoch();
        }

        (, , , , , , , uint256 sigmaZero, ) = _dvp.financeParameters();
        assertApproxEqAbs(t0.post.impliedVolatility, sigmaZero, _tolerance(t0.post.impliedVolatility));

        (uint256 baseTokenAmount, uint256 sideTokenAmount) = _vault.balances();

        // assertEq(t0.post.baseTokenAmount, baseTokenAmount); // TMP for math precision
        assertApproxEqAbs(t0.post.baseTokenAmount, baseTokenAmount, _tolerance(t0.post.baseTokenAmount));
        assertApproxEqAbs(t0.post.sideTokenAmount, sideTokenAmount, _tolerance(t0.post.sideTokenAmount));
        assertApproxEqAbs(t0.post.strike, _dvp.currentStrike(), _tolerance(t0.post.strike));
        FinanceParameters memory financeParams = _dvp.getCurrentFinanceParameters();
        assertApproxEqAbs(t0.post.kA, financeParams.kA, _tolerance(t0.post.kA));
        assertApproxEqAbs(t0.post.kB, financeParams.kB, _tolerance(t0.post.kB));
        assertApproxEqAbs(t0.post.theta, financeParams.theta, _tolerance(t0.post.theta));
    }

    function _checkTrade(Trade memory t) internal {
        // pre-conditions:
        vm.warp(block.timestamp + t.elapsedTimeSeconds);
        vm.startPrank(_admin);
        _marketOracle.setRiskFreeRate(_vault.baseToken(), t.pre.riskFreeRate);
        _oracle.setTokenPrice(_vault.sideToken(), t.pre.sideTokenPrice);
        vm.stopPrank();

        (uint256 baseTokenAmount, uint256 sideTokenAmount) = _vault.balances();
        assertApproxEqAbs(t.pre.baseTokenAmount, baseTokenAmount, _tolerance(t.pre.baseTokenAmount));
        assertApproxEqAbs(t.pre.sideTokenAmount, sideTokenAmount, _tolerance(t.pre.sideTokenAmount));

        assertApproxEqAbs(t.pre.utilizationRate, _dvp.getUtilizationRate(), _toleranceOnPercentage);
        (, , uint256 availableBearNotional, uint256 availableBullNotional) = _dvp.notional();

        assertApproxEqAbs(t.pre.availableNotionalBear, availableBearNotional, _tolerance(t.pre.availableNotionalBear));
        assertApproxEqAbs(t.pre.availableNotionalBull, availableBullNotional, _tolerance(t.pre.availableNotionalBull));
        uint256 strike = _dvp.currentStrike();

        {
            (uint256 sigma, /* uint256 ur */) = _dvp.getPostTradeVolatility(strike, Amount({up: 0, down: 0}), true);
            assertApproxEqAbs(
                t.pre.volatility,
                sigma,
                _toleranceOnPercentage
            );
        }

        // actual trade:
        uint256 marketValue;
        uint256 fee;
        if (t.isMint) {
            (marketValue, fee) = _dvp.premium(strike, t.amountUp, t.amountDown);
            TokenUtils.provideApprovedTokens(
                _admin,
                _vault.baseToken(),
                _trader,
                address(_pm),
                ((marketValue * (1e18 + t.post.acceptedPremiumSlippage)) / 1e18) + fee,
                vm
            );

            {
                IPositionManager.MintParams memory params = IPositionManager.MintParams({
                    tokenId: t.tokenID,
                    dvpAddr: address(_dvp),
                    notionalUp: t.amountUp,
                    notionalDown: t.amountDown,
                    strike: strike,
                    recipient: _trader,
                    expectedPremium: marketValue,
                    maxSlippage: t.post.acceptedPremiumSlippage,
                    nftAccessTokenId: 0
                });
                vm.prank(_trader);
                (/*uint256 tokenId*/, marketValue) = _pm.mint(params);
            }
            vm.prank(_trader);
            // TBD: check slippage on market value
        } else {
            vm.startPrank(_trader);
            (marketValue, fee) = _pm.payoff(t.tokenID, t.amountUp, t.amountDown);
            {
                IPositionManager.SellParams memory params = IPositionManager.SellParams({
                    tokenId: t.tokenID,
                    notionalUp: t.amountUp,
                    notionalDown: t.amountDown,
                    expectedMarketValue: marketValue,
                    maxSlippage: t.post.acceptedPremiumSlippage
                });
                marketValue = _pm.sell(params);
            }
            vm.stopPrank();
        }
        //fee = _feeManager.calculateTradeFee(t.amountUp + t.amountDown, marketValue, IToken(_vault.baseToken()).decimals(), false);

        //post-conditions:
        assertApproxEqAbs(t.post.marketValue, marketValue, _tolerance(t.post.marketValue));
        assertApproxEqAbs(t.post.utilizationRate, _dvp.getUtilizationRate(), _toleranceOnPercentage);
        (, , availableBearNotional, availableBullNotional) = _dvp.notional();
        assertApproxEqAbs(
            t.post.availableNotionalBear,
            availableBearNotional,
            _tolerance(t.post.availableNotionalBear)
        );
        assertApproxEqAbs(
            t.post.availableNotionalBull,
            availableBullNotional,
            _tolerance(t.post.availableNotionalBull)
        );

        {
            (uint256 sigma, /* uint256 ur */) = _dvp.getPostTradeVolatility(strike, Amount({up: 0, down: 0}), true);
            assertApproxEqAbs(
                t.post.volatility,
                sigma,
                _toleranceOnPercentage
            );
        }

        (baseTokenAmount, sideTokenAmount) = _vault.balances();
        assertApproxEqAbs(t.post.baseTokenAmount, baseTokenAmount, _tolerance(t.post.baseTokenAmount));
        assertApproxEqAbs(t.post.sideTokenAmount, sideTokenAmount, _tolerance(t.post.sideTokenAmount));
    }

    function _checkEndEpoch(string memory json) private {
        EndEpoch memory endEpoch = _getEndEpochFromJson(json);

        if (endEpoch.withdrawSharesAmount > 0) {
            vm.prank(_liquidityProvider);
            (uint256 heldByAccount, uint256 heldByVault) = _vault.shareBalances(_liquidityProvider);
            assertGe(heldByAccount + heldByVault, endEpoch.withdrawSharesAmount);
            (, uint256 sharesToWithdraw) = _vault.withdrawals(_liquidityProvider);
            if (sharesToWithdraw > 0) {
                vm.prank(_liquidityProvider);
                _vault.completeWithdraw();
            }

            vm.prank(_liquidityProvider);
            _vault.initiateWithdraw(endEpoch.withdrawSharesAmount);
        }

        // TBD: add asserts for pre-conditions (e.g. vault balances)

        if (endEpoch.depositAmount > 0) {
            VaultUtils.addVaultDeposit(_liquidityProvider, endEpoch.depositAmount, _admin, address(_vault), vm);
        }

        vm.startPrank(_admin);
        _oracle.setTokenPrice(_vault.sideToken(), endEpoch.sideTokenPrice);
        vm.warp(_dvp.currentEpoch() + 1);
        _dvp.rollEpoch();
        vm.stopPrank();

        (, , , , , , , uint256 sigmaZero, ) = _dvp.financeParameters();
        // NOTE: the value of sigmaZero must be divided by rho (0.9) in order to be checked
        sigmaZero = (sigmaZero * 10 ** 18) / 0.9e18;
        assertApproxEqAbs(endEpoch.impliedVolatility, sigmaZero, _tolerance(endEpoch.impliedVolatility));

        (uint256 baseTokenAmount, uint256 sideTokenAmount) = _vault.balances();

        assertApproxEqAbs(endEpoch.baseTokenAmount, baseTokenAmount, _tolerance(endEpoch.baseTokenAmount));
        assertApproxEqAbs(endEpoch.sideTokenAmount, sideTokenAmount, _tolerance(endEpoch.sideTokenAmount));
        assertApproxEqAbs(endEpoch.v0, _vault.v0(), _tolerance(endEpoch.v0));

        // Checking user payoff for matured positions
        uint256 vaultPendingPayoff = VaultUtils.getState(_vault).liquidity.pendingPayoffs;
        assertApproxEqAbs(endEpoch.payoffNet, vaultPendingPayoff, _tolerance(endEpoch.payoffNet));

        uint256 accPayoffNet = 0;
        uint256 accPayoffFees = 0;
        uint256 accNetPaid = 0;
        vm.startPrank(_trader);
        {
            uint256 numPositions = _pm.balanceOf(_trader);
            for (uint i = 0; i < numPositions; i++) {
                uint256 tokenID = _pm.tokenOfOwnerByIndex(_trader, 0);
                IPositionManager.PositionDetail memory posDetail = _pm.positionDetail(tokenID);
                (uint256 traderPayoffNet, uint256 fees) = _pm.payoff(
                    tokenID,
                    posDetail.notionalUp,
                    posDetail.notionalDown
                );
                accPayoffNet += traderPayoffNet;
                accPayoffFees += fees;
                IPositionManager.SellParams memory params = IPositionManager.SellParams({
                    tokenId: tokenID,
                    notionalUp: posDetail.notionalUp,
                    notionalDown: posDetail.notionalDown,
                    expectedMarketValue: traderPayoffNet,
                    maxSlippage: 1e18
                });
                uint256 netPaid = _pm.sell(params);
                accNetPaid += netPaid;
            }
        }

        assertApproxEqAbs(endEpoch.payoffNet, accPayoffNet + accPayoffFees, _tolerance(endEpoch.payoffNet));

        // Right now it makes sense only becasue there is only one trader
        assertApproxEqAbs(endEpoch.payoffTotal, accNetPaid, _tolerance(endEpoch.payoffTotal));

        vm.stopPrank();

        // TODO: add missing "complete withdraw"
    }

    function _tolerance(uint256 value) private view returns (uint256 tol) {
        if (value == 0) { // only works for 18 decimals
            return 1e9;
        }
        tol = (value * _tolerancePercentage) / 1e18;
        if (tol < 5e6) { // only works for 18 decimals
            tol = 5e6;
        }
    }

    function _tolerance(int256 value) private view returns (uint256) {
        return _tolerance(uint256(value >= 0 ? value : -value));
    }

    function _getTestsFromJson(string memory filename) internal view returns (string memory) {
        string memory directory = string.concat(vm.projectRoot(), "/test/resources/scenarios/");
        string memory file = string.concat(filename, ".json");
        string memory path = string.concat(directory, file);

        return vm.readFile(path);
    }

    function _getStartEpochFromJson(string memory json) private returns (StartEpoch memory) {
        string[24] memory paths = [
            "pre.sideTokenPrice",
            "pre.impliedVolatility",
            "pre.riskFreeRate",
            "pre.tradeVolatilityUtilizationRateFactor",
            "pre.tradeVolatilityTimeDecay",
            "pre.sigmaMultiplier",
            "pre.capFee",
            "pre.capFeeMaturity",
            "pre.fee",
            "pre.feeMaturity",
            "pre.minFeeBeforeTimeThreshold",
            "pre.minFeeAfterTimeThreshold",
            "pre.exchangeSlippage",
            "pre.exchangeFeeTier",
            "pre.successFee",
            "deposit",
            "duration",
            "post.baseTokenAmount",
            "post.sideTokenAmount",
            "post.impliedVolatility",
            "post.strike",
            "post.kA",
            "post.kB",
            "post.theta"
        ];
        uint256[24] memory vars;

        string memory fixedJsonPath = "$.startEpoch";
        for (uint256 i = 0; i < paths.length; i++) {
            string memory path = paths[i];
            vars[i] = _getUintJsonFromPath(json, fixedJsonPath, path);
        }
        uint256 counter = 0;
        StartEpoch memory startEpoch = StartEpoch({
            pre: StartEpochPreConditions({
                sideTokenPrice: vars[counter++],
                impliedVolatility: vars[counter++],
                riskFreeRate: vars[counter++],
                tradeVolatilityUtilizationRateFactor: vars[counter++],
                tradeVolatilityTimeDecay: vars[counter++],
                sigmaMultiplier: vars[counter++],
                capFee: vars[counter++],
                capFeeMaturity: vars[counter++],
                fee: vars[counter++],
                feeMaturity: vars[counter++],
                minFeeBeforeTimeThreshold: vars[counter++],
                minFeeAfterTimeThreshold: vars[counter++],
                exchangeSlippage: vars[counter++],
                exchangeFeeTier: vars[counter++],
                successFee: vars[counter++]
            }),
            deposit: vars[counter++],
            duration: vars[counter++],
            post: StartEpochPostConditions({
                baseTokenAmount: vars[counter++],
                sideTokenAmount: vars[counter++],
                impliedVolatility: vars[counter++],
                strike: vars[counter++],
                kA: vars[counter++],
                kB: vars[counter++],
                theta: vars[counter++]
            })
        });
        return startEpoch;
    }

    function _getTradesFromJson(string memory json) private returns (Trade[] memory ts) {
        uint256 tradeNumber = stdJson.readUint(json, "$.tradeNumber");
        ts = new Trade[](tradeNumber);
        for (uint256 i = 0; i < tradeNumber; i++) {
            string memory path = string.concat("$.trades[", Strings.toString(i), "]");
            bytes memory tradeDetail = stdJson.parseRaw(json, path);
            Trade memory t = abi.decode(tradeDetail, (Trade));
            ts[i] = t;
        }
    }

    function _getEndEpochFromJson(string memory json) private pure returns (EndEpoch memory endEpoch) {
        string memory path = "$.endEpoch";
        bytes memory endEpochBytes = stdJson.parseRaw(json, path);
        endEpoch = abi.decode(endEpochBytes, (EndEpoch));
    }

    function _getUintJsonFromPath(
        string memory json,
        string memory fixedJsonPath,
        string memory path
    ) private returns (uint256) {
        string memory jsonPath = string.concat(fixedJsonPath, ".", path);
        return stdJson.readUint(json, jsonPath);
    }

    function _getIntJsonFromPath(
        string memory json,
        string memory fixedJsonPath,
        string memory path
    ) private returns (int256) {
        string memory jsonPath = string.concat(fixedJsonPath, ".", path);
        return stdJson.readInt(json, jsonPath);
    }
}
