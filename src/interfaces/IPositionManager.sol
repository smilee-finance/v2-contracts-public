// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/// @title Non-fungible token for positions
/// @notice Wraps Uniswap V3 positions in a non-fungible token interface which allows for them to be transferred
/// and authorized.
interface IPositionManager is IERC721Metadata, IERC721Enumerable {
    struct MintParams {
        address dvpAddr;
        uint256 notional;
        uint256 strike;
        bool strategy;
        address recipient;
    }

    struct SellParams {
        uint256 tokenId;
        uint256 notional;
    }

    struct PositionDetail {
        address dvpAddr;
        address baseToken;
        address sideToken;
        uint256 dvpFreq;
        uint256 dvpType;
        uint256 strike;
        bool strategy;
        uint256 expiry;
        uint256 premium;
        uint256 leverage;
        uint256 notional;
        uint256 cumulatedPayoff;
    }

    /**
        @notice Emitted when option notional is increased
        @dev Also emitted when a token is minted
        @param tokenId The ID of the token for which liquidity was increased
        @param expiry The maturity timestamp of the position
        @param notional The amount of token that is held by the position
     */
    event BuyedDVP(uint256 indexed tokenId, uint256 expiry, uint256 notional);

    /**
        @notice Emitted when option notional is decreased
        @param tokenId The ID of the token for which liquidity was decreased
        @param notional The amount by which liquidity for the NFT position was decreased
        @param payoff The amount of token that was paid back for burning the position
     */
    event SoldDVP(uint256 indexed tokenId, uint256 notional, uint256 payoff);

    /**
        @notice Returns the position information associated with a given token ID.
        @dev Throws if the token ID is not valid.
        @param tokenId The ID of the token that represents the position
        @return position The struct holding all position data
     */
    function positions(uint256 tokenId) external view returns (PositionDetail memory position);

    /**
        @notice Creates a new position wrapped in a NFT
        @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
        a method does not exist, i.e. the pool is assumed to be initialized.
        @param params The params necessary to mint a position, encoded as `MintParams` in calldata
        @return tokenId The ID of the token that represents the minted position
        @return notional The amount of liquidity held by this position
     */
    function mint(MintParams calldata params) external returns (uint256 tokenId, uint256 notional);

    // struct IncreaseLiquidityParams {
    //     uint256 tokenId;
    //     uint256 amount;
    //     // uint256 deadline;
    // }

    // /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    // /// @param params tokenId The ID of the token for which liquidity is being increased,
    // /// amount0Desired The desired amount of token0 to be spent,
    // /// amount1Desired The desired amount of token1 to be spent,
    // /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    // /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    // /// deadline The time by which the transaction must be included to effect the change
    // /// @return liquidity The new liquidity amount as a result of the increase
    // /// @return amount0 The amount of token0 to acheive resulting liquidity
    // /// @return amount1 The amount of token1 to acheive resulting liquidity
    // function increaseLiquidity(IncreaseLiquidityParams calldata params)
    //     external
    //     payable
    //     returns (
    //         uint128 liquidity,
    //         uint256 amount0,
    //         uint256 amount1
    //     );

    /**
        @notice Sell a portion of the option
        @dev If the held notional goes to zero, also deletes the NFT
        @param params tokenId The ID of the token representing the position
                      notional The quantity to sell from the position
        @return payoff The amount of baseToken paid to the owner of the position
     */
    function sell(SellParams calldata params) external returns (uint256 payoff);

    /**
        @notice Burns a token ID, which deletes it from the NFT contract. The option is completely sold before burn.
        @param tokenId The ID of the token that is being burned
        @return payoff The amount of baseToken paid to the owner of the position
     */
    function burn(uint256 tokenId) external returns (uint256 payoff);
}
