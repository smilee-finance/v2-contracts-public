// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {Position} from "./lib/Position.sol";

contract PositionManager is ERC721Enumerable, IPositionManager {
    // details about the Smilee position
    struct ManagedPosition {
        address dvpAddr;
        uint256 strategy;
        uint256 strike;
        uint256 premium;
        uint256 leverage;
        uint256 expiry;
    }

    /// @dev The token ID position data
    address private immutable _factory;

    /// @dev The token ID position data
    mapping(uint256 => ManagedPosition) private _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId;

    constructor(address factory_) ERC721("Smilee V0 Positions NFT-V1", "SMIL-V0-POS") {
        _factory = factory_;
        _nextId = 1;
    }

    /// @inheritdoc IPositionManager
    function positions(
        uint256 tokenId
    )
        external
        view
        override
        returns (
            address dvpAddr,
            address baseToken,
            address sideToken,
            uint256 dvpFreq,
            uint256 dvpType,
            uint256 strike,
            uint256 strategy,
            uint256 expiry,
            uint256 premium,
            uint256 leverage
        )
    {
        ManagedPosition memory position = _positions[tokenId];
        if (position.dvpAddr == address(0)) {
            revert InvalidTokenID();
        }

        IDVP dvp = IDVP(position.dvpAddr);

        return (
            position.dvpAddr,
            dvp.baseToken(),
            dvp.sideToken(),
            dvp.epochFrequency(),
            0, // dvp.dvpType(),
            position.strike,
            position.strategy,
            position.expiry,
            position.premium,
            position.leverage
        );
    }

    /// @inheritdoc IPositionManager
    function mint(MintParams calldata params) external override returns (uint256 tokenId, uint256 posLiquidity) {
        IDVP dvp = IDVP(params.dvpAddr);

        // ToDo: handle premium

        // Buy position:
        dvp.mint(address(this), params.strike, params.strategy, params.premium);

        // Mint token:
        tokenId = _nextId++;
        _mint(params.recipient, tokenId);

        uint256 leverage = 1;
        posLiquidity = params.premium * leverage;

        // Save position:
        _positions[tokenId] = ManagedPosition({
            dvpAddr: params.dvpAddr,
            strike: params.strike,
            strategy: params.strategy,
            expiry: dvp.currentEpoch(),
            premium: params.premium,
            leverage: leverage
        });

        // emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    // modifier isAuthorizedForToken(uint256 tokenId) {
    //     require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
    //     _;
    // }

    // function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
    //     require(_exists(tokenId));
    //     return INonfungibleTokenPositionDescriptor(_tokenDescriptor).tokenURI(this, tokenId);
    // }

    // // save bytecode by removing implementation of unused method
    // function baseURI() public pure override returns (string memory) {}

    // /// @inheritdoc IPositionManager
    // function increaseLiquidity(
    //     IncreaseLiquidityParams calldata params
    // )
    //     external
    //     payable
    //     override
    //     checkDeadline(params.deadline)
    //     returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    // {
    //     Position storage position = _positions[params.tokenId];

    //     PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

    //     IUniswapV3Pool pool;
    //     (liquidity, amount0, amount1, pool) = addLiquidity(
    //         AddLiquidityParams({
    //             token0: poolKey.token0,
    //             token1: poolKey.token1,
    //             fee: poolKey.fee,
    //             tickLower: position.tickLower,
    //             tickUpper: position.tickUpper,
    //             amount0Desired: params.amount0Desired,
    //             amount1Desired: params.amount1Desired,
    //             amount0Min: params.amount0Min,
    //             amount1Min: params.amount1Min,
    //             recipient: address(this)
    //         })
    //     );

    //     bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);

    //     // this is now updated to the current transaction
    //     (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

    //     position.tokensOwed0 += uint128(
    //         FullMath.mulDiv(
    //             feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
    //             position.liquidity,
    //             FixedPoint128.Q128
    //         )
    //     );
    //     position.tokensOwed1 += uint128(
    //         FullMath.mulDiv(
    //             feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
    //             position.liquidity,
    //             FixedPoint128.Q128
    //         )
    //     );

    //     position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
    //     position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
    //     position.liquidity += liquidity;

    //     emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    // }

    // /// @inheritdoc IPositionManager
    // function decreaseLiquidity(
    //     DecreaseLiquidityParams calldata params
    // )
    //     external
    //     payable
    //     override
    //     isAuthorizedForToken(params.tokenId)
    //     checkDeadline(params.deadline)
    //     returns (uint256 amount0, uint256 amount1)
    // {
    //     require(params.liquidity > 0);
    //     Position storage position = _positions[params.tokenId];

    //     uint128 positionLiquidity = position.liquidity;
    //     require(positionLiquidity >= params.liquidity);

    //     PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
    //     IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
    //     (amount0, amount1) = pool.burn(position.tickLower, position.tickUpper, params.liquidity);

    //     require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "Price slippage check");

    //     bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);
    //     // this is now updated to the current transaction
    //     (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

    //     position.tokensOwed0 +=
    //         uint128(amount0) +
    //         uint128(
    //             FullMath.mulDiv(
    //                 feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
    //                 positionLiquidity,
    //                 FixedPoint128.Q128
    //             )
    //         );
    //     position.tokensOwed1 +=
    //         uint128(amount1) +
    //         uint128(
    //             FullMath.mulDiv(
    //                 feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
    //                 positionLiquidity,
    //                 FixedPoint128.Q128
    //             )
    //         );

    //     position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
    //     position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
    //     // subtraction is safe because we checked positionLiquidity is gte params.liquidity
    //     position.liquidity = positionLiquidity - params.liquidity;

    //     emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    // }

    // /// @inheritdoc IPositionManager
    // function collect(
    //     CollectParams calldata params
    // ) external payable override isAuthorizedForToken(params.tokenId) returns (uint256 amount0, uint256 amount1) {
    //     require(params.amount0Max > 0 || params.amount1Max > 0);
    //     // allow collecting to the nft position manager address with address 0
    //     address recipient = params.recipient == address(0) ? address(this) : params.recipient;

    //     Position storage position = _positions[params.tokenId];

    //     PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

    //     IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

    //     (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);

    //     // trigger an update of the position fees owed and fee growth snapshots if it has any liquidity
    //     if (position.liquidity > 0) {
    //         pool.burn(position.tickLower, position.tickUpper, 0);
    //         (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(
    //             PositionKey.compute(address(this), position.tickLower, position.tickUpper)
    //         );

    //         tokensOwed0 += uint128(
    //             FullMath.mulDiv(
    //                 feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
    //                 position.liquidity,
    //                 FixedPoint128.Q128
    //             )
    //         );
    //         tokensOwed1 += uint128(
    //             FullMath.mulDiv(
    //                 feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
    //                 position.liquidity,
    //                 FixedPoint128.Q128
    //             )
    //         );

    //         position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
    //         position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
    //     }

    //     // compute the arguments to give to the pool#collect method
    //     (uint128 amount0Collect, uint128 amount1Collect) = (
    //         params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max,
    //         params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max
    //     );

    //     // the actual amounts collected are returned
    //     (amount0, amount1) = pool.collect(
    //         recipient,
    //         position.tickLower,
    //         position.tickUpper,
    //         amount0Collect,
    //         amount1Collect
    //     );

    //     // sometimes there will be a few less wei than expected due to rounding down in core, but we just subtract the full amount expected
    //     // instead of the actual amount so we can burn the token
    //     (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);

    //     emit Collect(params.tokenId, recipient, amount0Collect, amount1Collect);
    // }

    // /// @inheritdoc IPositionManager
    // function burn(uint256 tokenId) external payable override isAuthorizedForToken(tokenId) {
    //     Position storage position = _positions[tokenId];
    //     require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, "Not cleared");
    //     delete _positions[tokenId];
    //     _burn(tokenId);
    // }

    // function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
    //     return uint256(_positions[tokenId].nonce++);
    // }

    // /// @inheritdoc IERC721
    // function getApproved(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
    //     require(_exists(tokenId), "ERC721: approved query for nonexistent token");

    //     return _positions[tokenId].operator;
    // }

    // /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    // function _approve(address to, uint256 tokenId) internal override(ERC721) {
    //     _positions[tokenId].operator = to;
    //     emit Approval(ownerOf(tokenId), to, tokenId);
    // }
}
