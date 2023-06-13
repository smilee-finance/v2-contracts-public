// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {Position} from "./lib/Position.sol";

contract PositionManager is ERC721Enumerable, Ownable, IPositionManager {
    struct ManagedPosition {
        address dvpAddr;
        bool strategy;
        uint256 strike;
        uint256 expiry;
        uint256 notional;
        uint256 premium; // TBD: should we keep it ?
        uint256 leverage; // TBD: should we keep it ?
        uint256 cumulatedPayoff; // TBD: should we keep it ?
    }

    /// @notice Whether the transfer of tokens between wallets is allowed or not
    bool internal _secondaryMarkedAllowed;

    /// @dev The token ID position data
    mapping(uint256 => ManagedPosition) internal _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId;

    error NotOwner();
    // error CantBurnZero();
    // error CantBurnMoreThanMinted();
    error InvalidTokenID();
    error SecondaryMarkedNotAllowed();

    constructor() ERC721("Smilee V0 Positions NFT-V1", "SMIL-V0-POS") Ownable() {
        _nextId = 1;
    }

    modifier isOwner(uint256 tokenId) {
        if (ownerOf(tokenId) != msg.sender) {
            revert NotOwner();
        }
        _;
    }

    // modifier isAuthorizedForToken(uint256 tokenId) {
    //     if (!_isApprovedOrOwner(msg.sender, tokenId)) {
    //         revert NotApproved();
    //     }
    //     _;
    // }

    /// @inheritdoc IPositionManager
    function positionDetail(uint256 tokenId) external view override returns (IPositionManager.PositionDetail memory) {
        ManagedPosition memory position = _positions[tokenId];
        if (position.dvpAddr == address(0)) {
            revert InvalidTokenID();
        }

        IDVP dvp = IDVP(position.dvpAddr);

        return
            IPositionManager.PositionDetail(
                position.dvpAddr,
                dvp.baseToken(),
                dvp.sideToken(),
                dvp.epochFrequency(),
                dvp.optionType(),
                position.strike,
                position.strategy,
                position.expiry,
                position.premium,
                position.leverage,
                position.notional,
                position.cumulatedPayoff
            );
    }
    
    /// @inheritdoc IPositionManager
    function mint(IPositionManager.MintParams calldata params) external override returns (uint256 tokenId, uint256 premium) {
        IDVP dvp = IDVP(params.dvpAddr);

        premium = dvp.premium(params.strike, params.strategy, params.notional);

        // Transfer premium:
        // NOTE: The PositionManager is just a middleman between the user and the DVP
        IERC20 baseToken = IERC20(dvp.baseToken());
        baseToken.transferFrom(msg.sender, address(this), premium);
        baseToken.approve(params.dvpAddr, premium);

        // Buy the option:
        premium = dvp.mint(address(this), params.strike, params.strategy, params.notional);
        uint256 leverage = params.notional / premium;

        // Mint token:
        tokenId = _nextId++;
        _mint(params.recipient, tokenId);

        // Save position:
        _positions[tokenId] = ManagedPosition({
            dvpAddr: params.dvpAddr,
            strike: params.strike,
            strategy: params.strategy,
            expiry: dvp.currentEpoch(),
            premium: premium,
            leverage: leverage,
            notional: params.notional,
            cumulatedPayoff: 0
        });

        emit BuyedDVP(tokenId, _positions[tokenId].expiry, params.notional);
    }

    /// @inheritdoc IPositionManager
    function burn(uint256 tokenId) external override isOwner(tokenId) returns (uint256 payoff) {
        ManagedPosition storage position = _positions[tokenId];
        payoff = _sell(tokenId, position.notional);
    }

    // ToDo: review usage and signature
    function sell(SellParams calldata params) external returns (uint256 payoff) {
        // TBD: burn if params.notional == 0 ?
        payoff = _sell(params.tokenId, params.notional);
    }

    function _sell(uint256 tokenId, uint256 notional) internal returns (uint256 payoff) {
        // if (notional == 0) {
        //     revert CantBurnZero();
        // }

        // // ToDo: review as the check is already done by the DVP
        // if (notional > position.notional) {
        //     revert CantBurnMoreThanMinted();
        // }

        ManagedPosition storage position = _positions[tokenId];

        // NOTE: the DVP already checks that the burned notional is lesser or equal to the position notional.
        // NOTE: the payoff is transferred directly from the DVP
        payoff = IDVP(position.dvpAddr).burn(position.expiry, msg.sender, position.strike, position.strategy, notional);

        position.cumulatedPayoff += payoff;
        position.notional -= notional;

        if (position.notional == 0) {
            delete _positions[tokenId];
            _burn(tokenId);
        }

        emit SoldDVP(tokenId, notional, payoff);
    }

    /// @inheritdoc ERC721Enumerable
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        if (from == address(0) || to == address(0)) {
            // it's a valid mint/burn
            return;
        }
        // if (from == address(this) || to == address(this)) {
        //     // it's a valid operation
        //     return;
        // }
        if (!_secondaryMarkedAllowed) {
            revert SecondaryMarkedNotAllowed();
        }
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    /**
        @notice Allows the contract's owner to enable or disable the secondary market for the position's tokens.
     */
    function setAllowedSecondaryMarked(bool allowed) external onlyOwner {
        _secondaryMarkedAllowed = allowed;
    }

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

}
