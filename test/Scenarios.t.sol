// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {IG} from "../src/IG.sol";
import {TestnetPriceOracle} from "../src/testnet/TestnetPriceOracle.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {SignedMath} from "../src/lib/SignedMath.sol";
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

    // function testScenario1() public {
    //     // NOTE: values taken from the "Test" sheet of the "CL_Delta_Hedging_v2.xlsx" file
    //     // TBD: use position manager for easing the tests
    //     StartEpoch memory t0 = StartEpoch({
    //         pre: StartEpochPreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             impliedVolatility: 50e16, // 70%
    //             riskFreeRate: 3e16, // 3%
    //             tradeVolatilityUtilizationRateFactor: 2e18, // 2
    //             tradeVolatilityTimeDecay: 25e16, // 0.25
    //             sigmaMultiplier: 3e18 // 3
    //         }),
    //         v0: 100000e18, // 100'000
    //         post: StartEpochPostConditions({
    //             baseTokenAmount: 50000e18, // 50'000
    //             sideTokenAmount: 2631578947e10, // 26.31578947
    //             strike: 1900e18, // 1'900
    //             kA: 154361405620e10, // 1'543,61405620
    //             kB: 233866748330e10, // 2'338,66748330
    //             theta: 19730374e10, // 0,19730374
    //             limInf: -291960327105e8, // -29,1960327105
    //             limSup: 263157894737e8 // 26,3157894737
    //         })
    //     });
    //     _checkStartEpoch(t0);

    //     // TBD: find a way to better handle the elapsed time
    //     Utils.skipDay(false, vm); // 6 days to maturity

    //     console.log("TRADE 1 --------------------------------------------------------");

    //     Trade memory t1 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1950e18, // 2'000
    //             volatility: 482143e12, // 48,2143%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 50000e18, // 50'000
    //             sideTokenAmount: 2631578947e10, // 26.31578947
    //             utilizationRate: 0, // 0 %
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 50000e18, // 30'000
    //         strategy: OptionStrategy.CALL, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 462554010656e9, // $462,554010656
    //             volatility: 5424e14, // 54.24 %
    //             baseTokenAmount: 456254763069946e8, // 45'625,4763069946
    //             sideTokenAmount: 287963421422e8, // 28,7963421422
    //             utilizationRate: 5e17, // 50 %
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 0e18 // 0
    //         })
    //     });
    //     _checkTrade(t1);

    //     Utils.skipDay(false, vm); // 5 days to maturity
    //     console.log("TRADE 2 --------------------------------------------------------");
    //     Trade memory t2 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 4000e18, // 1'900
    //             volatility: 5223e14, // 52.23 %
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 456254763069946e8, // 45'625,4763069946
    //             sideTokenAmount: 287963421422e8, // 28,7963421422
    //             utilizationRate: 5e17, // 50 %
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 0e18 // 0
    //         }),
    //         isMint: false,
    //         amount: 30000e18, // 30'000
    //         strategy: OptionStrategy.CALL, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 29888092778079e9, // $29.888,092778079
    //             volatility: 4680e14, // 46,80%
    //             baseTokenAmount: 88817366964020e9, // 88'817,366964020
    //             sideTokenAmount: 10526346283e9, // 10,526346283
    //             utilizationRate: 2e17, // 20%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 30000e18 // 30'000
    //         })
    //     });
    //     _checkTrade(t2);

    //     Utils.skipDay(false, vm); // 4 days to maturity
    //     console.log("TRADE 3 --------------------------------------------------------");
    //     Trade memory t3 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 8000e18, // 8'000
    //             volatility: 45e16, // 45 %
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 88817366964020e9, // 88'817,366964020
    //             sideTokenAmount: 10526346283e9, // 10,526346283
    //             utilizationRate: 2e17, // 20%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 30000e18 // 30'000
    //         }),
    //         isMint: false,
    //         amount: 20000e18, // 30'000
    //         strategy: OptionStrategy.CALL, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 620288352655138e8, // 62.028,8352655138
    //             volatility: 4464e14, // 44,64%
    //             baseTokenAmount: 110999301966089e9, // 110.999,301966089
    //             sideTokenAmount: 4597e3, // 0,000000000004597
    //             utilizationRate: 0e17, // 20%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 30'000
    //         })
    //     });
    //     _checkTrade(t3);

    //     Utils.skipDay(false, vm); // 3 days to maturity
    //     console.log("TRADE 4 --------------------------------------------------------");
    //     Trade memory t4 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 2100e18, // 2'100
    //             volatility: 4286e14, // 42,86%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 110999301966089e9, // 110.999,301966089
    //             sideTokenAmount: 4597e3, // 0,000000000004597
    //             utilizationRate: 0e17, // 0%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 30'000
    //         }),
    //         isMint: true,
    //         amount: 30000e18, // 30'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 10960634682e7, // $0,10960634682
    //             volatility: 4401e14, // 44,01%
    //             baseTokenAmount: 87945399144803e9, // 87'945,399144803
    //             sideTokenAmount: 10978101156020e6, // 10,978101156020
    //             utilizationRate: 30e17, // 30%
    //             availableNotionalBear: 20000e18, // 20'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t4);

    //     Utils.skipDay(false, vm); // 2 days to maturity
    //     console.log("TRADE 5 --------------------------------------------------------");
    //     Trade memory t5 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1800e18, // 8'000
    //             volatility: 4218e14, // 42,18%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 87945399144803e9, // 87'945,399144803
    //             sideTokenAmount: 10978101156020e6, // 10,978101156020
    //             utilizationRate: 30e17, // 30%
    //             availableNotionalBear: 20000e18, // 20'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: false,
    //         amount: 25000e18, // 25'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 238516634705e9, // $238,516634705
    //             volatility: 4108e14, // 41,08%
    //             baseTokenAmount: 43444962386987e9, // 43.444,962386987
    //             sideTokenAmount: 35568056780e9, // 35,568056780
    //             utilizationRate: 5e16, // 5%
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t5);

    //     Utils.skipDay(false, vm); // 1 days to maturity
    //     console.log("TRADE 6 --------------------------------------------------------");
    //     Trade memory t6 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 3929e14, // 39,29%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 43444962386987e9, // 43.444,962386987
    //             sideTokenAmount: 35568056780e9, // 35,568056780
    //             utilizationRate: 5e16, // 5%
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 17500e18, // 17'500
    //         strategy: OptionStrategy.CALL, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 9437702813e9, // $9,437702813
    //             volatility: 3973e14, // 39,73%
    //             baseTokenAmount: 50050569569100e9, //50'050,569569100
    //             sideTokenAmount: 32096388633e9, // 32,096388633
    //             utilizationRate: 225e15, // 22,5%
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 32500e18 // 32'500
    //         })
    //     });
    //     _checkTrade(t6);

    //     // ToDo: check burn market value after time (and maybe changed market conditions)

    //     // ToDo: check payoff after maturity
    // }

    // function testScenario2() public {
    //     // NOTE: values taken from the "Test" sheet of the "CL_Delta_Hedging_v2.xlsx" file
    //     // TBD: use position manager for easing the tests
    //     StartEpoch memory t0 = StartEpoch({
    //         pre: StartEpochPreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             impliedVolatility: 70e16, // 70%
    //             riskFreeRate: 3e16, // 3%
    //             tradeVolatilityUtilizationRateFactor: 2e18, // 2
    //             tradeVolatilityTimeDecay: 25e16, // 0.25
    //             sigmaMultiplier: 3e18 // 3
    //         }),
    //         v0: 100000e18, // 100'000
    //         post: StartEpochPostConditions({
    //             baseTokenAmount: 50000e18, // 50'000
    //             sideTokenAmount: 2631578947e10, // 26.31578947
    //             strike: 1900e18, // 1'900
    //             kA: 1420537732786e9, // 1'420,537732786
    //             kB: 2541291172125e9, // 2'541,291172125
    //             theta: 270663204e9, // 0,270663204
    //             limInf: -30434545241e9, // -30,434545241
    //             limSup: 26315789474e9 //   26,315789474
    //         })
    //     });
    //     _checkStartEpoch(t0);

    //     // TBD: find a way to better handle the elapsed time
    //     Utils.skipDay(false, vm); // 6 days to maturity

    //     console.log("TRADE 1 --------------------------------------------------------");

    //     Trade memory t1 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 6750e14, // 67.50%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 50000e18, // 50'000
    //             sideTokenAmount: 2631578947e10, // 26.31578947
    //             utilizationRate: 0, // 0 %
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 34248393361e9, // 34,248393361
    //             volatility: 6751e14, // 67.51 %
    //             baseTokenAmount: 51397566104425e9, // 51'397,566104425
    //             sideTokenAmount: 25598253836e9, //        25,598253836
    //             utilizationRate: 5e16, // 5 %
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50000
    //         })
    //     });
    //     _checkTrade(t1);

    //     Utils.skipDay(false, vm); // 5 days to maturity
    //     console.log("TRADE 2 --------------------------------------------------------");
    //     Trade memory t2 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 6501e14, // 65.01 %
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 51397566104425e9, // 51'397,566104425
    //             sideTokenAmount: 25598253836e9, //        25,598253836
    //             utilizationRate: 5e16, // 5 %
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 26490720831e9, // 26,490720831
    //             volatility: 6507e14, // 65,07%
    //             baseTokenAmount: 51891387566719e9, // 51'891,387566719
    //             sideTokenAmount: 25352290288e9, // 25,352290288
    //             utilizationRate: 1e17, // 10%
    //             availableNotionalBear: 40000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 30'000
    //         })
    //     });
    //     _checkTrade(t2);

    //     Utils.skipDay(false, vm); // 4 days to maturity
    //     console.log("TRADE 3 --------------------------------------------------------");
    //     Trade memory t3 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 6256e14, // 62.56 %
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 51891387566719e9, // 51'891,387566719
    //             sideTokenAmount: 25352290288e9, // 25,352290288
    //             utilizationRate: 1e17, // 10%
    //             availableNotionalBear: 40000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 30'000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 19642906686e9, // $19,642906686
    //             volatility: 6271e14, // 62.71%
    //             baseTokenAmount: 52314845824294e9, // 52'314,845824294
    //             sideTokenAmount: 25139755893e9, // 25,139755893
    //             utilizationRate: 15e16, // 15%
    //             availableNotionalBear: 35000e18, // 35'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t3);

    //     Utils.skipDay(false, vm); // 3 days to maturity
    //     console.log("TRADE 4 --------------------------------------------------------");
    //     Trade memory t4 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 6020e14, // 60,20%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 52314845824294e9, // 52'314,845824294
    //             sideTokenAmount: 25139755893e9, // 25,139755893
    //             utilizationRate: 15e16, // 15%
    //             availableNotionalBear: 35000e18, // 35'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 13654326241e9, // $13,654326241
    //             volatility: 6048e14, // 60.48%
    //             baseTokenAmount: 52830052213085e9, // 52'830,052213085
    //             sideTokenAmount: 24875781123e6, // 24,875781123
    //             utilizationRate: 20e17, // 20%
    //             availableNotionalBear: 30000e18, // 30'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t4);

    //     Utils.skipDay(false, vm); // 2 days to maturity
    //     console.log("TRADE 5 --------------------------------------------------------");
    //     Trade memory t5 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 8'000
    //             volatility: 5796e14, // 57,96%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 52830052213085e9, // 52'830,052213085
    //             sideTokenAmount: 24875781123e6, // 24,875781123
    //             utilizationRate: 20e17, // 20%
    //             availableNotionalBear: 30000e18, // 30'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 8447571231e9, // 8,447571231
    //             volatility: 5840e14, // 58.40%
    //             baseTokenAmount: 54180392695204e9, // 54'180,392695204
    //             sideTokenAmount: 24169521696e9, // 24,169521696
    //             utilizationRate: 25e16, // 25%
    //             availableNotionalBear: 25000e18, // 25'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t5);

    //     Utils.skipDay(false, vm); // 1 days to maturity
    //     console.log("TRADE 6 --------------------------------------------------------");
    //     Trade memory t6 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 5586e14, // 55,86%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 54180392695204e9, // 54'180,392695204
    //             sideTokenAmount: 24169521696e9, // 24,169521696
    //             utilizationRate: 25e16, // 25%
    //             availableNotionalBear: 25000e18, // 25'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 3929975579e9, // 3,929975579
    //             volatility: 5649e14, // 56,49%
    //             baseTokenAmount: 65345850928972e9, // 65'345,850928972
    //             sideTokenAmount: 18295033139e9, // 18,295033139
    //             utilizationRate: 30e16, // 30%
    //             availableNotionalBear: 20000e18, // 20'000
    //             availableNotionalBull: 50000e18 // 50500
    //         })
    //     });
    //     _checkTrade(t6);

    //     // ToDo: check burn market value after time (and maybe changed market conditions)

    //     // ToDo: check payoff after maturity
    // }

    // function testScenario2Bis() public {
    //     // NOTE: values taken from the "Test" sheet of the "CL_Delta_Hedging_v2.xlsx" file
    //     // TBD: use position manager for easing the tests
    //     StartEpoch memory t0 = StartEpoch({
    //         pre: StartEpochPreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             impliedVolatility: 70e16, // 70%
    //             riskFreeRate: 3e16, // 3%
    //             tradeVolatilityUtilizationRateFactor: 2e18, // 2
    //             tradeVolatilityTimeDecay: 25e16, // 0.25
    //             sigmaMultiplier: 3e18 // 3
    //         }),
    //         v0: 100000e18, // 100'000
    //         post: StartEpochPostConditions({
    //             baseTokenAmount: 50000e18, // 50'000
    //             sideTokenAmount: 2631578947e10, // 26.31578947
    //             strike: 1900e18, // 1'900
    //             kA: 1420537732786e9, // 1'420,537732786
    //             kB: 2541291172125e9, // 2'541,291172125
    //             theta: 270663204e9, // 0,270663204
    //             limInf: -30434545241e9, // -30,434545241
    //             limSup: 26315789474e9 //   26,315789474
    //         })
    //     });
    //     _checkStartEpoch(t0);

    //     // TBD: find a way to better handle the elapsed time
    //     Utils.skipDay(false, vm); // 6 days to maturity

    //     console.log("TRADE 1 --------------------------------------------------------");

    //     Trade memory t1 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 6750e14, // 67.50%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 50000e18, // 50'000
    //             sideTokenAmount: 2631578947e10, // 26.31578947
    //             utilizationRate: 0, // 0 %
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 34248393361e9, // 34,248393361
    //             volatility: 6751e14, // 67.51 %
    //             baseTokenAmount: 51397566104425e9, // 51'397,566104425
    //             sideTokenAmount: 25598253836e9, //        25,598253836
    //             utilizationRate: 5e16, // 5 %
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50000
    //         })
    //     });
    //     _checkTrade(t1);

    //     Utils.skipDay(false, vm); // 5 days to maturity
    //     console.log("TRADE 2 --------------------------------------------------------");
    //     Trade memory t2 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 6501e14, // 65.01 %
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 51397566104425e9, // 51'397,566104425
    //             sideTokenAmount: 25598253836e9, //        25,598253836
    //             utilizationRate: 5e16, // 5 %
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50000
    //         }),
    //         isMint: false,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 26490720831e9, // 26,490720831
    //             volatility: 6500e14, // 65,07%
    //             baseTokenAmount: 50625375844955e9, // 50'625,375844955
    //             sideTokenAmount: 25990727278e9, //        25,990727278
    //             utilizationRate: 0e18, // 0%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t2);

    //     Utils.skipDay(false, vm); // 4 days to maturity
    //     console.log("TRADE 3 --------------------------------------------------------");
    //     Trade memory t3 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 6250e14, // 62.50 %
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 50625375844955e9, // 50'625,375844955
    //             sideTokenAmount: 25990727278e9, //        25,990727278
    //             utilizationRate: 0e18, // 0%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 19603533241e9, // 19,603533241
    //             volatility: 6251e14, // 62.51%
    //             baseTokenAmount: 51114083896334e9, // 51'114,083896334
    //             sideTokenAmount: 25743830163e9, //        25,743830163
    //             utilizationRate: 5e16, // 5%
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t3);

    //     Utils.skipDay(false, vm); // 3 days to maturity
    //     console.log("TRADE 4 --------------------------------------------------------");
    //     Trade memory t4 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 6001e14, // 60,01%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 51114083896334e9, // 51'114,083896334
    //             sideTokenAmount: 25743830163e9, //        25,743830163
    //             utilizationRate: 5e16, // 5%
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: false,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 13565712969e9, // 13,565712969
    //             volatility: 60e16, // 60%
    //             baseTokenAmount: 50384682178384e9, // 50'384,682178384
    //             sideTokenAmount: 26120585955e9, // 26,120585955
    //             utilizationRate: 0e18, // 0%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t4);

    //     Utils.skipDay(false, vm); // 2 days to maturity
    //     console.log("TRADE 5 --------------------------------------------------------");
    //     Trade memory t5 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 8'000
    //             volatility: 5750e14, // 57,50%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 50384682178384e9, // 50'384,682178384
    //             sideTokenAmount: 26120585955e9, // 26,120585955
    //             utilizationRate: 0e18, // 0%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: true,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 8313622845e9, // 8,313622845
    //             volatility: 5751e14, // 57.51%
    //             baseTokenAmount: 50840290122888e9, // 50'840,290122888
    //             sideTokenAmount: 25885167891e9, // 25,885167891
    //             utilizationRate: 5e16, // 5%
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t5);

    //     Utils.skipDay(false, vm); // 1 days to maturity
    //     console.log("TRADE 6 --------------------------------------------------------");
    //     Trade memory t6 = Trade({
    //         pre: TradePreConditions({
    //             sideTokenPrice: 1900e18, // 1'900
    //             volatility: 5501e14, // 55,01%
    //             riskFreeRate: 3e16, // 3%
    //             baseTokenAmount: 50840290122888e9, // 50'840,290122888
    //             sideTokenAmount: 25885167891e9, // 25,885167891
    //             utilizationRate: 5e17, // 5%
    //             availableNotionalBear: 45000e18, // 45'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         }),
    //         isMint: false,
    //         amount: 5000e18, // 5'000
    //         strategy: OptionStrategy.PUT, // Bear
    //         epochOfBurnedPosition: 0, // ignored
    //         post: TradePostConditions({
    //             marketValue: 3810676958e9, // 3,810676958
    //             volatility: 55e16, // 55,16%
    //             baseTokenAmount: 44435287320460e9, // 44'435,287320460
    //             sideTokenAmount: 29254216378e9, // 29,254216378
    //             utilizationRate: 0e18, // 0%
    //             availableNotionalBear: 50000e18, // 50'000
    //             availableNotionalBull: 50000e18 // 50'000
    //         })
    //     });
    //     _checkTrade(t6);

    //     // ToDo: check burn market value after time (and maybe changed market conditions)

    //     // ToDo: check payoff after maturity
    // }

    function testScenario3() public {
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
                kA: 1420537732786e9, // 1'420,537732786
                kB: 2541291172125e9, // 2'541,291172125
                theta: 270663204e9, // 0,270663204
                limInf: -30434545241e9, // -30,434545241
                limSup: 26315789474e9 //   26,315789474
            })
        });
        _checkStartEpoch(t0);

        // TBD: find a way to better handle the elapsed time
        Utils.skipDay(false, vm); // 6 days to maturity

        console.log("TRADE 1 --------------------------------------------------------");

        Trade memory t1 = Trade({
            pre: TradePreConditions({
                sideTokenPrice: 1900e18, // 1'900
                volatility: 6750e14, // 67.50%
                riskFreeRate: 3e16, // 3%
                baseTokenAmount: 50000e18, // 50'000
                sideTokenAmount: 2631578947e10, // 26.31578947
                utilizationRate: 0, // 0 %
                availableNotionalBear: 50000e18, // 50'000
                availableNotionalBull: 50000e18 // 50'000
            }),
            isMint: true,
            amount: 50000e18, // 50'000
            strategy: OptionStrategy.PUT, // Bear
            epochOfBurnedPosition: 0, // ignored
            post: TradePostConditions({
                marketValue: 342483933606e9, // 
                volatility: 7594e14, // 75,94 %
                baseTokenAmount: 58361171550765e9, // 58'361,171550765
                sideTokenAmount: 22095427570e9, //        22,095427570
                utilizationRate: 50e16, // 50 %
                availableNotionalBear: 0e18, // 0
                availableNotionalBull: 50000e18 // 50000
            })
        });
        _checkTrade(t1);

        Utils.skipDay(false, vm); // 5 days to maturity
        console.log("TRADE 2 --------------------------------------------------------");
        Trade memory t2 = Trade({
            pre: TradePreConditions({
                sideTokenPrice: 1900e18, // 1'900
                volatility: 7313e14, // 73.13 %
                riskFreeRate: 3e16, // 3%
                baseTokenAmount: 58361171550765e9, // 58'361,171550765
                sideTokenAmount: 22095427570e9, //        22,095427570
                utilizationRate: 50e16, // 50 %
                availableNotionalBear: 0e18, // 0
                availableNotionalBull: 50000e18 // 50000
            }),
            isMint: false,
            amount: 50000e18, // 50'000
            strategy: OptionStrategy.PUT, // Bear
            epochOfBurnedPosition: 0, // ignored
            post: TradePostConditions({
                marketValue: 335454855023e9, // 335,454855023
                volatility: 6500e14, // 65,00%
                baseTokenAmount: 50624647251007e9, // 50.624,647251007
                sideTokenAmount: 25990727278e9, //        25,990727278
                utilizationRate: 0e18, // 0%
                availableNotionalBear: 50000e18, // 50'000
                availableNotionalBull: 50000e18 // 50'000
            })
        });
        _checkTrade(t2);

        Utils.skipDay(false, vm); // 4 days to maturity
        console.log("TRADE 3 --------------------------------------------------------");
        Trade memory t3 = Trade({
            pre: TradePreConditions({
                sideTokenPrice: 1900e18, // 1'900
                volatility: 6250e14, // 62.50 %
                riskFreeRate: 3e16, // 3%
                baseTokenAmount: 50624647251007e9, // 50.624,647251007
                sideTokenAmount: 25990727278e9, //        25,990727278
                utilizationRate: 0e18, // 0%
                availableNotionalBear: 50000e18, // 50'000
                availableNotionalBull: 50000e18 // 50'000
            }),
            isMint: true,
            amount: 50000e18, // 50'000
            strategy: OptionStrategy.PUT, // Bear
            epochOfBurnedPosition: 0, // ignored
            post: TradePostConditions({
                marketValue: 196035332407e9, // 196,035332407
                volatility: 7031e14, // 70.31%
                baseTokenAmount: 56753869238706e9, // 56'753,869238706
                sideTokenAmount: 22867997459e9, //        22,867997459
                utilizationRate: 50e16, // 50%
                availableNotionalBear: 0e18, // 0
                availableNotionalBull: 50000e18 // 50'000
            })
        });
        _checkTrade(t3);

        Utils.skipDay(false, vm); // 3 days to maturity
        console.log("TRADE 4 --------------------------------------------------------");
        Trade memory t4 = Trade({
            pre: TradePreConditions({
                sideTokenPrice: 1900e18, // 1'900
                volatility: 6750e14, // 67,50%
                riskFreeRate: 3e16, // 3%
                baseTokenAmount: 56753869238706e9, // 56'753,869238706
                sideTokenAmount: 22867997459e9, //        22,867997459
                utilizationRate: 50e16, // 50%
                availableNotionalBear: 0e18, // 0
                availableNotionalBull: 50000e18 // 50'000
            }),
            isMint: false,
            amount: 50000e18, // 50'000
            strategy: OptionStrategy.PUT, // Bear
            epochOfBurnedPosition: 0, // ignored
            post: TradePostConditions({
                marketValue: 171777738260e9, // 171,777738260
                volatility: 6000e14, // 60,00%
                baseTokenAmount: 50402173358313e9, // 50'402,173358313
                sideTokenAmount: 26120585955e9, // 26,120585955
                utilizationRate: 0e18, // 0%
                availableNotionalBear: 50000e18, // 50'000
                availableNotionalBull: 50000e18 // 50'000
            })
        });
        _checkTrade(t4);

        Utils.skipDay(false, vm); // 2 days to maturity
        console.log("TRADE 5 --------------------------------------------------------");
        Trade memory t5 = Trade({
            pre: TradePreConditions({
                sideTokenPrice: 1900e18, // 8'000
                volatility: 5750e14, // 57,50%
                riskFreeRate: 3e16, // 3%
                baseTokenAmount: 50402173358313e9, // 50'402,173358313
                sideTokenAmount: 26120585955e9, // 26,120585955
                utilizationRate: 0e18, // 0%
                availableNotionalBear: 50000e18, // 50'000
                availableNotionalBull: 50000e18 // 50'000
            }),
            isMint: true,
            amount: 50000e18, // 50'000
            strategy: OptionStrategy.PUT, // Bear
            epochOfBurnedPosition: 0, // ignored
            post: TradePostConditions({
                marketValue: 83136228449e9, // 8,3136228449
                volatility: 6469e14, // 64.69%
                baseTokenAmount: 57068256903808e9, // 57'068,256903808
                sideTokenAmount: 22655876841e9, // 22,655876841
                utilizationRate: 50e16, // 50%
                availableNotionalBear: 0e18, // 0
                availableNotionalBull: 50000e18 // 50'000
            })
        });
        _checkTrade(t5);

        Utils.skipDay(false, vm); // 1 days to maturity
        console.log("TRADE 6 --------------------------------------------------------");
        Trade memory t6 = Trade({
            pre: TradePreConditions({
                sideTokenPrice: 1900e18, // 1'900
                volatility: 5500e14, // 55,00%
                riskFreeRate: 3e16, // 3%
                baseTokenAmount: 57068256903808e9, // 57'068,256903808
                sideTokenAmount: 22655876841e9, // 22,655876841
                utilizationRate: 50e16, // 50%
                availableNotionalBear: 0e18, // 0
                availableNotionalBull: 50000e18 // 50'000
            }),
            isMint: false,
            amount: 50000e18, // 50'000
            strategy: OptionStrategy.PUT, // Bear
            epochOfBurnedPosition: 0, // ignored
            post: TradePostConditions({
                marketValue: 48240571300e9, // $48,240571300
                volatility: 55e16, // 55,16%
                baseTokenAmount: 44483171211650e9, // 44'483,171211650
                sideTokenAmount: 29254216378e9, // 29,254216378
                utilizationRate: 0e18, // 0%
                availableNotionalBear: 50000e18, // 50'000
                availableNotionalBull: 50000e18 // 50'000
            })
        });
        _checkTrade(t6);

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
        vm.startPrank(_admin);
        _oracle.setRiskFreeRate(t.pre.riskFreeRate);
        _oracle.setTokenPrice(_vault.sideToken(), t.pre.sideTokenPrice);
        vm.stopPrank();

        console.log("PRE --------------------------------------------------------");
        (uint256 baseTokenAmount, uint256 sideTokenAmount) = _vault.balances();
        // assertApproxEqAbs(t.pre.baseTokenAmount, baseTokenAmount, _toleranceOnAmount);
        // assertApproxEqAbs(t.pre.sideTokenAmount, sideTokenAmount, _toleranceOnAmount);

        // assertEq(t.pre.utilizationRate, _dvp.getUtilizationRate());
        (, , uint256 availableBearNotional, uint256 availableBullNotional) = _dvp.notional();
        // assertEq(t.pre.availableNotionalBear, availableBearNotional);
        // assertEq(t.pre.availableNotionalBull, availableBullNotional);
        uint256 strike = _dvp.currentStrike();
        // assertApproxEqAbs(t.pre.volatility, _dvp.getPostTradeVolatility(strike, 0), _toleranceOnPercentage);

        // actual trade:
        uint256 marketValue;
        if (t.isMint) {
            marketValue = _dvp.premium(strike, t.strategy, t.amount);
            TokenUtils.provideApprovedTokens(_admin, _vault.baseToken(), _trader, address(_dvp), marketValue, vm);
            vm.prank(_trader);
            marketValue = _dvp.mint(_trader, strike, t.strategy, t.amount);
            console.log("Epoch", _dvp.currentEpoch());
            // TBD: check slippage on market value
        } else {
            vm.prank(_trader);
            marketValue = _dvp.burn(1683273600, _trader, strike, t.strategy, t.amount);
        }

        console.log("POST --------------------------------------------------------");
        console.log("Market Value", marketValue);
        //post-conditions:
        assertApproxEqAbs(t.post.marketValue, marketValue, (t.post.marketValue * 10) / 10000);
        assertEq(t.post.utilizationRate, _dvp.getUtilizationRate());
        (, , availableBearNotional, availableBullNotional) = _dvp.notional();
        assertEq(t.post.availableNotionalBear, availableBearNotional);
        assertEq(t.post.availableNotionalBull, availableBullNotional);
        assertApproxEqAbs(t.post.volatility, _dvp.getPostTradeVolatility(strike, 0), _toleranceOnPercentage);

        (baseTokenAmount, sideTokenAmount) = _vault.balances();
        console.log("baseTokenAmount", baseTokenAmount);
        console.log("sideTokenAmount", sideTokenAmount);

        assertApproxEqAbs(t.post.baseTokenAmount, baseTokenAmount, (t.post.baseTokenAmount * 100) / 10000);
        assertApproxEqAbs(t.post.sideTokenAmount, sideTokenAmount, (t.post.baseTokenAmount * 100) / 10000);
    }
}
