// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {Notional} from "../src/lib/Notional.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {SignedMath} from "../src/lib/SignedMath.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {IG} from "../src/IG.sol";
import {TestnetPriceOracle} from "../src/testnet/TestnetPriceOracle.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {Utils} from "./utils/Utils.sol";

contract TestScenariosJson is Test {
    address internal _admin;
    address internal _liquidityProvider;
    address internal _trader;
    AddressProvider internal _ap;
    MockedVault internal _vault;
    MockedIG internal _dvp;
    TestnetPriceOracle internal _oracle;
    uint256 internal _toleranceOnPercentage;
    uint256 internal _toleranceOnAmount;

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
    }

    struct Rebalance {
        uint256 baseTokenAmount;
        uint256 depositAmount;
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
        _checkScenario("scenario_1");
    }

    function testScenario2() public {
        _checkScenario("scenario_2");
    }

    function testScenario3() public {
        _checkScenario("scenario_3");
    }

    function testScenario4() public {
        _checkScenario("scenario_4");
    }


    function _checkScenario(string memory scenarioName) internal {
        console.log(string.concat("Executing scenario: ", scenarioName));
        string memory scenariosJSON = _getTestsFromJson(scenarioName);

        console.log("- Checking start epoch");
        StartEpoch memory startEpoch = _getStartEpochFromJson(scenariosJSON);
        _checkStartEpoch(startEpoch);

        Trade[] memory trades = _getTradesFromJson(scenariosJSON);
        for (uint i = 0; i < trades.length; i++) {
            console.log("- Checking trade number", i+1);
            _checkTrade(trades[i]);
        }

        // ToDo: replace with a "_checkMaturity".
        console.log("- Checking rebalance");
        _checkRebalance(scenariosJSON);
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
        // assertEq(t0.post.baseTokenAmount, baseTokenAmount); // TMP for math precision
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
        vm.warp(block.timestamp + t.elapsedTimeSeconds);
        vm.startPrank(_admin);
        _oracle.setRiskFreeRate(t.pre.riskFreeRate);
        _oracle.setTokenPrice(_vault.sideToken(), t.pre.sideTokenPrice);
        vm.stopPrank();

        (uint256 baseTokenAmount, uint256 sideTokenAmount) = _vault.balances();
        assertApproxEqAbs(t.pre.baseTokenAmount, baseTokenAmount, _tollerancePercentage(t.pre.baseTokenAmount, 3));
        assertApproxEqAbs(t.pre.sideTokenAmount, sideTokenAmount, _tollerancePercentage(t.pre.sideTokenAmount, 3));

        assertEq(t.pre.utilizationRate, _dvp.getUtilizationRate());
        (, , uint256 availableBearNotional, uint256 availableBullNotional) = _dvp.notional();
        assertEq(t.pre.availableNotionalBear, availableBearNotional);
        assertEq(t.pre.availableNotionalBull, availableBullNotional);
        uint256 strike = _dvp.currentStrike();
        assertApproxEqAbs(t.pre.volatility, _dvp.getPostTradeVolatility(strike, Notional.Amount({up: 0, down: 0}), true), _toleranceOnPercentage);

        // actual trade:
        uint256 marketValue;
        if (t.isMint) {
            marketValue = _dvp.premium(strike, t.amountUp, t.amountDown);
            TokenUtils.provideApprovedTokens(_admin, _vault.baseToken(), _trader, address(_dvp), marketValue, vm);
            vm.prank(_trader);
            marketValue = _dvp.mint(_trader, strike, t.amountUp, t.amountDown, marketValue, 0.1e18);

            // TBD: check slippage on market value
        } else {
            vm.startPrank(_trader);
            marketValue = _dvp.payoff(_dvp.currentEpoch(), strike, t.amountUp, t.amountDown);
            marketValue = _dvp.burn(_dvp.currentEpoch(), _trader, strike, t.amountUp, t.amountDown, marketValue, 0.1e18);
            vm.stopPrank();
        }

        //post-conditions:
        assertApproxEqAbs(t.post.marketValue, marketValue, _tollerancePercentage(t.post.marketValue, 3));
        assertEq(t.post.utilizationRate, _dvp.getUtilizationRate());
        (, , availableBearNotional, availableBullNotional) = _dvp.notional();
        assertEq(t.post.availableNotionalBear, availableBearNotional);
        assertEq(t.post.availableNotionalBull, availableBullNotional);
        assertApproxEqAbs(t.post.volatility, _dvp.getPostTradeVolatility(strike, Notional.Amount({up: 0, down: 0}), true), _toleranceOnPercentage);

        (baseTokenAmount, sideTokenAmount) = _vault.balances();

        assertApproxEqAbs(t.post.baseTokenAmount, baseTokenAmount, _tollerancePercentage(t.post.baseTokenAmount, 3));
        assertApproxEqAbs(t.post.sideTokenAmount, sideTokenAmount, _tollerancePercentage(t.post.sideTokenAmount, 3));
    }

    function _checkRebalance(string memory json) private {
        Rebalance memory rebalance = _getRebalanceFromJson(json);

        if (rebalance.withdrawSharesAmount > 0) {
            vm.prank(_liquidityProvider);
            (uint256 heldByAccount, uint256 heldByVault) = _vault.shareBalances(_liquidityProvider);
            assertGe(heldByAccount + heldByVault, rebalance.withdrawSharesAmount);
            vm.prank(_liquidityProvider);
            _vault.initiateWithdraw(rebalance.withdrawSharesAmount);
        }

        // TBD: add asserts for pre-conditions (e.g. vault balances)

        if (rebalance.depositAmount > 0) {
            VaultUtils.addVaultDeposit(_liquidityProvider, rebalance.depositAmount, _admin, address(_vault), vm);
        }

        vm.startPrank(_admin);
        _oracle.setTokenPrice(_vault.sideToken(), rebalance.sideTokenPrice);
        vm.stopPrank();

        vm.warp(_dvp.currentEpoch() + 1);
        _dvp.rollEpoch();

        (uint256 baseTokenAmount, uint256 sideTokenAmount) = _vault.balances();
        assertApproxEqAbs(
            rebalance.baseTokenAmount,
            baseTokenAmount,
            _tollerancePercentage(rebalance.baseTokenAmount, 3)
        );
        assertApproxEqAbs(
            rebalance.sideTokenAmount,
            sideTokenAmount,
            _tollerancePercentage(rebalance.sideTokenAmount, 3)
        );

        assertApproxEqAbs(
            rebalance.v0,
            _vault.v0(),
            _tollerancePercentage(rebalance.v0, 3)
        );

        // TBD: add missing "complete withdraw"
    }

    function _tollerancePercentage(uint256 value, uint256 percentage) private pure returns (uint256) {
        return (value * (percentage * 1e2)) / 10000;
    }

    function _getTestsFromJson(string memory filename) internal view returns (string memory) {
        string memory directory = string.concat(vm.projectRoot(), "/test/resources/scenarios/");
        string memory file = string.concat(filename, ".json");
        string memory path = string.concat(directory, file);

        return vm.readFile(path);
    }

    function _getStartEpochFromJson(string memory json) private returns (StartEpoch memory) {
        string[15] memory paths = [
            "pre.sideTokenPrice",
            "pre.impliedVolatility",
            "pre.riskFreeRate",
            "pre.tradeVolatilityUtilizationRateFactor",
            "pre.tradeVolatilityTimeDecay",
            "pre.sigmaMultiplier",
            "v0",
            "post.baseTokenAmount",
            "post.sideTokenAmount",
            "post.strike",
            "post.kA",
            "post.kB",
            "post.theta",
            "post.limInf",
            "post.limSup"
        ];
        uint256[15] memory vars;

        string memory fixedJsonPath = "$.startEpoch";
        for (uint256 i = 0; i < paths.length; i++) {
            string memory path = paths[i];
            bytes32 pathE = keccak256(abi.encodePacked(path));
            if (pathE == keccak256(abi.encodePacked("post.limInf"))) {
                vars[i] = SignedMath.abs(_getIntJsonFromPath(json, fixedJsonPath, path));
            } else {
                vars[i] = _getUintJsonFromPath(json, fixedJsonPath, path);
            }
        }
        uint256 counter = 0;
        StartEpoch memory startEpoch = StartEpoch({
            pre: StartEpochPreConditions({
                sideTokenPrice: vars[counter++],
                impliedVolatility: vars[counter++],
                riskFreeRate: vars[counter++],
                tradeVolatilityUtilizationRateFactor: vars[counter++],
                tradeVolatilityTimeDecay: vars[counter++],
                sigmaMultiplier: vars[counter++]
            }),
            v0: vars[counter++],
            post: StartEpochPostConditions({
                baseTokenAmount: vars[counter++],
                sideTokenAmount: vars[counter++],
                strike: vars[counter++],
                kA: vars[counter++],
                kB: vars[counter++],
                theta: vars[counter++],
                limInf: -int256(vars[counter++]),
                limSup: int256(vars[counter++])
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

    function _getRebalanceFromJson(string memory json) private pure returns (Rebalance memory rebalance) {
        string memory path = "$.rebalance";
        bytes memory rebalanceBytes = stdJson.parseRaw(json, path);
        rebalance = abi.decode(rebalanceBytes, (Rebalance));
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
