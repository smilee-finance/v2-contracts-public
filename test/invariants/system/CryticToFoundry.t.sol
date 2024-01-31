// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {console} from "forge-std/console.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    /**
        InsufficientLiquidity("_beforeRollEpoch()::_state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs - baseTokens")
     */
    function testFail_01() public {
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
    // function testFail_2() public {
    //     vm.warp(block.timestamp + 65280);
    //     deposit(53660751925402942071444234319586906678597225057891828354971127042736941450);
    //     vm.warp(block.timestamp + 334984);
    //     callAdminFunction(2114683348797038701721556498398548843679748884308985742881043097095705417104, 2);
    //     vm.warp(block.timestamp + 29113);
    //     buyBull(10616969518659123581099617347038970877541454535286915844038626259034985343772);
    // }

    /**
        LockedLiquidity is 2 and buy can't work for price 0 (accept PriceZero in GENERAL_6)
     */
    function testFail_3() public {
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

        Amount to sell is greater then sideToken amount, sell all. See FinanceIGDelta:deltaHedgeAmount()
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

    /**
        InsufficientLiquidity
    */
    function testFail_6() public {
        deposit(62371730870697728150);
        vm.warp(block.timestamp + 88417);
        callAdminFunction(91191509274284818089195485045059220520329531160155857031,560546320870737139457170187497346984605561619303321602565095);
        callAdminFunction(1543512734265866555972778732410098471,83381555156362781964048013826851);
        buySmilee(0);
        sellSmilee(261491956713171412);
    }

    /**
        FINANCE_IG:253 t_previous non veniva dentro resettato alla rollEpoch -> FIX: setter fuori dall'IF
     */
    function test_7() public {
        deposit(33386845615680520816062583326021756675779207876119476425502802489475652); // 122_673_539.22654901
        vm.warp(block.timestamp + 102804); // time elapsed 16405
        callAdminFunction(1416240688421465261954060731256103985292458851080778370120592320503,5768613114260765327218982425636567210098946651861166084142136755276);
        buySmilee(8931270579803913598420817361141420851150235213703576221915573794); // 54_950_261.933064535
        vm.warp(block.timestamp + 337667); // time elapsed 8472
        callAdminFunction(10009453680007084245140033563715827249672489294939558664139039449915371351486,827143617152251475045365870035216388665587072646986147622683960742405892156);
        buyBear(28084112099162374911833274103582108765339946023515450924285427280006190); // 35_448_726.53333452
    }

    /**
        Payoff go to 0 | Error in payoff calculation due to use of decimals -> FIX removed use of prbmath
     */
    function test_8() public {
        deposit(363832441207608031381538649652880991216);
        vm.warp(block.timestamp + 89943);
        callAdminFunction(7709711957391696449644924662425615316104353629035315311135883,4692919964351829787252731322855358659984407068911172835365251);
        callAdminFunction(256655946237317258741608247951082432701860,354740622810918269336956915792081752);
        buySmilee(0);
        vm.warp(block.timestamp + 100058);
        callAdminFunction(29803577713175975728719396786707410020138369830389418421306966581964,0);
        sellSmilee(1347253341437032087717724329901562845424032412874086688218746642);
    }

    /// same test_8
    function test_9() public {
        deposit(3);
        vm.warp(block.timestamp + 147673);
        callAdminFunction(10,7016600745407);
        vm.warp(block.timestamp + 14615);
        callAdminFunction(825816348924844701292088890797515731501426120250569500869733356456849906,4172984492642209997040197925577839131595312355350801797339295216870948);
        buyBull(0);
        vm.warp(block.timestamp + 10943);
        callAdminFunction(3280046007163860492837367159705370869032495776034464712505330698117037096177,719448161461036991287904776808475643676636682307718868204681574324195086835);
        sellBull(2188545132624869139719206348643560878113435651409871683901688358);
    }

    /**
        Payoff is 0.23% of 1e-18 notional
     */
    function test_10() public {
        deposit(663); // 1663e-14
        callAdminFunction(209705029053490561079288413638962911889657827361982348784,68634752940773002574026202127292821124308879630206224789); // set token price 315.33537972851923
        vm.warp(block.timestamp + 96786);
        callAdminFunction(1549067089859764208748712685501942669993934697740870491400291077512543,184969450184);
        callAdminFunction(4462994417513440758528685897825929867715867101148439142597050757870998874,8105035166234110422266569917889308622279665061477732016059011046754298966); // set token price 159.96951008899907
        buyBear(0);
        vm.warp(block.timestamp + 92604);
        callAdminFunction(1284725181277127957315910390697642887565391463647356087660604251506030803,0);
        sellBear(797341448576130769790180721029182630190737937977408496751081327268);
    }

    /**
        Price doesn't change, profit > 0 (payoff = premium + 1)
        Approx problem in payoff calcualtion (fix in market value formula)
     */
    function test_11() public {
        deposit(73656835896403470880408202092); // 656835896403470880408276019 656835896.4034709
        vm.warp(block.timestamp + 89943); // ~ 1d
        // roll
        callAdminFunction(266432110305683411109246809602263033080067818912289926483847,51754215855933051339714057659602555348131322963928310883);
        // price 435970366477081517468 435.9703664770815
        callAdminFunction(120365710355053862587596618885051829,27492931503900366477109010674);
        buySmilee(0); // 1000 + 1000
        vm.warp(block.timestamp + 86401); // 1 d + 1 + 3543
        // roll
        callAdminFunction(6164563530367351661506131336201189562179091371649704700594627624,0);
        // 2000
        sellSmilee(143007476252246688414549877331616418671945481376698222);
    }

    /**
        Strange break IG_11
     */
    function test_12() public {
        deposit(2378619670875673844525681700791729113511730506061670233);
        vm.warp(block.timestamp + 87759);
        callAdminFunction(11009053483262904587257392965333658718023140353785640310911127486,31494680133468960006);
        buySmilee(3681438805190737524140869650039550087253049645098);
        sellSmilee(532532592);
    }

    function test_13() public {
        deposit(530521900148918802206790506277822744594818125);
        vm.warp(block.timestamp + 105444);
        callAdminFunction(11324937542665223109634109791790964707,13718036068035106058878404851332740781160604991806272177);
        buySmilee(88316193384789658807160332196865401252463615387);
        sellSmilee(0);
        // IG_03_2
    }

    function test_14() public {
        deposit(18482681084989489482165154684400022058371938026296191777048952645221295);
        vm.warp(block.timestamp + 285621);
        callAdminFunction(504684357853357368340230977805570593418460747720108223840582933601169,0);
        buyBull(2290093601431824472725800405079740834680006830219961557086655295933205);
        // IG_03_1
    }

    function test_15() public {
        deposit(1051034490173561764878087949156940155427);
        vm.warp(block.timestamp + 88083);
        callAdminFunction(141625567604158971302135402,5821680857693207976196398076442913178046209978);
        buyBull(265754352762039665202330300414964620458933251487518844808144839877333228647);
        vm.warp(block.timestamp + 34161);
        sellBull(122938242399466354816773767369374763997661136908228672496728221760447);
        // IG_03_1
    }
}
