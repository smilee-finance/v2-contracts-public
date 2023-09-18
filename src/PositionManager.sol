// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Position} from "./lib/Position.sol";
import {Epoch} from "./lib/EpochController.sol";

contract PositionManager is ERC721Enumerable, Ownable, IPositionManager {
    struct ManagedPosition {
        address dvpAddr;
        uint256 strike;
        uint256 expiry;
        uint256 notionalUp;
        uint256 notionalDown;
        uint256 premium;
        uint256 leverage; // TBD: should we keep it ?
        uint256 cumulatedPayoff; // TBD: should we keep it ? (payoff already paid)
    }

    /// @notice [TESTNET] Whether the transfer of tokens between wallets is allowed or not
    bool internal _secondaryMarkedAllowed;

    /// @dev Stored data by position ID
    mapping(uint256 => ManagedPosition) internal _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId;

    error ApproveFailed();
    error CantBurnMoreThanMinted();
    error InvalidTokenID();
    error NotOwner();
    error PositionExpired();
    error SecondaryMarkedNotAllowed();
    error TransferFailed();

    constructor() ERC721Enumerable() ERC721("Smilee V0 Trade Positions", "SMIL-V0-TRAD") Ownable() {
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

        Epoch memory epoch = dvp.getEpoch();

        // TBD: add payoff
        return
            IPositionManager.PositionDetail({
                dvpAddr: position.dvpAddr,
                baseToken: dvp.baseToken(),
                sideToken: dvp.sideToken(),
                dvpFreq: epoch.frequency,
                dvpType: dvp.optionType(),
                strike: position.strike,
                expiry: position.expiry,
                premium: position.premium,
                leverage: position.leverage,
                notionalUp: position.notionalUp,
                notionalDown: position.notionalDown,
                cumulatedPayoff: position.cumulatedPayoff
            });
    }

    /// @inheritdoc IPositionManager
    function mint(
        IPositionManager.MintParams calldata params
    ) external override returns (uint256 tokenId, uint256 premium) {
        IDVP dvp = IDVP(params.dvpAddr);

        if (params.tokenId != 0) {
            tokenId = params.tokenId;
            ManagedPosition storage position = _positions[tokenId];

            if (ownerOf(tokenId) != msg.sender) {
                revert NotOwner();
            }
            // Check token compatibility:
            if (position.dvpAddr != params.dvpAddr || position.strike != params.strike) {
                revert InvalidTokenID();
            }
            Epoch memory epoch = dvp.getEpoch();
            if (position.expiry != epoch.current) {
                revert PositionExpired();
            }
        }
        uint256 fee;
        (premium, fee) = dvp.premium(params.strike, params.notionalUp, params.notionalDown);

        // Transfer premium:
        // NOTE: The PositionManager is just a middleman between the user and the DVP
        IERC20 baseToken = IERC20(dvp.baseToken());
        bool ok = baseToken.transferFrom(msg.sender, address(this), premium);
        if (!ok) {
            revert TransferFailed();
        }

        // Premium already include fee
        ok = baseToken.approve(params.dvpAddr, premium);
        if (!ok) {
            revert ApproveFailed();
        }

        // TBD: add fees?
        premium = dvp.mint(
            address(this),
            params.strike,
            params.notionalUp,
            params.notionalDown,
            params.expectedPremium,
            params.maxSlippage
        );

        if (params.tokenId == 0) {
            // Mint token:
            tokenId = _nextId++;
            _mint(params.recipient, tokenId);

            Epoch memory epoch = dvp.getEpoch();

            // Save position:
            _positions[tokenId] = ManagedPosition({
                dvpAddr: params.dvpAddr,
                strike: params.strike,
                expiry: epoch.current,
                premium: premium,
                leverage: (params.notionalUp + params.notionalDown) / premium,
                notionalUp: params.notionalUp,
                notionalDown: params.notionalDown,
                cumulatedPayoff: 0
            });
        } else {
            ManagedPosition storage position = _positions[tokenId];
            // Increase position:
            position.premium += premium;
            position.notionalUp += params.notionalUp;
            position.notionalDown += params.notionalDown;
            /* NOTE:
                When, within the same epoch, a user wants to buy, sell partially
                and then buy again, the leverage computation can fail due to
                decreased notional; in order to avoid this issue, we have to
                also adjust (decrease) the premium in the burn flow.
             */
            position.leverage = (position.notionalUp + position.notionalDown) / position.premium;
        }

        emit BuyedDVP(tokenId, _positions[tokenId].expiry, params.notionalUp + params.notionalDown);
    }

    /// @inheritdoc IPositionManager
    function burn(uint256 tokenId) external override isOwner(tokenId) returns (uint256 payoff) {
        ManagedPosition storage position = _positions[tokenId];
        uint256 expectedMarketValue = 0;
        Epoch memory epoch = IDVP(position.dvpAddr).getEpoch();
        if (epoch.current == position.expiry) {
            (expectedMarketValue, ) = IDVP(position.dvpAddr).payoff(
                position.expiry,
                position.strike,
                position.notionalUp,
                position.notionalDown
            );
        }
        payoff = _sell(tokenId, position.notionalUp, position.notionalDown, expectedMarketValue, 0.1e18);
    }

    // ToDo: review usage and signature
    function sell(SellParams calldata params) external isOwner(params.tokenId) returns (uint256 payoff) {
        // TBD: burn if params.notional == 0 ?
        // TBD: burn if position is expired ?
        payoff = _sell(
            params.tokenId,
            params.notionalUp,
            params.notionalDown,
            params.expectedMarketValue,
            params.maxSlippage
        );
    }

    function _sell(
        uint256 tokenId,
        uint256 notionalUp,
        uint256 notionalDown,
        uint256 expectedMarketValue,
        uint256 maxSlippage
    ) internal returns (uint256 payoff) {
        ManagedPosition storage position = _positions[tokenId];
        // NOTE: as the positions within the DVP are all of the PositionManager, we must replicate this check here.
        if (notionalUp > position.notionalUp || notionalDown > position.notionalDown) {
            revert CantBurnMoreThanMinted();
        }

        // NOTE: the DVP already checks that the burned notional is lesser or equal to the position notional.
        // NOTE: the payoff is transferred directly from the DVP
        payoff = IDVP(position.dvpAddr).burn(
            position.expiry,
            msg.sender,
            position.strike,
            notionalUp,
            notionalDown,
            expectedMarketValue,
            maxSlippage
        );

        // NOTE: premium fix for the leverage issue annotated in the mint flow.
        // notional : position.notional = fix : position.premium
        uint256 premiumFix = ((notionalUp + notionalDown) * position.premium) /
            (position.notionalUp + position.notionalDown);
        position.premium -= premiumFix;
        position.cumulatedPayoff += payoff;
        position.notionalUp -= notionalUp;
        position.notionalDown -= notionalDown;

        if (position.notionalUp == 0 && position.notionalDown == 0) {
            delete _positions[tokenId];
            _burn(tokenId);
        }

        emit SoldDVP(tokenId, (notionalUp + notionalDown), payoff);
    }

    /// @inheritdoc ERC721Enumerable
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        if (from != address(0) && to != address(0) && !_secondaryMarkedAllowed) {
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
}
