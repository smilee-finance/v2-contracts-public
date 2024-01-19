// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    /**
        InsufficientLiquidity("_beforeRollEpoch()::_state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs - baseTokens")
     */
    function test_01() public {
        vm.warp(block.timestamp + 15790);
        deposit(753780546426345955413931157775832410930106);
        vm.warp(block.timestamp + 99568);
        callAdminFunction(
            42058281372472454962807870485987314089146113209336814108751744773162,
            94586397242477222477402127700118551742513176453076716598512929824532
        );
        callAdminFunction(
            42520534683753573551241396107604603541460636312716439758751609768970802983,
            3722225677400697555411638394426114732703479860560469910417771863973355293
        );
        initiateWithdraw(744596680349883318272300);
        vm.warp(block.timestamp + 59060);
        callAdminFunction(10, 2592262954105063);
    }

    /**
        Delta hedge failing on buy, requiring more sidetokens than can be bought
        InsufficientInput()
        // should be InsufficientLiquidity(bytes4(keccak256("_buySideTokens()")));
     */
    function test_2() public {
        vm.warp(block.timestamp + 65280);
        deposit(53660751925402942071444234319586906678597225057891828354971127042736941450);
        vm.warp(block.timestamp + 334984);
        callAdminFunction(2114683348797038701721556498398548843679748884308985742881043097095705417104, 2);
        vm.warp(block.timestamp + 29113);
        buyBull(10616969518659123581099617347038970877541454535286915844038626259034985343772);
    }

    /**
        LockedLiquidity is 2 and buy can't work for price 0 (accept PriceZero in GENERAL_6)
     */
    function test_3() public {
        deposit(1384233657759163422);
        vm.warp(block.timestamp + 88110);
        callAdminFunction(17940346325083685200204339517280845868355573746869169508,6389732087006262645396293163980224686774072721133376504436555850860886183);
        initiateWithdraw(1430159095897988946927574128699781560565324895279480372864710098001599);
        callAdminFunction(217847293719094250790364819281794297976580624965956725035984422847437651293,3);
        vm.warp(block.timestamp + 87585);
        callAdminFunction(451137554874517463134337297733751786480587123398856542130420047853207502805,0);
        buySmilee(156411199246107622137928077703900749641316263797149686496304161433518);
    }

    /**
        Opposite of test_2 -> Insufficient sideToken InsufficientLiquidity
        Deposit = 422874763096089738138323191
        Buy amount = 204235032083126070892368654
        Price = 449763326627668207959
        Payoff = 91645114104417003886950356788
        Amount SideToken to sell = 211337912616092553207414960
        SideToken = 211337912616092503274682387
     */
    function test_4() public {
        deposit(60422874763096089738138323190);
        vm.warp(block.timestamp + 88083);
        callAdminFunction(2132145331917968010594835,16284122588879201369169830701800346181174);
        buySmilee(1707506151294058898106476209242951773);
        callAdminFunction(18827006011594566056867083291411443603897833,29891880245160202434953218754986665198581311070963);
        sellSmilee(0);
    }

    /**
        Similar to test_4
     */
    function test_5() public {
        deposit(2718364611567106372819098024200);
        vm.warp(block.timestamp + 87063);
        callAdminFunction(26735622668226734088,1026294980344217368020213225200567899815000);
        callAdminFunction(126524595298907413077460400435114538180333054143,175040526175012183925390216430334634667371331510678);
        buyBull(36686119904715600032666016466265016498086465088748897033858380399762);
        sellBull(88440000);
    }
}
