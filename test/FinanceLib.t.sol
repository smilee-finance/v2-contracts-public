// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {FixedPointMathLib} from "../src/lib/FixedPointMathLib.sol";

import {Gaussian} from "@solstat/Gaussian.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {AmountsMath} from "../src/lib/AmountsMath.sol";
import {Finance} from "../src/lib/Finance.sol";
import {WadTime} from "../src/lib/WadTime.sol";

contract FinanceLibTest is Test {
    using AmountsMath for uint256;

    struct DeltaComponents {
        int256 x;
        int256 bearAtanArg;
        int256 bullAtanArg;
        int256 igDBear;
        int256 igDBull;
    }

    struct PriceComponents {
        Finance.DTerms ds;
        Finance.DTerms das;
        Finance.DTerms dbs;
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
        uint256 igUp;
        uint256 igDown;
    }

    struct TestCase {
        // inputs
        uint256 v0;
        Finance.DeltaPriceParams params;
        // results
        DeltaComponents delta;
        PriceComponents price;
        Payoff payoff;
    }

    uint256 v0 = 1e23; // 100,000 (100 K)
    uint256 r = 3e16; // 0.02 (2 %)
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
        uint256 teta = Finance._teta(19e20, ka, kb);
        (int256 limSup, int256 limInf) = Finance.lims(k, ka, kb, teta);
        uint256 T = WadTime.nYears(WadTime.daysFraction(1, 1));
        (int256 alfa1, int256 alfa2) = Finance._alfas(k, ka, kb, Finance._sigmaTaurtd(sigma, T));

        assertApproxEqAbs(-277394026339900, limInf, ERR);
        assertApproxEqAbs(256320270477425, limSup, ERR);
        assertApproxEqAbs(-2065905623981380000, alfa1, ERR);
        assertApproxEqAbs(1959914026616160000, alfa2, ERR);

        // current price: 1900
        tau = WadTime.nYears(WadTime.daysFraction(1, 1));
        testCases[0] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, k, 19e20, tau, ka, kb, teta, limSup, limInf, alfa1, alfa2),
            DeltaComponents(0e9, 0e9, 0e9, 0e9, 0e9),
            PriceComponents(Finance.DTerms(16226142e9, -9945055e9, 3140544e9), Finance.DTerms(2082131766e9, 2055960569e9, 2069046168e9), Finance.DTerms(-1943687885e9, -1969859081e9, -1956773483e9), 9692368857e9, 9492356948e9, 18441880301e9, 368838939e9, 372383691e9, 9539764291e9, 9741356989e9, 18310708044e9, 486787268e9, 481992674e9, 162287400074e9, 163329325284e9, 325616725358e9),
            Payoff(0, 0)
        );

        // 1910
        tau = WadTime.nYears(WadTime.daysFraction(5, 6));
        testCases[1] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, k, 191e19, tau, ka, kb, teta, limSup, limInf, alfa1, alfa2),
            DeltaComponents(219721760e9, 231726752e9, 219657339e9, 0e9, 3528302790e9),
            PriceComponents(Finance.DTerms(234534132e9, 210643208e9, 222588670e9), Finance.DTerms(2497620356e9, 2473729432e9, 2485674894e9), Finance.DTerms(-1912444114e9, -1936335038e9, -1924389576e9), 8011886525e9, 7874835940e9, 15636440410e9, 124184603e9, 125149677e9, 11220510079e9, 11460108070e9, 21631545344e9, 525967315e9, 521188622e9, 94777528956e9, 191686789846e9, 286464318802e9),
            Payoff(0, 0)
        );

        // 1800
        tau = WadTime.nYears(WadTime.daysFraction(4, 6));
        testCases[2] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, k, 18e20, tau, ka, kb, teta, limSup, limInf, alfa1, alfa2),
            DeltaComponents(-2530207318e9, -3772441373e9, -5372928641e9, -23163471485e9, 0e9),
            PriceComponents(Finance.DTerms(-2516958729e9, -2538327421e9, -2527643075e9), Finance.DTerms(13248589e9, -8120103e9, 2564243e9), Finance.DTerms(-4917353381e9, -4938722073e9, -4928037727e9), 19125549799e9, 18113567314e9, 18542486028e9, 9261417195e9, 9420489243e9, 107110264e9, 107845889e9, 214938269e9, 7790e9, 7758e9, 1472464820482e9, 233588717e9, 1472698409200e9),
            Payoff(0, 0)
        );

        // 1900
        tau = WadTime.nYears(WadTime.daysFraction(3, 6));
        testCases[3] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, k, 19e20, tau, ka, kb, teta, limSup, limInf, alfa1, alfa2),
            DeltaComponents(0e9, 0e9, 0e9, 0e9, 0e9),
            PriceComponents(Finance.DTerms(11473615e9, -7032215e9, 2220700e9), Finance.DTerms(2933105367e9, 2914599537e9, 2923852452e9), Finance.DTerms(-2760263383e9, -2778769213e9, -2769516298e9), 9670418287e9, 9528820228e9, 19131925868e9, 33157570e9, 33335109e9, 9562505239e9, 9704893709e9, 19158602248e9, 54135591e9, 53835639e9, 81996805394e9, 82546947057e9, 164543752451e9),
            Payoff(0, 0)
        );

        // 2200
        tau = WadTime.nYears(WadTime.daysFraction(2, 6));
        testCases[4] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, k, 22e20, tau, ka, kb, teta, limSup, limInf, alfa1, alfa2),
            DeltaComponents(9702447859e9, 135416166317e9, 111881792701e9, 0e9, 25486181863e9),
            PriceComponents(Finance.DTerms(9711816027e9, 9696706080e9, 9704261053e9), Finance.DTerms(13290069531e9, 13274959584e9, 13282514557e9), Finance.DTerms(6317145354e9, 6302035407e9, 6309590381e9), 0e9, 0e9, 0e9, 0e9, 0e9, 19233186993e9, 22270616137e9, 6e9, 21706711539e9, 19732833493e9, 0e9, 6425809163331e9, 6425809163331e9),
            Payoff(0, 0)
        );

        // 1950
        tau = WadTime.nYears(WadTime.daysFraction(1, 6));
        testCases[5] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, k, 195e19, tau, ka, kb, teta, limSup, limInf, alfa1, alfa2),
            DeltaComponents(2431172316e9, 5023864010e9, 3546214303e9, 0e9, 21147001461e9),
            PriceComponents(Finance.DTerms(2437796611e9, 2427112265e9, 2432454438e9), Finance.DTerms(7498211246e9, 7487526900e9, 7492869073e9), Finance.DTerms(-2362992694e9, -2373677040e9, -2368334867e9), 146362187e9, 145848833e9, 292210186e9, 0e9, 0e9, 19087088276e9, 19594015471e9, 38329098084e9, 174391980e9, 173769195e9, 83426057e9, 384448704120e9, 384532130178e9),
            Payoff(0, 0)
        );

        // 3800
        tau = WadTime.nYears(WadTime.daysFraction(1, 1000));
        testCases[6] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, k, 38e20, tau, ka, kb, teta, limSup, limInf, alfa1, alfa2),
            DeltaComponents(837532924917e9, 73056983092042700e9, 72881617741962600e9, 0e9, 25632026824e9),
            PriceComponents(Finance.DTerms(837533438033e9, 837532610427e9, 837533024230e9), Finance.DTerms(902863110060e9, 902862282454e9, 902862696257e9), Finance.DTerms(775555514611e9, 775554687005e9, 775555100808e9), 0e9, 0e9, 0e9, 0e9, 0e9, 19233712356e9, 38467427873e9, 0e9, 37493410845e9, 19733372507e9, 0e9, 47435687633232e9, 47435687633232e9),
            Payoff(0, 0)
        );

        testCasesNum = 7;
    }

    function testTermsDs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (Finance.DTerms memory ds, Finance.DTerms memory das, Finance.DTerms memory dbs) = Finance.dTerms(testCases[i].params);

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

    function testDeltas() public {
        uint256 D_ERR = 4e13;

        for (uint256 i = 0; i < testCasesNum; i++) {
            uint256 sigmaTaurtd = Finance._sigmaTaurtd(testCases[i].params.sigma, testCases[i].params.tau);
            int256 x = Finance._x(testCases[i].params.s, testCases[i].params.k, sigmaTaurtd);
            (int256 bullAtanArg, int256 bearAtanArg) = Finance.atanArgs(x, testCases[i].params.alfa1, testCases[i].params.alfa2);

            assertApproxEqAbs(testCases[i].delta.x, x, D_ERR);
            assertApproxEqAbs(testCases[i].delta.bullAtanArg, bullAtanArg, D_ERR);
            assertApproxEqAbs(testCases[i].delta.bearAtanArg, bearAtanArg, D_ERR);

            (int256 igDBull, int256 igDBear) = Finance.igDeltas(testCases[i].params);

            igDBull = (int256(testCases[i].v0) * igDBull) / 1e18;
            igDBear = (int256(testCases[i].v0) * igDBear) / 1e18;

            assertApproxEqAbs(testCases[i].delta.igDBull, igDBull, D_ERR);
            assertApproxEqAbs(testCases[i].delta.igDBear, igDBear, D_ERR);
        }
    }

    function testPs() public {
        for (uint256 i = 0; i < testCasesNum; i++) {
            (Finance.DTerms memory ds, Finance.DTerms memory das, Finance.DTerms memory dbs) = Finance.dTerms(testCases[i].params);
            Finance.NTerms memory ns = Finance.nTerms(ds);
            Finance.NTerms memory nas = Finance.nTerms(das);
            Finance.NTerms memory nbs = Finance.nTerms(dbs);

            uint256 ert = Finance._ert(testCases[i].params.r, testCases[i].params.tau);
            uint256 sdivk = (testCases[i].params.s).wdiv(testCases[i].params.k);

            {
                Finance.PriceParts memory ps = Finance.pBullParts(testCases[i].params, ert, sdivk, ns, nbs);
                assertApproxEqAbs(testCases[i].price.pBull1, ps.p1, ERR);
                assertApproxEqAbs(testCases[i].price.pBull2, ps.p2, ERR);
                assertApproxEqAbs(testCases[i].price.pBull3, ps.p3, ERR);
                assertApproxEqAbs(testCases[i].price.pBull4, ps.p4, ERR);
                assertApproxEqAbs(testCases[i].price.pBull5, ps.p5, ERR);
            }

            {
                Finance.PriceParts memory ps = Finance.pBearParts(testCases[i].params, ert, sdivk, ns, nas);
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
            (uint256 pBull, uint256 pBear) = Finance.igPrices(testCases[i].params);
            assertApproxEqAbs(testCases[i].price.pBull, testCases[i].v0.wmul(pBull), 6e16);
            assertApproxEqAbs(testCases[i].price.pBear, testCases[i].v0.wmul(pBear), 6e16);
        }
    }

    // function testPayoff() public {
    //     for (uint256 i = 0; i < testCasesNum; i++) {
    //         (uint256 poUp, uint256 poDown) = Finance.igPayoffPerc(testCases[i].params.s, testCases[i].params.k);
    //         assertApproxEqAbs(testCases[i].payoff.igUp, poUp, ERR);
    //         assertApproxEqAbs(testCases[i].payoff.igDown, poDown, ERR);
    //     }
    // }
}
