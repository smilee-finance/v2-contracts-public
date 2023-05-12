// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SignedMath} from "./SignedMath.sol";

/// @title Implementation of normal cumulative distribution function approximation
library Normal {
    uint160 private constant N_39 = 111505427425257224751621052874312054487580675;
    uint160 private constant N_38 = 156107598402629361945966816116370677128560645;
    uint160 private constant N_37 = 245311600059429824819381452073367353111871496;
    uint160 private constant N_36 = 356817027489879346430746258396106008080154635;
    uint160 private constant N_35 = 512924625892508787604875588776814283047632913;
    uint160 private constant N_34 = 758236225946746236337559698957313546286333976;
    uint160 private constant N_33 = 1070451763034371960397328234648614563620323363;
    uint160 private constant N_32 = 1538773877667141689869394615255506861673414706;
    uint160 private constant N_31 = 2163204271267274623164354738727984704686522439;
    uint160 private constant N_30 = 3010645179445939837199906039999726142274142308;
    uint160 private constant N_29 = 4170300944142304557330392700947533609049260171;
    uint160 private constant N_28 = 5709075162097005623455528524268133950220075201;
    uint160 private constant N_27 = 7738472920458125557017634487005810066411487496;
    uint160 private constant N_26 = 10392301412712130017762023002018120963363701093;
    uint160 private constant N_25 = 13848968301885060634407944721206124835448422880;
    uint160 private constant N_24 = 18286882612153196065326221988590969718203023999;
    uint160 private constant N_23 = 23906754112896537809658376383137394360433378122;
    uint160 private constant N_22 = 30998496915423870156639528872938420448029967437;
    uint160 private constant N_21 = 39829724045568272227511498715460453420812928402;
    uint160 private constant N_20 = 50734951445338725666169916847849513321869084455;
    uint160 private constant N_19 = 64048695397026579354360318912545553708924078362;
    uint160 private constant N_18 = 80127773608691639014937027279468333736927234938;
    uint160 private constant N_17 = 99395906023999686913125412605590903433072348761;
    uint160 private constant N_16 = 122209911031580454752057725116203554146265600455;
    uint160 private constant N_15 = 148993508234817358034478405977699199411951310296;
    uint160 private constant N_14 = 180103515682052569324950869620182867641454566043;
    uint160 private constant N_13 = 215874449655593014395799882927991640762529554466;
    uint160 private constant N_12 = 256618525011946008317862054504160861197892789885;
    uint160 private constant N_11 = 302558752946270394183558669524176475745863609782;
    uint160 private constant N_10 = 353828940311759886296438250217773356096431797722;
    uint160 private constant N_9 = 410473689279407433763500118308057437173474017005;
    uint160 private constant N_8 = 472470698763711369774000763844336363435584342257;
    uint160 private constant N_7 = 539596958590396298551720264641174667158606205924;
    uint160 private constant N_6 = 611607156478832863895415663116528020836075528126;
    uint160 private constant N_5 = 688077572145067724480522124295216114836193700976;
    uint160 private constant N_4 = 768450678451964209351878776788997700484057364967;
    uint160 private constant N_3 = 852102045686476534665890565866116832520994392075;
    uint160 private constant N_2 = 938295737687291750888253960216342012936536889023;
    uint160 private constant N_1 = 1026228915717182603140917594329376713856315467233;
    uint160 private constant N_0 = 1115054138527688059209676872963989147711874839886;

    uint256 private constant MAX_INT_16 = 65535;

    function wcdf(int256 n) public pure returns (uint256) {
        return cdf(n / 1e16);
    }

    function cdf(int256 n) public pure returns (uint256) {
        uint256 tval = _cdfTable(SignedMath.abs(n));
        return n < 0 ? tval * 1e13 : (1e5 - tval) * 1e13;
    }

    function _cdfTable(uint256 n) private pure returns (uint256) {
        uint256 index = (n / 10);
        if (index > 39) return 0;

        uint256 shift = 16 * (9 - (n - (n / 10) * 10));
        if (index > 38) return (N_39 & (MAX_INT_16 << shift)) >> shift;
        if (index > 37) return (N_38 & (MAX_INT_16 << shift)) >> shift;
        if (index > 36) return (N_37 & (MAX_INT_16 << shift)) >> shift;
        if (index > 35) return (N_36 & (MAX_INT_16 << shift)) >> shift;
        if (index > 34) return (N_35 & (MAX_INT_16 << shift)) >> shift;
        if (index > 33) return (N_34 & (MAX_INT_16 << shift)) >> shift;
        if (index > 32) return (N_33 & (MAX_INT_16 << shift)) >> shift;
        if (index > 31) return (N_32 & (MAX_INT_16 << shift)) >> shift;
        if (index > 30) return (N_31 & (MAX_INT_16 << shift)) >> shift;
        if (index > 29) return (N_30 & (MAX_INT_16 << shift)) >> shift;
        if (index > 28) return (N_29 & (MAX_INT_16 << shift)) >> shift;
        if (index > 27) return (N_28 & (MAX_INT_16 << shift)) >> shift;
        if (index > 26) return (N_27 & (MAX_INT_16 << shift)) >> shift;
        if (index > 25) return (N_26 & (MAX_INT_16 << shift)) >> shift;
        if (index > 24) return (N_25 & (MAX_INT_16 << shift)) >> shift;
        if (index > 23) return (N_24 & (MAX_INT_16 << shift)) >> shift;
        if (index > 22) return (N_23 & (MAX_INT_16 << shift)) >> shift;
        if (index > 21) return (N_22 & (MAX_INT_16 << shift)) >> shift;
        if (index > 19) return (N_21 & (MAX_INT_16 << shift)) >> shift;
        if (index > 18) return (N_19 & (MAX_INT_16 << shift)) >> shift;
        if (index > 17) return (N_18 & (MAX_INT_16 << shift)) >> shift;
        if (index > 16) return (N_17 & (MAX_INT_16 << shift)) >> shift;
        if (index > 15) return (N_16 & (MAX_INT_16 << shift)) >> shift;
        if (index > 14) return (N_15 & (MAX_INT_16 << shift)) >> shift;
        if (index > 13) return (N_14 & (MAX_INT_16 << shift)) >> shift;
        if (index > 12) return (N_13 & (MAX_INT_16 << shift)) >> shift;
        if (index > 11) return (N_12 & (MAX_INT_16 << shift)) >> shift;
        if (index > 10) return (N_11 & (MAX_INT_16 << shift)) >> shift;
        if (index > 9) return (N_10 & (MAX_INT_16 << shift)) >> shift;
        if (index > 8) return (N_9 & (MAX_INT_16 << shift)) >> shift;
        if (index > 7) return (N_8 & (MAX_INT_16 << shift)) >> shift;
        if (index > 6) return (N_7 & (MAX_INT_16 << shift)) >> shift;
        if (index > 5) return (N_6 & (MAX_INT_16 << shift)) >> shift;
        if (index > 4) return (N_5 & (MAX_INT_16 << shift)) >> shift;
        if (index > 3) return (N_4 & (MAX_INT_16 << shift)) >> shift;
        if (index > 2) return (N_3 & (MAX_INT_16 << shift)) >> shift;
        if (index > 1) return (N_2 & (MAX_INT_16 << shift)) >> shift;
        if (index > 0) return (N_1 & (MAX_INT_16 << shift)) >> shift;
        return (N_0 & (MAX_INT_16 << shift)) >> shift;
    }

    function toBinaryString(uint256 n) public pure returns (string memory) {
        bytes memory output = new bytes(160);

        for (uint8 i = 0; i < 160; i++) {
            output[159 - i] = (n % 2 == 1) ? bytes1("1") : bytes1("0");
            n /= 2;
        }

        return string(output);
    }
}
