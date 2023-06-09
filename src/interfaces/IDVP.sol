// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVPEvents} from "./IDVPEvents.sol";
import {IDVPImmutables} from "./IDVPImmutables.sol";
import {IEpochControls} from "./IEpochControls.sol";

/// @title The interface for Smilee DVP
/// @notice A DVP (Decentralized Volatility Product) is basically a generator for options on volatility
interface IDVP is IDVPImmutables, IDVPEvents, IEpochControls {
    ////// ERRORS
    error AmountZero();
    error InvalidStrategy();

    // /**
    //     @notice Returns the information about a position by the position's key
    //     @param positionID The position's key [TODO]
    //     @return amount The amount of liquidity in the position,
    //     @return strategy The strategy of the position,
    //     @return strike The strike price of the position
    //  */
    // function positions(
    //     bytes32 positionID
    // ) external view returns (uint256 amount, bool strategy, uint256 strike, uint256 epoch);

    /**
        @notice Returns the pool providing liquidity for these DVP options
        @return provider The address location of the provider contract
     */
    function vault() external view returns (address);

    /**
        @notice Returns the current price for the given option amount, function of time and available underlying assets
        @param strike The strike price the user wants to mint
        @param strategy The option type
        @param amount The amount of options to be paid
        @return premium The amount of base tokens that need to be paid to mint an option
     */
    function premium(uint256 strike, bool strategy, uint256 amount) external view returns (uint256 premium);

    /**
        @notice Returns the payoff of the given position
        @param epoch The epoch
        @param strike The strike price of the option
        @param strategy The selected strategy
        @param positionAmount The position amount used to compute payoff
        @return payoff The current value of the position
     */
    function payoff(uint256 epoch, uint256 strike, bool strategy, uint256 positionAmount) external view returns (uint256);

    ////// USER ACTIONS

    /**
        @notice Creates an option with the given strategy
        @param recipient The address for which the option will be created
        @param strike The strike price for the minted option
        @param strategy The selected strategy
        @param amount The integer quantity of options recipient wants to mint
        @return leverage The multiplier to obtain position notional from paid premium
        @dev strike param is ignored for IG vaults, can pass 0
     */
    function mint(address recipient, uint256 strike, bool strategy, uint256 amount) external returns (uint256 leverage);

    /**
        @notice Burns an option transferring back the payoff to the owner.
        @param epoch The maturity timestamp of the option.
        @param recipient The address of the wallet that will receive the payoff, if any.
        @param strike The strike price of the burned option.
        @param strategy The strategy of the burned option.
        @param amount The amount of notional to be burned.
        @return paidPayoff The amount of paid payoff.
        @dev After maturity, the amount parameter is ignored and all the option is burned.
     */
    function burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) external returns (uint256 paidPayoff);
}
