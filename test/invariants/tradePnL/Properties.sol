// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {console} from "forge-std/console.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {PropertiesDescriptions} from "./PropertiesDescriptions.sol";
import {IPriceOracle} from "@project/interfaces/IPriceOracle.sol";
import {AmountsMath} from "@project/lib/AmountsMath.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EchidnaVaultUtils} from "../lib/EchidnaVaultUtils.sol";

abstract contract Properties is BeforeAfter, PropertiesDescriptions {
    error PropertyFail(string);

    struct BuyInfo {
        uint256 tokenId; // position manager nft
        address recipient;
        uint256 premium;
        uint256 amountUp;
        uint256 amountDown;
        uint256 timestamp;
        uint256 buyTokenPrice;
    }

    struct EpochInfo {
        uint256 epochTimestamp;
        uint256 epochStrike;
    }

    uint8 internal constant _BULL = 0;
    uint8 internal constant _BEAR = 1;
    uint8 internal constant _SMILEE = 2;

    uint8 internal constant _BUY = 0;
    uint8 internal constant _SELL = 1;

    // Errors
    string internal constant _ERR_VAULT_PAUSED = "Pausable: paused";
    bytes32 internal constant _ERR_VAULT_DEAD = keccak256(abi.encodeWithSignature("VaultDead()"));
    bytes32 internal constant _ERR_EPOCH_NOT_FINISHED = keccak256(abi.encodeWithSignature("EpochNotFinished()"));
    bytes32 internal constant _ERR_EXCEEDS_AVAILABLE = keccak256(abi.encodeWithSignature("ExceedsAvailable()"));
    bytes32 internal constant _ERR_PRICE_ZERO = keccak256(abi.encodeWithSignature("PriceZero()"));
    bytes32 internal constant _ERR_NOT_ENOUGH_NOTIONAL = keccak256(abi.encodeWithSignature("NotEnoughNotional()"));
    bytes32 internal constant _ERR_ASYMMETRIC_AMOUNT = keccak256(abi.encodeWithSignature("AsymmetricAmount()"));

    bytes4 internal constant _INSUFFICIENT_LIQUIDITY_SEL = bytes4(keccak256("InsufficientLiquidity(bytes4)"));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_01 =
        keccak256(
            abi.encodeWithSelector(
                _INSUFFICIENT_LIQUIDITY_SEL,
                bytes4(keccak256("_beforeRollEpoch()::lockedLiquidity <= _state.liquidity.newPendingPayoffs"))
            )
        );
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_02 =
        keccak256(
            abi.encodeWithSelector(
                _INSUFFICIENT_LIQUIDITY_SEL,
                bytes4(keccak256("_beforeRollEpoch()::sharePrice == 0"))
            )
        );
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_03 =
        keccak256(
            abi.encodeWithSelector(
                _INSUFFICIENT_LIQUIDITY_SEL,
                bytes4(
                    keccak256(
                        "_beforeRollEpoch()::_state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs - baseTokens"
                    )
                )
            )
        );

    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_EDGE_01 =
        keccak256(abi.encodeWithSelector(_INSUFFICIENT_LIQUIDITY_SEL, bytes4(keccak256("_sellSideTokens()"))));
    // bytes32 internal constant _ERR_INSUFF_LIQUIDITY_EDGE_02 = keccak256(abi.encodeWithSelector(_INSUFFICIENT_LIQUIDITY_SEL, bytes4(keccak256("_buySideTokens()")))); // Replace by InsufficientInput()
    bytes32 internal constant _ERR_INSUFFICIENT_INPUT = keccak256(abi.encodeWithSignature("InsufficientInput()")); // see TestnetSwapAdapter
    bytes32 internal constant _ERR_CHECK_SLIPPAGE = keccak256(abi.encodeWithSignature("SlippedMarketValue()")); // see test_21

    // Accept reverts array
    mapping(string => mapping(bytes32 => bool)) internal _ACCEPTED_REVERTS;

    function _initializeProperties() internal {
        // GENERAL 1 - No reverts allowed

        // GENERAL 5
        _ACCEPTED_REVERTS[_GENERAL_4.code][_ERR_INSUFF_LIQUIDITY_ROLL_01] = true;
        _ACCEPTED_REVERTS[_GENERAL_4.code][_ERR_INSUFF_LIQUIDITY_ROLL_02] = true;
        _ACCEPTED_REVERTS[_GENERAL_4.code][_ERR_INSUFF_LIQUIDITY_ROLL_03] = true;
        _ACCEPTED_REVERTS[_GENERAL_5.code][_ERR_EPOCH_NOT_FINISHED] = true;

        // GENERAL 6
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_NOT_ENOUGH_NOTIONAL] = true; // buy never more than notional available
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_EXCEEDS_AVAILABLE] = true; // sell never more than owned
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_INSUFFICIENT_INPUT] = true; // delta hedge can't be performed
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_PRICE_ZERO] = true; // option price is 0
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_INSUFF_LIQUIDITY_EDGE_01] = true; // delta hedge can't be performed
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_CHECK_SLIPPAGE] = true;
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_ASYMMETRIC_AMOUNT] = true;
    }
}
