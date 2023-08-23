// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Gaussian} from "@solstat/Gaussian.sol";
import {AmountsMath} from "../src/lib/AmountsMath.sol";
import {FinanceIGDelta} from "../src/lib/FinanceIGDelta.sol";
import {FinanceIGPayoff} from "../src/lib/FinanceIGPayoff.sol";
import {FinanceIGPrice} from "../src/lib/FinanceIGPrice.sol";
import {WadTime} from "../src/lib/WadTime.sol";

contract FinanceLibTest is Test {
    using AmountsMath for uint256;

    struct DeltaComponents {
        int256 x;
        int256 igDBear;
        int256 igDBull;
    }

    struct PriceComponents {
        FinanceIGPrice.DTerms ds;
        FinanceIGPrice.DTerms das;
        FinanceIGPrice.DTerms dbs;
        uint256 pBear1;
        uint256 pBear2;
        uint256 pBear3;
        uint256 pBear4;
        uint256 pBear5;
        uint256 pBull1;
        uint256 pBull2;
        uint256 pBull3;
        uint256 pBull4;
        uint256 pBull5;
        uint256 pBear;
        uint256 pBull;
        uint256 igP;
    }

    struct Payoff {
        uint256 igBear;
        uint256 igBull;
    }

    struct TestCase {
        // inputs
        uint256 v0;
        FinanceIGDelta.Parameters deltaParams;
        FinanceIGPrice.Parameters priceParams;
        // results
        DeltaComponents delta;
        PriceComponents price;
        Payoff payoff;
    }

    struct LiquidityRange {
        // inputs
        uint256 strike;
        uint256 volatility;
        uint256 volatilityMultiplier;
        uint256 yearsOfMaturity;
        // results
        uint256 kA;
        uint256 kB;
    }

    struct TradeVolatility {
        // inputs
        uint256 baselineVolatility;
        uint256 utilizationRateFactor;
        uint256 timeDecay;
        uint256 utilizationRate;
        uint256 maturity;
        uint256 initialTime;
        // result
        uint256 volatility;
    }

    uint256 v0 = 1e23; // 100,000 (100 K)
    uint256 r = 3e16; // 0.03 (3 %)
    uint256 sigma = 5e17; // 0.5 (50 %)
    mapping(uint256 => TestCase) testCases;
    uint256 testCasesNum = 0;

    /**
        @dev Accepted delta on comparisons (up to 5e-6)
        This is mainly due to limitations of `Gaussian.cdf()` computation error.
     */
    uint256 constant ERR = 1e12;

    function setUp() public {
        uint256 tau;

        uint256 k = 19e20;
        uint256 ka = 18e20;
        uint256 kb = 20e20;
        uint256 teta = FinanceIGPrice._teta(k, ka, kb);
        (int256 limSup, int256 limInf) = FinanceIGDelta.lims(k, ka, kb, teta, v0);
        uint256 T = WadTime.nYears(WadTime.daysFraction(1, 1));
        (int256 alfa1, int256 alfa2) = FinanceIGDelta._alfas(k, ka, kb, sigma, T);

        assertApproxEqAbs(-27739402633990000000, limInf, ERR);
        assertApproxEqAbs(25632027047742500000, limSup, ERR);
        assertApproxEqAbs(-2065905623981380000, alfa1, ERR);
        assertApproxEqAbs(1959914026616160000, alfa2, ERR);

        // current price: 1900
        tau = WadTime.nYears(WadTime.daysFraction(1, 1));
        (alfa1, alfa2) = FinanceIGDelta._alfas(k, ka, kb, sigma, tau);

        testCases[0] = TestCase(
            v0,
            FinanceIGDelta.Parameters(sigma, k, 19e20, tau, limSup, limInf, alfa1, alfa2),
            FinanceIGPrice.Parameters(r, sigma, k, 19e20, tau, ka, kb, teta),
            DeltaComponents(0e9, -5385367943e9, 5443747370e9),
            PriceComponents(FinanceIGPrice.DTerms(16226142e9, -9945055e9, 3140544e9), FinanceIGPrice.DTerms(2082131766e9, 2055960569e9, 2069046168e9), FinanceIGPrice.DTerms(-1943687885e9, -1969859081e9, -1956773483e9), 9692368857e9, 9492356948e9, 18441880301e9, 368838939e9, 372383691e9, 9539764291e9, 9741356989e9, 18310708044e9, 486787268e9, 481992674e9, 162287400074e9, 163329325284e9, 325616725358e9),
            Payoff(0e9, 0e9)
        );

        // 1910
        tau = WadTime.nYears(WadTime.daysFraction(5, 6));
        (alfa1, alfa2) = FinanceIGDelta._alfas(k, ka, kb, sigma, tau);
        testCases[1] = TestCase(
            v0,
            FinanceIGDelta.Parameters(sigma, k, 191e19, tau, limSup, limInf, alfa1, alfa2),
            FinanceIGPrice.Parameters(r, sigma, k, 191e19, tau, ka, kb, teta),
            DeltaComponents(219721760e9, -3866085307e9, 6400998901e9),
            PriceComponents(FinanceIGPrice.DTerms(234534132e9, 210643208e9, 222588670e9), FinanceIGPrice.DTerms(2497620356e9, 2473729432e9, 2485674894e9), FinanceIGPrice.DTerms(-1912444114e9, -1936335038e9, -1924389576e9), 8011886525e9, 7874835940e9, 15636440410e9, 124184603e9, 125149677e9, 11220510079e9, 11460108070e9, 21631545344e9, 525967315e9, 521188622e9, 94777528956e9, 191686789846e9, 286464318802e9),
            Payoff(0e9, 13284809408e9)
        );

        // 1800
        tau = WadTime.nYears(WadTime.daysFraction(4, 6));
        (alfa1, alfa2) = FinanceIGDelta._alfas(k, ka, kb, sigma, tau);
        testCases[2] = TestCase(
            v0,
            FinanceIGDelta.Parameters(sigma, k, 18e20, tau, limSup, limInf, alfa1, alfa2),
            FinanceIGPrice.Parameters(r, sigma, k, 18e20, tau, ka, kb, teta),
            DeltaComponents(-2530207318e9, -23550631907e9, 193350845e9),
            PriceComponents(FinanceIGPrice.DTerms(-2516958729e9, -2538327421e9, -2527643075e9), FinanceIGPrice.DTerms(13248589e9, -8120103e9, 2564243e9), FinanceIGPrice.DTerms(-4917353381e9, -4938722073e9, -4928037727e9), 19125549799e9, 18113567314e9, 18542486028e9, 9261417195e9, 9420489243e9, 107110264e9, 107845889e9, 214938269e9, 7790e9, 7758e9, 1472464820482e9, 233588717e9, 1472698409200e9),
            Payoff(1368223868107e9, 0e9)
        );

        // 1900
        tau = WadTime.nYears(WadTime.daysFraction(3, 6));
        (alfa1, alfa2) = FinanceIGDelta._alfas(k, ka, kb, sigma, tau);
        testCases[3] = TestCase(
            v0,
            FinanceIGDelta.Parameters(sigma, k, 19e20, tau, limSup, limInf, alfa1, alfa2),
            FinanceIGPrice.Parameters(r, sigma, k, 19e20, tau, ka, kb, teta),
            DeltaComponents(0e9, -3972291854e9, 4091149226e9),
            PriceComponents(FinanceIGPrice.DTerms(11473615e9, -7032215e9, 2220700e9), FinanceIGPrice.DTerms(2933105367e9, 2914599537e9, 2923852452e9), FinanceIGPrice.DTerms(-2760263383e9, -2778769213e9, -2769516298e9), 9670418287e9, 9528820228e9, 19131925868e9, 33157570e9, 33335109e9, 9562505239e9, 9704893709e9, 19158602248e9, 54135591e9, 53835639e9, 81996805394e9, 82546947057e9, 164543752451e9),
            Payoff(0e9, 0e9)
        );

        // 2200
        tau = WadTime.nYears(WadTime.daysFraction(2, 6));
        (alfa1, alfa2) = FinanceIGDelta._alfas(k, ka, kb, sigma, tau);
        testCases[4] = TestCase(
            v0,
            FinanceIGDelta.Parameters(sigma, k, 22e20, tau, limSup, limInf, alfa1, alfa2),
            FinanceIGPrice.Parameters(r, sigma, k, 22e20, tau, ka, kb, teta),
            DeltaComponents(9702447859e9, -45481e9, 25630083127e9),
            PriceComponents(FinanceIGPrice.DTerms(9711816027e9, 9696706080e9, 9704261053e9), FinanceIGPrice.DTerms(13290069531e9, 13274959584e9, 13282514557e9), FinanceIGPrice.DTerms(6317145354e9, 6302035407e9, 6309590381e9), 0e9, 0e9, 0e9, 0e9, 0e9, 19233186993e9, 22270616137e9, 6e9, 21706711539e9, 19732833493e9, 0e9, 6425809163331e9, 6425809163331e9),
            Payoff(0e9, 6424440250048e9)
        );

        // 1950
        tau = WadTime.nYears(WadTime.daysFraction(1, 6));
        (alfa1, alfa2) = FinanceIGDelta._alfas(k, ka, kb, sigma, tau);
        testCases[5] = TestCase(
            v0,
            FinanceIGDelta.Parameters(sigma, k, 195e19, tau, limSup, limInf, alfa1, alfa2),
            FinanceIGPrice.Parameters(r, sigma, k, 195e19, tau, ka, kb, teta),
            DeltaComponents(2431172316e9, -297632726e9, 15038470863e9),
            PriceComponents(FinanceIGPrice.DTerms(2437796611e9, 2427112265e9, 2432454438e9), FinanceIGPrice.DTerms(7498211246e9, 7487526900e9, 7492869073e9), FinanceIGPrice.DTerms(-2362992694e9, -2373677040e9, -2368334867e9), 146362187e9, 145848833e9, 292210186e9, 0e9, 0e9, 19087088276e9, 19594015471e9, 38329098084e9, 174391980e9, 173769195e9, 83426057e9, 384448704120e9, 384532130178e9),
            Payoff(0e9, 328682929026e9)
        );

        // 3800
        // Note: When the price is very far from the strike near the maturity date (less than 1 hour)
        // the test fails due to ExpOverflow when you're calculating Delta Hedges
        tau = WadTime.nYears(WadTime.daysFraction(1, 1000));
        (alfa1, alfa2) = FinanceIGDelta._alfas(k, ka, kb, sigma, tau);
        testCases[6] = TestCase(
            v0,
            FinanceIGDelta.Parameters(sigma, k, 38e20, tau, limSup, limInf, alfa1, alfa2),
            FinanceIGPrice.Parameters(r, sigma, k, 38e20, tau, ka, kb, teta),
            DeltaComponents(837532924917e9, 0e9, 25632027048e9),
            PriceComponents(FinanceIGPrice.DTerms(837533438033e9, 837532610427e9, 837533024230e9), FinanceIGPrice.DTerms(902863110060e9, 902862282454e9, 902862696257e9), FinanceIGPrice.DTerms(775555514611e9, 775554687005e9, 775555100808e9), 0e9, 0e9, 0e9, 0e9, 0e9, 19233712356e9, 38467427873e9, 0e9, 37493410845e9, 19733372507e9, 0e9, 47435687633232e9, 47435687633232e9),
            Payoff(0e9, 47435683526437e9)
        );



        testCasesNum = 7;
    }

    function testDeltas() public {
        uint256 D_ERR = 4e13;
        uint256 testCasesNumDelta = testCasesNum - 1;
        for (uint256 i = 0; i < testCasesNumDelta; i++) {
            uint256 sigmaTaurtd = FinanceIGDelta._sigmaTaurtd(testCases[i].deltaParams.sigma, testCases[i].deltaParams.tau);
            int256 x = FinanceIGDelta._z(testCases[i].deltaParams.s, testCases[i].deltaParams.k, sigmaTaurtd);

            assertApproxEqAbs(testCases[i].delta.x, x, D_ERR);

            (int256 igDBull, int256 igDBear) = FinanceIGDelta.igDeltas(testCases[i].deltaParams);

            assertApproxEqAbs(testCases[i].delta.igDBull, igDBull, D_ERR);
            assertApproxEqAbs(testCases[i].delta.igDBear, igDBear, D_ERR);
        }
    }

    function testTermsDs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (FinanceIGPrice.DTerms memory ds, FinanceIGPrice.DTerms memory das, FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(testCases[i].priceParams);

            assertApproxEqAbs(testCases[i].price.ds.d1, ds.d1, ERR);
            assertApproxEqAbs(testCases[i].price.ds.d2, ds.d2, ERR);
            assertApproxEqAbs(testCases[i].price.ds.d3, ds.d3, ERR);

            assertApproxEqAbs(testCases[i].price.das.d1, das.d1, ERR);
            assertApproxEqAbs(testCases[i].price.das.d2, das.d2, ERR);
            assertApproxEqAbs(testCases[i].price.das.d3, das.d3, ERR);

            assertApproxEqAbs(testCases[i].price.dbs.d1, dbs.d1, ERR);
            assertApproxEqAbs(testCases[i].price.dbs.d2, dbs.d2, ERR);
            assertApproxEqAbs(testCases[i].price.dbs.d3, dbs.d3, ERR);
        }
    }

    function testPs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (FinanceIGPrice.DTerms memory ds, FinanceIGPrice.DTerms memory das, FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(testCases[i].priceParams);
            FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(ds);
            FinanceIGPrice.NTerms memory nas = FinanceIGPrice.nTerms(das);
            FinanceIGPrice.NTerms memory nbs = FinanceIGPrice.nTerms(dbs);

            uint256 ert = FinanceIGPrice._ert(testCases[i].priceParams.r, testCases[i].priceParams.tau);
            uint256 sdivk = (testCases[i].priceParams.s).wdiv(testCases[i].priceParams.k);

            {
                FinanceIGPrice.PriceParts memory ps = FinanceIGPrice.pBullParts(testCases[i].priceParams, ert, sdivk, ns, nbs);
                assertApproxEqAbs(testCases[i].price.pBull1, ps.p1, ERR);
                assertApproxEqAbs(testCases[i].price.pBull2, ps.p2, ERR);
                assertApproxEqAbs(testCases[i].price.pBull3, ps.p3, ERR);
                assertApproxEqAbs(testCases[i].price.pBull4, ps.p4, ERR);
                assertApproxEqAbs(testCases[i].price.pBull5, ps.p5, ERR);
            }

            {
                FinanceIGPrice.PriceParts memory ps = FinanceIGPrice.pBearParts(testCases[i].priceParams, ert, sdivk, ns, nas);
                assertApproxEqAbs(testCases[i].price.pBear1, ps.p1, ERR);
                assertApproxEqAbs(testCases[i].price.pBear2, ps.p2, ERR);
                assertApproxEqAbs(testCases[i].price.pBear3, ps.p3, ERR);
                assertApproxEqAbs(testCases[i].price.pBear4, ps.p4, ERR);
                assertApproxEqAbs(testCases[i].price.pBear5, ps.p5, ERR);
            }
        }
    }

    function testPrices() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (uint256 pBull, uint256 pBear) = FinanceIGPrice.igPrices(testCases[i].priceParams);
            assertApproxEqAbs(testCases[i].price.pBull, testCases[i].v0.wmul(pBull), 6e16);
            assertApproxEqAbs(testCases[i].price.pBear, testCases[i].v0.wmul(pBear), 6e16);
        }
    }

    function testPayoff() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (uint256 poBull, uint256 poBear) = FinanceIGPayoff.igPayoffPerc(testCases[i].priceParams.s, testCases[i].priceParams.k, testCases[i].priceParams.ka, testCases[i].priceParams.kb, testCases[i].priceParams.teta);
            assertApproxEqAbs(testCases[i].payoff.igBull, testCases[i].v0.wmul(poBull), ERR);
            assertApproxEqAbs(testCases[i].payoff.igBear, testCases[i].v0.wmul(poBear), ERR);
        }
    }

    function testLiquidityRange() public {
        uint256 volatility = 5e17;
        uint256 volatilityMultiplier = AmountsMath.wrap(2);
        uint256 dailyMaturity = AmountsMath.wrap(1) / 365;

        // Fixed maturity, change strike price:
        _checkLiquidityRange(LiquidityRange(1800e18, volatility, volatilityMultiplier, dailyMaturity, 1708206983329e9, 1896725649538e9));
        _checkLiquidityRange(LiquidityRange(1900e18, volatility, volatilityMultiplier, dailyMaturity, 1803107371292e9, 2002099296734e9));
        _checkLiquidityRange(LiquidityRange(1910e18, volatility, volatilityMultiplier, dailyMaturity, 1812597410088e9, 2012636661454e9));
        _checkLiquidityRange(LiquidityRange(1950e18, volatility, volatilityMultiplier, dailyMaturity, 1850557565273e9, 2054786120333e9));
        _checkLiquidityRange(LiquidityRange(2200e18, volatility, volatilityMultiplier, dailyMaturity, 2087808535180e9, 2318220238324e9));
        _checkLiquidityRange(LiquidityRange(3800e18, volatility, volatilityMultiplier, dailyMaturity, 3606214742584e9, 4004198593469e9));
        // Fixed strike price, change maturity:
        _checkLiquidityRange(LiquidityRange(1900e18, volatility, volatilityMultiplier, dailyMaturity * 7, 1654285069345e9, 2182211558876e9));
        _checkLiquidityRange(LiquidityRange(1900e18, volatility, volatilityMultiplier, dailyMaturity * 21, 1494797747280e9, 2415042440737e9));
        _checkLiquidityRange(LiquidityRange(1900e18, volatility, volatilityMultiplier, dailyMaturity * 30, 1426412850588e9, 2530824086807e9));

        // ToDo: check corner cases
    }

    function _checkLiquidityRange(LiquidityRange memory params) internal {
        (uint256 kA, uint256 kB) = FinanceIGPrice.liquidityRange(FinanceIGPrice.LiquidityRangeParams(params.strike, params.volatility, params.volatilityMultiplier, params.yearsOfMaturity));
        uint256 maxError = 1e9;
        assertApproxEqAbs(params.kA, kA, maxError);
        assertApproxEqAbs(params.kB, kB, maxError);
    }

    function testTradeVolatility() public {
        uint256 baselineVolatility = 70e16; // 0.7 Wad == 70 %
        uint256 utilizationRateFactor = 2e18; // 2 Wad
        uint256 timeDecay = 25e16; // 0.25 Wad
        uint256 utilizationRate = 50e16; // 0.5 Wad == 50 %

        // Test time decay effect:
        uint256 initialTime = 0;
        uint256 maturity = initialTime + 7 days;
        uint256 time = initialTime;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 787500e12));
        time = time + 1 days;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 759375e12));
        time = time + 1 days;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 731250e12));
        time = time + 1 days;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 703125e12));
        time = time + 1 days;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 675000e12));

        // ToDo: check corner cases
    }

    function _checkTradeVolatility(TradeVolatility memory params) internal {
        uint256 volatility = FinanceIGPrice.tradeVolatility(FinanceIGPrice.TradeVolatilityParams(params.baselineVolatility, params.utilizationRateFactor, params.timeDecay, params.utilizationRate, params.maturity, params.initialTime));
        uint256 maxError = 1e11;
        assertApproxEqAbs(params.volatility, volatility, maxError);
    }
}
