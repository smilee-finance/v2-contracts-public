// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {console} from "forge-std/console.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {

    /**
        IMPORTANT!
        Check number of token's decimals before run test
        [01 : 23] => 18 & 18
        [24 : ] => 6 & 18
     */

    function setUp() public {
        setup();
    }

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
        should be InsufficientLiquidity(bytes4(keccak256("_buySideTokens()")));
    */
    /**
    function testFail_2() public {
        vm.warp(block.timestamp + 65280);
        deposit(53660751925402942071444234319586906678597225057891828354971127042736941450);
        vm.warp(block.timestamp + 334984);
        callAdminFunction(2114683348797038701721556498398548843679748884308985742881043097095705417104, 2);
        vm.warp(block.timestamp + 29113);
        buyBull(10616969518659123581099617347038970877541454535286915844038626259034985343772);
    }
     */

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
        // Setup
        MIN_VAULT_DEPOSIT = 200_000;
        MIN_OPTION_BUY = 10_000;
        MAX_TOKEN_PRICE = 1_000e18;

        deposit(62371730870697728150);
        vm.warp(block.timestamp + 88417);
        callAdminFunction(91191509274284818089195485045059220520329531160155857031,560546320870737139457170187497346984605561619303321602565095);
        callAdminFunction(1543512734265866555972778732410098471,83381555156362781964048013826851);
        buySmilee(0);
        sellSmilee(261491956713171412);
    }

    /**
        FINANCE_IG:253 tPrevious non veniva dentro resettato alla rollEpoch -> FIX: setter fuori dall'IF
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
        // vm.warp(block.timestamp + 20000);
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

    /**
        since premium is computed as sum of individual components, it shows minor numeric error
        when it should be flat, resulting in oscillating funct p = f(σ)
        pBull = p1 (stable) + p2 (stable) - p3 (small increase with σ) - p4 (small decrease with σ) - p5 (small decrease with σ)
        this means premium(σ_trade) ≈ premium(σ_min) ≈ premium(σ_max) but breaks invariant premium(σ_trade) < premium(σ_max) for an insignificant amount
     */
    function test_16() public {
        deposit(2598815979535791392650349155725307559004232563062986);
        vm.warp(block.timestamp + 98710);
        callAdminFunction(2759995693894705286270150264751168629303119878274493352182021438643,3191658696782648234870846407286396637621195120149335072456079502468097623);
        callAdminFunction(331056827005901253160921164922582471882608228289305872240903370589827948,459869873452095112399741750219291595080115997018980002145271419839);
        callAdminFunction(5584952083121955048280594199833031519042643679683018017071916483470,2557665265024842509566435254777460810681564640055536281926360659252);
        buySmilee(322632051130518995476083019706582586812028838626850117267);
        // IG_03_1 -> premium (expectedPremium) <= premium with IV max
    }

    /**
        premium  => 288101.652119 8092
        expected => 288101.652119 81116
     */
    function test_17() public {
        deposit(423307637375438812712042770985364286205494461969951544685577);
        vm.warp(block.timestamp + 100353);
        callAdminFunction(32303544467686343529913887103247763466702008692025135140,0);
        callAdminFunction(14211450755175968984785211625433968817228906214153279961957294519701215,0);
        buyBear(29360403950846471158868228052399623906788159012137341390278722960128);
    }

    /**
        Setta un prezzo -> rolla epoca
        Il prezzo diminuisce ~ 30%
        Compra bear
        Rolla epoca
        Vende bear (payoff > premium)
        FIXED after new delta
     */
    function test_18() public {
        // Setup
        MIN_VAULT_DEPOSIT = 200_000;
        MIN_OPTION_BUY = 10_000;
        MAX_TOKEN_PRICE = 1_000e18;

        deposit(93);
        callAdminFunction(2377155786571951189298921622007369147648652565535159623,11174772035670605948504275428392330951138012204890085482);
        vm.warp(block.timestamp + 96786);
        callAdminFunction(1431434924619959508713677195921937724170555313896136210820974749311444,86698543930);
        callAdminFunction(1726909336048179509951966933168551565575947000870747543728835024341231795,501290294221066830489836932710580229692278804303731236217486835753041866);
        buyBear(0);
        vm.warp(block.timestamp + 92604);
        callAdminFunction(5861675324907212805057829220851547932627566111831467711663875746113926,0);
        sellBear(1002330666111824467578667264840049609617861201229242387944511);
    }

    /**
        like test_17 but in a SELL
        payoff   => 11489974127587 7429080370 -> 114899.74127587 743
        expected => 11489974127587 6995901966 -> 114899.74127587 7
     */
    function test_19() public {
        deposit(37066744011882662307322883060977);
        callAdminFunction(96060766435339876409463801113089185126592489140356590573146993793463,91882);
        vm.warp(block.timestamp + 93629);
        callAdminFunction(2123828553691874246008726667544917752886287182149634824537417016,26);
        buyBull(6329017278754622905240606702214001806635188206279662034266);
        sellBull(14);
    }

    /**
        like test_18
    */
    function test_20() public {
        deposit(800580301567623717261402377857319139000999309591385992805756654676);
        vm.warp(block.timestamp + 147673);
        callAdminFunction(10,2944901718733);
        vm.warp(block.timestamp + 14424);
        callAdminFunction(197527652989854302220357873368023172504094120233791560562431381021397290,363705820392302980868865445742946543441158372556971138348807013031);
        buyBull(0);
        buySmilee(5752830415617398815498998192563311945205115591851683295512);
        vm.warp(block.timestamp + 11945);
        callAdminFunction(23262723743039068255073528904091887136950941061202793809543770308594831367,50140337573808921479236207837850268121785753003247325992286776887690676683);
        sellSmilee(401918786667870094167815412692754360544047764526854926052858111303);
        sellBull(7713390305724069356024);
    }

    /**
        revert SlippedMarketValue()
    */
    function testFail_21() public {
        // Setup
        MIN_VAULT_DEPOSIT = 200_000;
        MIN_OPTION_BUY = 10_000;
        MAX_TOKEN_PRICE = 1_000e18;

        deposit(210); // 200210
        vm.warp(block.timestamp + 86911);
        // token price 977438559572558438478 977.4385
        callAdminFunction(6556804589560001720336737730878790743208491336123063752,527617053888875542268387391153034913492594072672262538);
        // roll epoch
        callAdminFunction(194480424127950262280307908059984295872918888910379873355929616,15381700399932317829884095112591540214707713650231845182675557997);
        buyBear(5928224393158461906330184732177990580369369920790); // 82178
    }

    function test_22() public {
        deposit(296342259192872841304930541012896970701);
        vm.warp(block.timestamp + 88083);
        callAdminFunction(22675101178327823094613882,6316244417623050784708423897568384236481855098);
        initiateWithdraw(2532008291145098071148312159617094645801510245812059280332377316615764292334);
        deposit(526259430645699625236482278181871938389127263316616906046988459630151510);
        vm.warp(block.timestamp + 149442);
        callAdminFunction(11,1910728547794275);
    }

    /**
        PriceBull goes negative p3 > p1 + p2 (fixed)
     */
    function test_23() public {
        deposit(2126334661631650472160001239073693612578739734945829894397444672163960986574);
        vm.warp(block.timestamp + 110708);
        callAdminFunction(5169669188236344552042093701429765239669505597278200379597595865665615470720,8749492025694042386592079318585037975633937764054834539568872447042221147184);
        vm.warp(block.timestamp + 323566);
        callAdminFunction(2845559563721998081958410640734687789854979932799547903813658298273796751429,11630523485759453529931501248494012638812988734813216310076457509772285652623);
        vm.warp(block.timestamp + 399501);
        callAdminFunction(11455813486668528748363299223100603799704112872989241156452277360950410199578,26858110371467041310735580739663109305368264248633109071947795617142909010362);
        buyBear(16213361655922531010327861187524263120668406390971124115480699861194738608185);
    }

    /**
        Worst off
     */
    function test_24() public {
        vm.warp(block.timestamp + 80118);
        deposit(1287411528851971937893850489202348703004846726134503910857403222685296072948);
        vm.warp(block.timestamp + 47739);
        callAdminFunction(0,54008722422514824720745794771247179604794190066355790171869800368444604985534);
        callAdminFunction(12893515289296501778774233874048225484536546618160045712049305928893285785243,2753693240023968708);
        vm.warp(block.timestamp + 284448);
        callAdminFunction(21105297364783965597242698184902440268959945731849823992680180113868564713964,38040738540635798405975382118594869040775923366948010740279774831476770404768);
        vm.warp(block.timestamp + 323566);
        callAdminFunction(8516975225945311538107132738200628119725869562952148342978257233342989872415,69272021300262182177651197984842290237312601598925228105486162179422550942876);
        buyBear(7322360386737542152);
        vm.warp(block.timestamp + 27022);
        buySmilee(1394749764395806683715964848714515570894695391084343958361539936944413434611);
    }

    /**
        If price drops near to 0 and near to maturity, if bear the premium can grow if the time pass
     */
    function test_25() public {
        deposit(166042447148348179660107483);
        vm.warp(block.timestamp + 90095);
        callAdminFunction(13758010420754611781632267973991414500157366084407947,1280065636694890695717487314303829608588916166783169384258350754043995043);
        callAdminFunction(8195443413161124188778130268651834180493696844419516626811358072,1);
        callAdminFunction(68810149516844908386443685945848336009980204491643220023410016003851938156086,16256341966623338242235730688208447742860413281671866885555511280241023836403);
    }

    function test_26() public {
        deposit(520126963530215599416463582858283412247339051534801207123793731979586454);
        vm.warp(block.timestamp + 188079);
        callAdminFunction(3279737145792527063441728494140625799970248682464557767103473672668211915,121899212951448);
        callAdminFunction(563657844937227370257839033913354537599089165363907729589045245575773768423,0);
        buyBear(688419768287300758491671902187099753275378786259759375402820826537608762);
    }

    /**
        sidetoken price = decimal.Decimal("1000000000000000000") / 475081328759579842408 = Decimal('0.002104902759725295483479190256')
        gets approximated to 0.002104902759725295
        leading to target side tokens 892965342766381242978039 < 892965342766381448084977 after first epoch
     */
    function test_27() public {
        deposit(1538845384323155412332890137686); // 848_462_323.155412332890136148
        vm.warp(block.timestamp + 88083);
        callAdminFunction(82626331,77647096502091328759735139706); // price 475.081
        callAdminFunction(158676193263058568817276662385456583408583648,389000856729725218450858118227232998829508578479); // rollepoch
        initiateWithdraw(1138998423721152195025232816420647290123088152875874776194); // withdraw all, with share price 1.0
        vm.warp(block.timestamp + 88774);
        callAdminFunction(44237826109279931,8188983321755133194167599241166872124991173522390158876306605229697789034004); // rollepoch breaks for insufficient liquidity
        // fixed withdrawing a bit less than all
    }
}
