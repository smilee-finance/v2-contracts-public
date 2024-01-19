// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {console} from "forge-std/console.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {console} from "forge-std/console.sol";
import {PropertiesDescriptions} from "./PropertiesDescriptions.sol";
import {IPriceOracle} from "@project/interfaces/IPriceOracle.sol";
import {IFeeManager} from "@project/interfaces/IFeeManager.sol";

abstract contract Properties is BeforeAfter, PropertiesDescriptions {

    error PropertyFail(string);

    // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);

    // Errors
    bytes32 internal constant _ERR_VAULT_DEAD = keccak256(abi.encodeWithSignature("VaultDead()"));
    bytes32 internal constant _ERR_VAULT_PAUSED = keccak256(abi.encodeWithSignature("Pausable: paused"));
    bytes32 internal constant _ERR_EPOCH_NOT_FINISHED = keccak256(abi.encodeWithSignature("EpochNotFinished()"));
    bytes32 internal constant _ERR_EXCEEDS_AVAILABLE = keccak256(abi.encodeWithSignature("ExceedsAvailable()"));
    bytes32 internal constant _ERR_PRICE_ZERO = keccak256(abi.encodeWithSignature("PriceZero()"));
    bytes32 internal constant _ERR_NOT_ENOUGH_NOTIONAL = keccak256(abi.encodeWithSignature("NotEnoughNotional()"));

    bytes4 internal constant _INSUFFCIENT_LIQUIDITY_SEL = bytes4(keccak256("InsufficientLiquidity(bytes4)"));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_01 = keccak256(abi.encodeWithSelector(_INSUFFCIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::lockedLiquidity <= _state.liquidity.newPendingPayoffs"))));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_02 = keccak256(abi.encodeWithSelector(_INSUFFCIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::sharePrice == 0"))));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_03 = keccak256(abi.encodeWithSelector(_INSUFFCIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::_state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs - baseTokens"))));

    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_EDGE_01 = keccak256(abi.encodeWithSelector(_INSUFFCIENT_LIQUIDITY_SEL, bytes4(keccak256("_sellSideTokens()"))));
    // bytes32 internal constant _ERR_INSUFF_LIQUIDITY_EDGE_02 = keccak256(abi.encodeWithSelector(_INSUFFCIENT_LIQUIDITY_SEL, bytes4(keccak256("_buySideTokens()")))); // Replace by InsufficientInput()
    bytes32 internal constant _ERR_INSUFFICIENT_INPUT = keccak256(abi.encodeWithSignature("InsufficientInput()")); // see TestnetSwapAdapter

    // Accept reverts array
    mapping(string => mapping(bytes32 => bool)) internal _ACCEPTED_REVERTS;

    function _initializeProperties() internal {
        // GENERAL 1 - No reverts allowed

        // GENERAL 5
        _ACCEPTED_REVERTS[_GENERAL_5_BEFORE_TIMESTAMP.code][_ERR_EPOCH_NOT_FINISHED] = true;
        _ACCEPTED_REVERTS[_GENERAL_5_AFTER_TIMESTAMP.code][_ERR_EXCEEDS_AVAILABLE] = true;
        _ACCEPTED_REVERTS[_GENERAL_5_AFTER_TIMESTAMP.code][_ERR_INSUFF_LIQUIDITY_ROLL_01] = true;
        _ACCEPTED_REVERTS[_GENERAL_5_AFTER_TIMESTAMP.code][_ERR_INSUFF_LIQUIDITY_ROLL_02] = true;
        _ACCEPTED_REVERTS[_GENERAL_5_AFTER_TIMESTAMP.code][_ERR_INSUFF_LIQUIDITY_ROLL_03] = true;

        // GENERAL 6
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_NOT_ENOUGH_NOTIONAL] = true;
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_EXCEEDS_AVAILABLE] = true;
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_INSUFFICIENT_INPUT] = true;
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_PRICE_ZERO] = true;
    }

    /// @notice Share price never goes to 0
    function smilee_invariants_vault_16() public returns (bool) {
        if (vault.v0() > 0) {
            uint256 epochSharePrice = vault.epochPricePerShare(ig.getEpoch().previous);
            return epochSharePrice > 0;
        }
        return true;
    }

    function smilee_invariants_ig_20() public returns (bool) {
        // uint256 price = IPriceOracle(ap.priceOracle()).getPrice(sideToken, address(baseToken));
        uint256 price = IPriceOracle(ap.priceOracle()).getPrice(ig.sideToken(), ig.baseToken());
        // IFeeManager feeManager = IFeeManager(ap.feeManager());
        // uint256 minFee = feeManager.dvpsFeeParams(address(ig)).vaultSellMinFee; // TODO: verify how to
        return price >= 0 /* + minFee */;
    }
}
