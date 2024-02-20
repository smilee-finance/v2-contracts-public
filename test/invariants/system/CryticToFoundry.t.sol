// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {console} from "forge-std/console.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {

    /**
        IMPORTANT!
        Before run this test make sure to select the right scenario
        `cp test/invariants/utils/scenarios/Parameters_*.sol test/invariants/utils/scenarios/Parameters.sol`
     */

    function setUp() public {
        setup();
    }

    /// TEST WITH NEW SCENARIOS SET UP

    /**
        scenario 6
        Error: IG_14: For each buy / sell, IG premium >= IG payoff for a given price; Both calculated with price oracle
        Error: a >= b not satisfied [uint]
            Value a: 18897304744
            Value b: 18897304745
        FIXED: Introduce tollerance
        NOW FAIL ASSUME
    */
    function testFail_1() public {
        vm.warp(block.timestamp + 269841);
        callAdminFunction(5607587871908216405763951847714077393111042645929048005615840241057835214505,59654271350141131221907402743453494299292882906966176538190917032912939709500);
        vm.warp(block.timestamp + 539764);
        callAdminFunction(347437083999162433888837515002539729507623920905942392673140735,85190047576838501505646443170323552574165036916370217963769483351651863619542);
        vm.warp(block.timestamp + 2000);
        callAdminFunction(115792089237316195423570985008687907853269984665640564039397789302205157117674,115792089237316195423570985008687907853269984665640564039439135702944693225106);
        vm.warp(block.timestamp + 32562);
        buySmilee(75746529874280507437901860185272850970076156487803951298666641553294593251423);
        vm.warp(block.timestamp + 235975);
        callAdminFunction(9920141303379037982868003213532632591227475842257952173276861006939017479942,30699997304819786786856458479381130733496238137275429698580461944011914505750);
        buyBear(15);
        vm.warp(block.timestamp + 39626);
        sellBear(770651425980145124863019537085913315868240266551810532803144923041381631773);
    }

    /**
        scenario 4
        Price goes to 1e-9
        kA && kB too low, vault get paused PausedForFinanceApproximation()
     */
    function test_2() public {
        callAdminFunction(3237718079345155102596977565293135294949081376636977917802446534327,0);
        vm.warp(block.timestamp + 124117);
        callAdminFunction(938954416,26687785706012934596669443676619534887163690062779701690349395237800636785);
        vm.warp(block.timestamp + 49915);
        callAdminFunction(534149955705393442044995023299632473722604709326934600853264931116981500,34296178893);
    }

    function test_28() public {
    deposit(812870960728227484);
    callAdminFunction(1511610659193518031426431653186024674225125534647314379845149750819,510185651478062688580191808681885501755315866103988431614978114178);
    vm.warp(block.timestamp + 88915);
    callAdminFunction(3623708084350930395975976413989672956513777569597106486235951338142379,4082446757041140532454664397786647062463302814056876477581246504665649643);
    buyBull(0);
    callAdminFunction(374497518371728331551778773946400961302213034390924771266345,849136325537371672980380596350583896402217096699195792975636483055);
    sellBull(138873235318212070661920463869414865342189751049626);
}
}
