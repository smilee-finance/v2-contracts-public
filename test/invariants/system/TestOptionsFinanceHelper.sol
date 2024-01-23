// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FinanceParameters} from "@project/lib/FinanceIG.sol";
import {WadTime} from "@project/lib/WadTime.sol";
import {FinanceIGPrice} from "@project/lib/FinanceIGPrice.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";

library TestOptionsFinanceHelper {
    uint8 internal constant _BULL = 0;
    uint8 internal constant _BEAR = 1;
    uint8 internal constant _SMILE = 2;

    // S * N(d1) - K * e^(-r tau) * N(d2)
    function _optionCallPremium(
        uint256 amount,
        uint256 s,
        uint256 k,
        uint256 r,
        uint256 tau,
        uint256 n1,
        uint256 n2
    ) private pure returns (uint256) {
        UD60x18 p = (ud(s).mul(ud(n1))).sub(ud(k).mul(ud(FinanceIGPrice._ert(r, tau))).mul(ud(n2)));
        return ud(amount).mul(p).div(ud(k)).unwrap();
    }

    // K * e^(-r tau) * N(-d2) - S * N(-d1)
    function _optionPutPremium(
        uint256 amount,
        uint256 s,
        uint256 k,
        uint256 r,
        uint256 tau,
        uint256 n1,
        uint256 n2
    ) private pure returns (uint256) {
        UD60x18 p = (ud(k).mul(ud(FinanceIGPrice._ert(r, tau))).mul(ud(n2))).sub(ud(s).mul(ud(n1)));
        return ud(amount).mul(p).div(ud(k)).unwrap();
    }

    // S * 2(N(d1) - 1) - K * e^(-r tau) * (2 N(d2) - 1)
    function _optionStraddlePremium(
        uint256 amount,
        uint256 s,
        uint256 k,
        uint256 r,
        uint256 tau,
        uint256 n1,
        uint256 n2
    ) private pure returns (uint256) {
        UD60x18 p = (ud(k).mul(ud(FinanceIGPrice._ert(r, tau))).mul(ud(n2))).sub(ud(s).mul(ud(n1)));
        return ud(amount).mul(p).div(ud(k)).unwrap();
    }

    // S * (N(db1) - N(-da1)) - K * e^(-r tau) * (N(db2) - N(-da2))
    function _optionStranglePremium(
        uint256 amount,
        uint256 s,
        uint256 k,
        uint256 r,
        uint256 tau,
        FinanceIGPrice.NTerms memory nas,
        FinanceIGPrice.NTerms memory nbs
    ) private pure returns (uint256) {
        // S * (N(db1) - N(-da1))
        UD60x18 a = (ud(s).mul(ud(nbs.n1).sub(ud(nas.n1))));
        // K * e^(-r tau) * (N(db2) - N(-da2))
        UD60x18 b = ud(k).mul(ud(FinanceIGPrice._ert(r, tau))).mul(ud(nbs.n2).sub(ud(nas.n2)));
        return ud(amount).mul(a.sub(b)).div(ud(k)).unwrap();
    }

    /**
        @notice CALL premium option with same strike and notional of a given IG-Bull option
     */
    function _optionCallPremiumK(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (FinanceIGPrice.DTerms memory ds, , ) = FinanceIGPrice.dTerms(params);
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(ds);
        return _optionCallPremium(amount, params.s, params.k, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice CALL premium option with strike in Kb and same notional of a given IG-Bull option
     */
    function _optionCallPremiumKb(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (, , FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(params);
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(dbs);
        return _optionCallPremium(amount, params.s, params.k, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice PUT premium option with same strike and notional of a given IG-Bear option
     */
    function _optionPutPremiumK(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (FinanceIGPrice.DTerms memory ds, , ) = FinanceIGPrice.dTerms(params);
        ds.d1 = -ds.d1;
        ds.d2 = -ds.d2;
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(ds);
        return _optionPutPremium(amount, params.s, params.k, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice PUT premium option with strike in Ka and same notional of a given IG-Bear option
     */
    function _optionPutPremiumKa(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (, FinanceIGPrice.DTerms memory das, ) = FinanceIGPrice.dTerms(params);
        das.d1 = -das.d1;
        das.d2 = -das.d2;
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(das);
        return _optionPutPremium(amount, params.s, params.k, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice STRADDLE premium option with same strike and notional of a given IG-Smilee option
     */
    function _optionStraddlePremiumK(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (FinanceIGPrice.DTerms memory ds, , ) = FinanceIGPrice.dTerms(params);
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(ds);
        return _optionStraddlePremium(amount, params.s, params.k, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice STRANGLE premium option with strike in Ka and Kb and same notional of a given IG-Smilee option
     */
    function _optionStranglePremiumKaKb(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (, FinanceIGPrice.DTerms memory das, FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(params);
        das.d1 = -das.d1;
        das.d2 = -das.d2;

        FinanceIGPrice.NTerms memory nas = FinanceIGPrice.nTerms(das);
        FinanceIGPrice.NTerms memory nbs = FinanceIGPrice.nTerms(dbs);

        return _optionStranglePremium(amount, params.s, params.k, params.r, params.tau, nas, nbs);
    }

    function equivalentOptionPremiums(
        uint8 strategy,
        uint256 amount,
        uint256 oraclePrice,
        uint256 riskFree,
        FinanceParameters memory finParams
    ) public returns (uint256, uint256) {
        FinanceIGPrice.Parameters memory params = FinanceIGPrice.Parameters(
            riskFree, // r
            finParams.sigmaZero,
            finParams.currentStrike,
            oraclePrice, // s
            WadTime.yearsToTimestamp(finParams.maturity), // tau
            finParams.kA,
            finParams.kB,
            finParams.theta
        );
        if (strategy == _BULL) {
            return (_optionCallPremiumK(amount, params), _optionCallPremiumKb(amount, params));
        }
        if (strategy == _BEAR) {
            return (_optionPutPremiumK(amount, params), _optionPutPremiumKa(amount, params));
        }
        if (strategy == _SMILE) {
            return (_optionStraddlePremiumK(amount, params), _optionStranglePremiumKaKb(amount, params));
        }
    }
}
