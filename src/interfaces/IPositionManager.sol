// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
    @title Non-fungible token for trade positions
    @notice Wraps trade positions in a NFT interface which allows for them to be created from
            a single entry point and transferred
 */
interface IPositionManager is IERC721Metadata, IERC721Enumerable {
    struct MintParams {
        uint256 tokenId;
        address dvpAddr;
        uint256 notionalUp;
        uint256 notionalDown;
        uint256 strike;
        address recipient;
        uint256 expectedPremium;
        uint256 maxSlippage;
        uint256 nftAccessTokenId;
    }

    struct SellParams {
        uint256 tokenId;
        uint256 notionalUp;
        uint256 notionalDown;
        uint256 expectedMarketValue;
        uint256 maxSlippage;
    }

    struct PositionDetail {
        address dvpAddr;
        address baseToken;
        address sideToken;
        uint256 dvpFreq;
        bool dvpType;
        uint256 strike;
        uint256 expiry;
        uint256 premium;
        uint256 leverage;
        uint256 notionalUp;
        uint256 notionalDown;
        uint256 cumulatedPayoff;
    }

    /**
        @notice Emitted when option notional is increased
        @dev Also emitted when a token is minted
        @param tokenId The ID of the token for which liquidity was increased
        @param expiry The maturity timestamp of the position
        @param notional The amount of token that is held by the position
     */
    event BuyDVP(uint256 indexed tokenId, uint256 expiry, uint256 notional);

    /**
        @notice Emitted when option notional is decreased
        @param tokenId The ID of the token for which liquidity was decreased
        @param notional The amount by which liquidity for the NFT position was decreased
        @param payoff The amount of token that was paid back for burning the position
     */
    event SellDVP(uint256 indexed tokenId, uint256 notional, uint256 payoff);

    /**
        @notice Returns the position information associated with a given token ID.
        @dev Throws if the token ID is not valid.
        @param tokenId The ID of the token that represents the position
        @return position The struct holding all position data
     */
    function positionDetail(uint256 tokenId) external view returns (PositionDetail memory position);

    /**
        @notice Creates a new position wrapped in a NFT
        @dev Need spending to already be approved taking into account a tolerance margin made explicit in the input parameters (`maxSlippage`)
        @param params The params necessary to mint a position, encoded as `MintParams` in calldata
        @return tokenId The ID of the token that represents the minted position
        @return notional The amount of liquidity held by this position
     */
    function mint(MintParams calldata params) external returns (uint256 tokenId, uint256 notional);

    /**
        @notice Sell a portion of the option
        @dev If the held notional goes to zero, also deletes the NFT
        @param params tokenId The ID of the token representing the position
                      notional The quantity to sell from the position
        @return payoff_ The amount of baseToken paid to the owner of the position
     */
    function sell(SellParams calldata params) external returns (uint256 payoff_);

    /**
        @notice Sell all the notional of a list of positions also deleting the NFTs
        @param params Array of tokenId The ID of the token representing the position
                      notional The quantity to sell from the position
        @return payoff_ The amount of baseToken paid to the owner of the position
     */
    function sellAll(SellParams[] calldata params) external returns (uint256 payoff_);
}
