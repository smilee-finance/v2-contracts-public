// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {console} from "forge-std/console.sol";

abstract contract Properties is Setup {
    // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);

    // INVARIANTS
    string internal constant IG_09 = "IG_09: The option seller never gains more than the payoff";
    string internal constant IG_10 = "IG_10: The option buyer never loses more than the premium";
    string internal constant IG_11 = "IG_11: Payoff never exeed slippage";
    string internal constant IG_12 = "IG_12: A IG bull payoff is always positive above the strike price & zero at or below the strike price";
    string internal constant IG_13 = "IG_13: A IG bear payoff is always positive under the strike price & zero at or above the strike price";

    string internal constant _GENERAL_1 = "GENERAL_1";
    string internal constant _GENERAL_5_BEFORE_TIMESTAMP = "GENERAL_5_BEFORE_TIMESTAMP";
    string internal constant _GENERAL_5_AFTER_TIMESTAMP = "GENERAL_5_AFTER_TIMESTAMP";
    string internal constant _GENERAL_6 = "GENERAL_6";

    // Errors
    bytes32 internal constant _ERR_VAULT_DEAD = keccak256(abi.encodeWithSignature("VaultDead()"));
    bytes32 internal constant _ERR_VAULT_PAUSED = keccak256(abi.encodeWithSignature("Pausable: paused"));
    bytes32 internal constant _ERR_EPOCH_NOT_FINISHED = keccak256(abi.encodeWithSignature("EpochNotFinished()"));
    bytes32 internal constant _ERR_EXCEEDS_AVAILABLE = keccak256(abi.encodeWithSignature("ExceedsAvailable()"));
    bytes32 internal constant _ERR_NOT_ENOUGH_NOTIONAL = keccak256(abi.encodeWithSignature("NotEnoughNotional()"));
    bytes32 internal constant _ERR_INSUFFICIENT_INPUT = keccak256(abi.encodeWithSignature("InsufficientInput()")); // see TestnetSwapAdapter

    bytes4 internal constant _INSUFFCIENT_LIQUIDITY_SEL = bytes4(keccak256("InsufficientLiquidity(bytes4)"));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_01 = keccak256(abi.encodeWithSelector(_INSUFFCIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::lockedLiquidity <= _state.liquidity.newPendingPayoffs"))));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_02 = keccak256(abi.encodeWithSelector(_INSUFFCIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::sharePrice == 0"))));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_03 = keccak256(abi.encodeWithSelector(_INSUFFCIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::_state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs - baseTokens"))));

    // Accept reverts array
    mapping(string => mapping(bytes32 => bool)) internal _ACCEPTED_REVERTS;

    function _initializeProperties() internal {
        // GENERAL 1 - No reverts allowed

        // GENERAL 5
        _ACCEPTED_REVERTS[_GENERAL_5_BEFORE_TIMESTAMP][_ERR_EPOCH_NOT_FINISHED] = true;
        _ACCEPTED_REVERTS[_GENERAL_5_AFTER_TIMESTAMP][_ERR_EXCEEDS_AVAILABLE] = true;
        _ACCEPTED_REVERTS[_GENERAL_5_AFTER_TIMESTAMP][_ERR_INSUFF_LIQUIDITY_ROLL_01] = true;
        _ACCEPTED_REVERTS[_GENERAL_5_AFTER_TIMESTAMP][_ERR_INSUFF_LIQUIDITY_ROLL_02] = true;
        _ACCEPTED_REVERTS[_GENERAL_5_AFTER_TIMESTAMP][_ERR_INSUFF_LIQUIDITY_ROLL_03] = true;

        // GENERAL 6
        _ACCEPTED_REVERTS[_GENERAL_6][_ERR_NOT_ENOUGH_NOTIONAL] = true;
        _ACCEPTED_REVERTS[_GENERAL_6][_ERR_EXCEEDS_AVAILABLE] = true;
        _ACCEPTED_REVERTS[_GENERAL_6][_ERR_INSUFFICIENT_INPUT] = true;
    }
}
