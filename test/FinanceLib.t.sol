// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {FixedPointMathLib} from "../src/lib/FixedPointMathLib.sol";

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {AmountsMath} from "../src/lib/AmountsMath.sol";
import {Finance} from "../src/lib/Finance.sol";
import {WadTime} from "../src/lib/WadTime.sol";
import {Normal} from "../src/lib/Normal.sol";

contract FinanceLibTest is Test {
    using AmountsMath for uint256;
    uint256 r = 2e16; // 0.02 or 2%
    uint256 sigma = 5e17; // 0.5 or 50%

    function setUp() public {}

    /// @dev Accepted delta on comparisons (up to 0.0001)
    uint256 constant ERR = 1e14;

    function testTermsDs_1() public {
        uint256 K = 2e21; // 2000 strike price
        uint256 S = 3e21; // 3000 current price
        uint256 tau = WadTime.nYears(WadTime.daysFraction(5, 6)); // 5/6 of a day

        (int256 d1, int256 d2, int256 d3, ) = Finance.ds(Finance.DeltaIGParams(r, sigma, K, S, tau));

        assertApproxEqAbs(169854e14, d1, ERR);
        assertApproxEqAbs(169615e14, d2, ERR);
        assertApproxEqAbs(169734e14, d3, ERR);
    }

    function testTermsDs_2() public {
        uint256 K = 2e21; // 2000 strike price
        uint256 S = 1e17; // 0.1 current price
        uint256 tau = WadTime.nYears(WadTime.daysFraction(4, 6)); // 4/6 of a day

        (int256 d1, int256 d2, int256 d3, ) = Finance.ds(Finance.DeltaIGParams(r, sigma, K, S, tau));

        assertApproxEqAbs(-4634454e14, d1, ERR);
        assertApproxEqAbs(-4634668e14, d2, ERR);
        assertApproxEqAbs(-4634561e14, d3, ERR);
    }

    function testTermsDs_3() public {
        uint256 K = 2e21; // 2000 strike price
        uint256 S = 15e20; // 1500 current price
        uint256 tau = WadTime.nYears(WadTime.daysFraction(1, 2)); // 1/2 of a day

        (int256 d1, int256 d2, int256 d3, ) = Finance.ds(Finance.DeltaIGParams(r, sigma, K, S, tau));

        assertApproxEqAbs(-155347e14, d1, ERR);
        assertApproxEqAbs(-155533e14, d2, ERR);
        assertApproxEqAbs(-155440e14, d3, ERR);
    }

    function testTermsCs_1() public {
        uint256 K = 2e21; // 2000 strike price
        uint256 S = 3e21; // 3000 current price
        uint256 tau = WadTime.nYears(WadTime.daysFraction(5, 6)); // 5/6 of a day

        Finance.DeltaIGParams memory params = Finance.DeltaIGParams(r, sigma, K, S, tau);

        (int256 d1, int256 d2, int256 d3, uint256 sigmaTaurtd) = Finance.ds(params);
        uint256 sigmaTaurtdPi2rtd = sigmaTaurtd.wmul(Finance.PI2_RTD);
        (uint256 c1, uint256 c2, uint256 c3, uint256 c4, uint256 c5) = Finance.cs(
            params,
            d1,
            d2,
            d3,
            sigmaTaurtdPi2rtd
        );

        // console.log(c1);
        // console.log(c2);
        // console.log(c3);
        // console.log(c4);
        // console.log(c5);
    }

    // function testDeltas() public {
    //     uint256 K = 2e21; // 2000 strike price
    //     uint256 S = 3e21; // 3000 current price
    //     uint256 tau = WadTime.nYears(WadTime.daysFraction(5, 6)); // 5/6 of a day

    //     (int256 igDUp, int256 igDDown) = Finance.igDeltas(r, sigma, K, S, tau);

    //     assertApproxEqAbs(4590e16, igDUp, ERR);
    //     assertApproxEqAbs(0, igDDown, ERR);
    // }
}
