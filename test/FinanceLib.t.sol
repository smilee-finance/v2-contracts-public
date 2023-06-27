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
        int256 d1;
        int256 d2;
        int256 d3;
        uint256 c1;
        uint256 c2;
        uint256 c3;
        uint256 c4;
        uint256 c5;
        uint256 c6;
        uint256 c7;
        int256 igDUp;
        int256 igDDown;
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

    uint256 v0 = 1e23; // 1,000,000 (1M)
    uint256 r = 3e16; // 0.02 (2 %)
    uint256 sigma = 5e17; // 0.5 (50 %)
    mapping(uint256 => TestCase) testCases;
    uint256 testCasesNum = 0;
    uint256 teta;

    /**
        @dev Accepted delta on comparisons (up to 5e-6)
        This is mainly due to limitations of `Gaussian.cdf()` computation error.
     */
    uint256 constant ERR = 1e12;

    function setUp() public {
        uint256 ka = 18e20;
        uint256 kb = 20e20;
        teta = Finance._teta(19e20, ka, kb);

        // current price: 1900
        testCases[0] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 19e20, 19e20, WadTime.nYears(WadTime.daysFraction(1, 1)), teta, ka, kb),
            DeltaComponents(16985368844e9, 16961477920e9, 16973423382e9, 0e9, 250000e9, 0, 204105e9, 0, 250000e9, 204105e9, 45895077883e9, 0),
            PriceComponents(Finance.DTerms(16226142e9, -9945055e9, 3140544e9), Finance.DTerms(2082131766e9, 2055960569e9, 2069046168e9), Finance.DTerms(-1943687885e9, -1969859081e9, -1956773483e9), 9692368857e9, 9492356948e9, 18441880301e9, 368838939e9, 372383691e9, 9539764291e9, 9741356989e9, 18310708044e9, 486787268e9, 481992674e9, 162287400074e9, 163329325284e9, 325616725358e9),
            Payoff(0, 0)
        );

        // 1910
        testCases[1] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 19e20, 191e19, WadTime.nYears(WadTime.daysFraction(5, 6)), teta, ka, kb),
            DeltaComponents(-463445429364e9, -463466798056e9, -463456113710e9, 0, 0, 0, 0, 0, 250000e9, 35352675e9, 0, -35102675401250e9),
            PriceComponents(Finance.DTerms(234534132e9, 210643208e9, 222588670e9), Finance.DTerms(2497620356e9, 2473729432e9, 2485674894e9), Finance.DTerms(-1912444114e9, -1936335038e9, -1924389576e9), 8011886525e9, 7874835940e9, 15636440410e9, 124184603e9, 125149677e9, 11220510079e9, 11460108070e9, 21631545344e9, 525967315e9, 521188622e9, 94777528956e9, 191686789846e9, 286464318802e9),
            Payoff(0, 0)
        );

        // 1800
        testCases[2] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 19e20, 18e20, WadTime.nYears(WadTime.daysFraction(4, 6)), teta, ka, kb),
            DeltaComponents(-15534749771e9, -15553255601e9, -15544002686e9, 0, 0, 0, 0, 0, 250000e9, 288659e9, 0, -38658822933e9),
            PriceComponents(Finance.DTerms(-2516958729e9, -2538327421e9, -2527643075e9), Finance.DTerms(13248589e9, -8120103e9, 2564243e9), Finance.DTerms(-4917353381e9, -4938722073e9, -4928037727e9), 19125549799e9, 18113567314e9, 18542486028e9, 9261417195e9, 9420489243e9, 107110264e9, 107845889e9, 214938269e9, 7790e9, 7758e9, 1472464820482e9, 233588717e9, 1472698409200e9),
            Payoff(0, 0)
        );

        // 1900
        testCases[3] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 19e20, 19e20, WadTime.nYears(WadTime.daysFraction(3, 6)), teta, ka, kb),
            DeltaComponents(338847089e9, 323737142e9, 331292116e9, 6232393e9, 158159e9, 6232393e9, 157049e9, 12464787e9, 250000e9, 249368e9, 1110429038e9, -478368890e9),
            PriceComponents(Finance.DTerms(11473615e9, -7032215e9, 2220700e9), Finance.DTerms(2933105367e9, 2914599537e9, 2923852452e9), Finance.DTerms(-2760263383e9, -2778769213e9, -2769516298e9), 9670418287e9, 9528820228e9, 19131925868e9, 33157570e9, 33335109e9, 9562505239e9, 9704893709e9, 19158602248e9, 54135591e9, 53835639e9, 81996805394e9, 82546947057e9, 164543752451e9),
            Payoff(0, 0)
        );

        // 2200
        testCases[4] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 19e20, 22e20, WadTime.nYears(WadTime.daysFraction(2, 6)), teta, ka, kb),
            DeltaComponents(-462951288e9, -473635634e9, -468293461e9, 8386143e9, 80425e9, 8386143e9, 80146e9, 16772287e9, 250000e9, 250623e9, 278957332e9, -901590214e9),
            PriceComponents(Finance.DTerms(9711816027e9, 9696706080e9, 9704261053e9), Finance.DTerms(13290069531e9, 13274959584e9, 13282514557e9), Finance.DTerms(6317145354e9, 6302035407e9, 6309590381e9), 0e9, 0e9, 0e9, 0e9, 0e9, 19233186993e9, 22270616137e9, 6e9, 21706711539e9, 19732833493e9, 0e9, 6425809163331e9, 6425809163331e9),
            Payoff(0, 0)
        );

        // 1950
        testCases[5] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 19e20, 195e19, WadTime.nYears(WadTime.daysFraction(1, 6)), teta, ka, kb),
            DeltaComponents(6196921e9, -4487425e9, 854748e9, 9334559e9, 125618e9, 9334559e9, 125083e9, 18669117e9, 250000e9, 249995e9, 535156764e9, -530447904e9),
            PriceComponents(Finance.DTerms(2437796611e9, 2427112265e9, 2432454438e9), Finance.DTerms(7498211246e9, 7487526900e9, 7492869073e9), Finance.DTerms(-2362992694e9, -2373677040e9, -2368334867e9), 146362187e9, 145848833e9, 292210186e9, 0e9, 0e9, 19087088276e9, 19594015471e9, 38329098084e9, 174391980e9, 173769195e9, 83426057e9, 384448704120e9, 384532130178e9),
            Payoff(0, 0)
        );

        // 3800
        testCases[6] = TestCase(
            v0,
            Finance.DeltaPriceParams(r, sigma, 19e20, 38e20, WadTime.nYears(WadTime.daysFraction(1, 1000)), teta, ka, kb),
            DeltaComponents(6196921e9, -4487425e9, 854748e9, 9334559e9, 125618e9, 9334559e9, 125083e9, 18669117e9, 250000e9, 249995e9, 535156764e9, -530447904e9),
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

    // function testTermsCs() public {
    //     for (uint256 i = 0; i < testCasesNum; i++) {
    //         (int256 d1, int256 d2, int256 d3, uint256 sigmaTaurtd) = Finance.ds(testCases[i].params);
    //         uint256 sigmaTaurtdPi2rtd = sigmaTaurtd.wmul(Finance.PI2_RTD);
    //         Finance.DeltaIGAddends memory cs_ = Finance.cs(testCases[i].params, d1, d2, d3, sigmaTaurtdPi2rtd);

    //         assertApproxEqAbs(testCases[i].delta.c1, cs_.c1, ERR);
    //         assertApproxEqAbs(testCases[i].delta.c2, cs_.c2, ERR);
    //         assertApproxEqAbs(testCases[i].delta.c3, cs_.c3, ERR);
    //         assertApproxEqAbs(testCases[i].delta.c4, cs_.c4, ERR);
    //         assertApproxEqAbs(testCases[i].delta.c5, cs_.c5, ERR);
    //         assertApproxEqAbs(testCases[i].delta.c6, cs_.c6, ERR);
    //         assertApproxEqAbs(testCases[i].delta.c7, cs_.c7, ERR);
    //     }
    // }

    // function testDeltas() public {
    //     for (uint256 i = 0; i < testCasesNum; i++) {
    //         (int256 igDUp, int256 igDDown) = Finance.igDeltas(testCases[i].params);

    //         igDUp = (int256(testCases[i].v0) * igDUp) / (10 ** 18);
    //         igDDown = (int256(testCases[i].v0) * igDDown) / (10 ** 18);

    //         assertApproxEqAbs(testCases[i].delta.igDUp, igDUp, 1e13);
    //         assertApproxEqAbs(testCases[i].delta.igDDown, igDDown, 1e13);
    //     }
    // }

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
