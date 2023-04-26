// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVPEvents} from "./IDVPEvents.sol";
import {IDVPImmutables} from "./IDVPImmutables.sol";
import {Position} from "../lib/Position.sol";

/// @title The interface for Smilee DVP
/// @notice A DVP (Decentralized Volatility Product) is basically a generator for options on volatility
interface IDVP is IDVPImmutables, IDVPEvents {
    ////// STATE

    /**
        @notice Returns the information about a position by the position's key
        @param key The position's key [TODO]
        @return amount The amount of liquidity in the position,
        @return strategy The strategy of the position,
        @return strike The strike price of the position
     */
    function positions(
        bytes32 key
    ) external view returns (uint256 amount, uint256 strategy, uint256 strike, uint256 epoch);

    /**
        @notice Returns the pool providing liquidity for these DVP options
        @return provider The address location of the provider contract
     */
    function liquidityProvider() external view returns (address);

    /**
        @notice Returns the current price for one option, in function of the time and the number of options still
        available
        @param strike The strike price the user wants to mint
        @param strategy The option type
        @param amount The amount of options to be paid
        @return premium The amount of base tokens that need to be paid to mint an option
     */
    function premium(uint256 strike, uint256 strategy, uint256 amount) external view returns (uint256 premium);

    /**
        @notice Returns the payoff of the given position
        @param key The hash identifying the position
        @return payoff The current value of the position
     */
    function payoff(bytes32 key) external view returns (uint256 payoff);

    ////// USER ACTIONS

    /**
        @notice Creates an option with the given strategy
        @param recipient The address for which the option will be created
        @param strike The strike price for the minted option
        @dev strike param is ignored for IG vaults, can pass 0
        @param strategy The selected strategy
        @param amount The integer quantity of options recipient wants to mint
     */
    function mint(address recipient, uint256 strike, uint256 strategy, uint256 amount) external;

    /// @notice Burns an option transferring back the payoff to the owner
    /// TODO
    function burn(uint256 epoch, address recipient, uint256 strike, uint256 strategy, uint256 amount) external;

    ////// ERRORS

    error AmountZero();
}
