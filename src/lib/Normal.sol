// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SignedMath} from "./SignedMath.sol";

/**
    @title Implementation of normal cumulative distribution function approximation
    @dev values have been taken from a common cdf table https://www.math.arizona.edu/~rsims/ma464/standardnormaltable.pdf approximated to 5 decimals

    Since each value (v x 1e5) fit into a uint16, we created a 25 uint256 table, each containing of 16 values (total 400 values).
    Value retrieve is simply done by shifting the row to the right position.
 */
library Normal {
    uint256 private constant N_24 = 10601244150818597103307951167324588515708918689086689556562382254445363203;
    uint256 private constant N_23 = 21202461341279150916645806157073046630666928570703273424496351166897520646;
    uint256 private constant N_22 = 38871201592232107467627100343557226982045986530477171941837867757182189580;
    uint256 private constant N_21 = 68908060019140101295768992581852327481564342726275649262957285477602230294;
    uint256 private constant N_20 = 121914226852517012786667809269534894145431285081238118269083542332969189416;
    uint256 private constant N_19 = 208491027123432829189276218339981645291863004867489285967528531015848558663;
    uint256 private constant N_18 = 351607769237533715887498977817370387629973629320691389424670917999451832442;
    uint256 private constant N_17 = 576000689547141123575370713585649991895997244974817757693157556352904855757;
    uint256 private constant N_16 = 924074710735224742779716810242889122063700000685030545781800010118143344976;
    uint256 private constant N_15 = 1448836107474948159871288560474164295670097856236915249355978588125030646299;
    uint256 private constant N_14 = 2217426011841655855197503700836990055032925247780188202850717159872425755466;
    uint256 private constant N_13 = 3314654457921325281114803499389404740302249156328509187974934793100047484167;
    uint256 private constant N_12 = 4846533752421586352010491260055780995941193998003226224383442802372710107011;
    uint256 private constant N_11 = 6926143913831010845005550658573621026949418026188251480989111982258027760375;
    uint256 private constant N_10 = 9682466692063842329151361267978877368432417008131344187817599046216507527078;
    uint256 private constant N_09 = 13239183295840400615481379844264536520737154383552563006414933271079283135960;
    uint256 private constant N_08 = 17716441158869551832835242288261058195922083136329731125018835417828625227220;
    uint256 private constant N_07 = 23209651478509897552610075325886299956395614309829022057271571439239851616220;
    uint256 private constant N_06 = 29777121178472425643348473816213241336614456675805523341668843528466001245222;
    uint256 private constant N_05 = 37432985304879355057775308104394684700844604899463964369549751457265428284114;
    uint256 private constant N_04 = 46131305186998677403651618560612777148852162764924893217884779093798681203684;
    uint256 private constant N_03 = 55764301563219020472214009090480629790268395866083471135639375818027554268995;
    uint256 private constant N_02 = 66165888302138740297845602133902740163701610206093351715666351691862455385262;
    uint256 private constant N_01 = 77113439357472131753228400106904630729005190884236490359727936734390118355908;
    uint256 private constant N_00 = 88343690499474688971411165391354918996666130358655838879889354234990603381766;

    /**
        @notice Cumulative distribution function of a wad notation number
        @param n The number in wad notation (2.75512 -> 2_75512...0 with 18 decimals)
        @return cdf_ The cdf value in wad

        TODO - rounding up or down (right now is always down to 2 decimal)
     */
    function wcdf(int256 n) public pure returns (uint256) {
        return cdf(n / 1e16);
    }

    /**
        @notice Cumulative distribution function of a 2 decimals notation number
        @param n The number in 2 decimals notation (2.75512 -> 275)
        @return cdf_ The cdf value in wad
     */
    function cdf(int256 n) public pure returns (uint256 cdf_) {
        uint256 tval = _cdfTable(SignedMath.abs(n));
        return n < 0 ? tval * 1e13 : (1e5 - tval) * 1e13;
    }

    function _cdfTable(uint256 n) private pure returns (uint256) {
        uint256 index = (n / 16);
        if (index > 24) return 0;

        uint256 shift = 16 * (15 - (n - index * 16));
        if (index > 9) {
            if (index > 15) {
                if (index > 19) {
                    if (index > 23) return ((N_24 >> shift) & 65535);
                    if (index > 22) return ((N_23 >> shift) & 65535);
                    if (index > 21) return ((N_22 >> shift) & 65535);
                    if (index > 20) return ((N_21 >> shift) & 65535);
                    return ((N_20 >> shift) & 65535);
                } else {
                    if (index > 18) return ((N_19 >> shift) & 65535);
                    if (index > 17) return ((N_18 >> shift) & 65535);
                    if (index > 16) return ((N_17 >> shift) & 65535);
                    return ((N_16 >> shift) & 65535);
                }
            } else {
                if (index > 14) return ((N_15 >> shift) & 65535);
                if (index > 13) return ((N_14 >> shift) & 65535);
                if (index > 12) return ((N_13 >> shift) & 65535);
                if (index > 11) return ((N_12 >> shift) & 65535);
                if (index > 10) return ((N_11 >> shift) & 65535);
                return ((N_10 >> shift) & 65535);
            }
        } else {
            if (index > 4) {
                if (index > 8) return ((N_09 >> shift) & 65535);
                if (index > 7) return ((N_08 >> shift) & 65535);
                if (index > 6) return ((N_07 >> shift) & 65535);
                if (index > 5) return ((N_06 >> shift) & 65535);
                return ((N_05 >> shift) & 65535);
            } else {
                if (index > 3) return ((N_04 >> shift) & 65535);
                if (index > 2) return ((N_03 >> shift) & 65535);
                if (index > 1) return ((N_02 >> shift) & 65535);
                if (index > 0) return ((N_01 >> shift) & 65535);
                return ((N_00 >> shift) & 65535);
            }
        }
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
