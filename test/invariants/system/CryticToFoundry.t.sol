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

    /**
        Parameters 4
        vaultPnl -1186598
        lpPnl 0
     */
    function test_3() public {
        vm.warp(block.timestamp + 60420);
        deposit(2757856024891);
        vm.warp(block.timestamp + 32108);
        callAdminFunction(105037294159547526916489525899537646393540900804206336260338125015606844443,2349631377542172248668800963390341172549367658466638483973998550480267959);
        callAdminFunction(93432219226529644030285479139703783906017019188906152283520,0);
        callAdminFunction(181597564746001288112248952591229437726504065471067703398997165141,19846515109023960111825331431116748845896575751676634138047767);
        buyBear(44357228027576917546402860714237895212857522068972994973317518);
        vm.warp(block.timestamp + 66);
        sellBear(11612441366777744948635299090481579671431726502020107311182467);
    }
}
