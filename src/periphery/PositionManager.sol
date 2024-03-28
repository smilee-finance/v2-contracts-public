// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IDVP} from "../interfaces/IDVP.sol";
import {IDVPAccessNFT} from "../interfaces/IDVPAccessNFT.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {Epoch} from "../lib/EpochController.sol";

contract PositionManager is ERC721Enumerable, AccessControl, IPositionManager {
    using SafeERC20 for IERC20;

    struct ManagedPosition {
        address dvpAddr;
        uint256 strike;
        uint256 expiry;
        uint256 notionalUp;
        uint256 notionalDown;
        uint256 premium;
        uint256 leverage;
        uint256 cumulatedPayoff;
    }

    /// @dev Stored data by position ID
    mapping(uint256 => ManagedPosition) internal _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId;

    /// @notice A flag to tell if this PosMan is currently bound to check access for trade
    bool public nftAccessFlag;

    IAddressProvider internal immutable _addressProvider;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    // Used by TheGraph for frontend needs:
    event Buy(address dvp, uint256 epoch, uint256 premium, address creditor);
    event Sell(address dvp, uint256 epoch, uint256 payoff);

    error CantBurnMoreThanMinted();
    error InvalidTokenID();
    error NotOwner();
    error PositionExpired();
    error AsymmetricAmount();
    error NFTAccessDenied();
    error ZeroAddress();
    error NotRegistered();

    constructor(
        address addressProvider
    ) ERC721Enumerable() ERC721("Smilee DVP Position", "SMIL-DVP-POS") AccessControl() {
        _nextId = 1;
        nftAccessFlag = false;
        _addressProvider = IAddressProvider(addressProvider);

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
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

    /**
        @notice Allows the contract's admin to enable or disable the nft-based priority access to trade operations
     */
    function setNftAccessFlag(bool flag) external {
        _checkRole(ROLE_ADMIN);
        nftAccessFlag = flag;
    }

    /// @inheritdoc IPositionManager
    function positionDetail(uint256 tokenId) external view override returns (IPositionManager.PositionDetail memory) {
        ManagedPosition memory position = _positions[tokenId];
        if (position.dvpAddr == address(0)) {
            revert InvalidTokenID();
        }

        IDVP dvp = IDVP(position.dvpAddr);

        Epoch memory epoch = dvp.getEpoch();

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

    /// @dev Checks if given trade is allowed to be made
    function _checkNFTAccess(uint256 tokenId, address receiver, uint256 notionalAmount) internal {
        if (!nftAccessFlag) {
            return;
        }

        IDVPAccessNFT nft = IDVPAccessNFT(_addressProvider.dvpAccessNFT());
        if (tokenId == 0 || nft.ownerOf(tokenId) != receiver) {
            revert NFTAccessDenied();
        }
        nft.checkCap(tokenId, notionalAmount);
    }

    function _checkRegisteredDVP(address dvp) internal view {
        address registryAddr = _addressProvider.registry();
        if (registryAddr == address(0)) {
            revert ZeroAddress();
        }

        if (!IRegistry(registryAddr).isRegistered(dvp)) {
            revert NotRegistered();
        }
    }

    /// @inheritdoc IPositionManager
    function mint(
        IPositionManager.MintParams calldata params
    ) external override returns (uint256 tokenId, uint256 premium) {
        _checkRegisteredDVP(params.dvpAddr);
        IDVP dvp = IDVP(params.dvpAddr);

        _checkNFTAccess(params.nftAccessTokenId, msg.sender, params.notionalUp + params.notionalDown);

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
            {
                bool posIsBull = position.notionalUp > 0 && position.notionalDown == 0;
                if (posIsBull && params.notionalDown > 0) {
                    revert AsymmetricAmount();
                }
                bool posIsBear = position.notionalUp == 0 && position.notionalDown > 0;
                if (posIsBear && params.notionalUp > 0) {
                    revert AsymmetricAmount();
                }
                bool posIsSmile = position.notionalUp > 0 && position.notionalDown > 0;
                if (posIsSmile && params.notionalUp != params.notionalDown) {
                    revert AsymmetricAmount();
                }
            }
        } else {
            bool tradeIsSmile = params.notionalUp > 0 && params.notionalDown > 0;
            if (tradeIsSmile && (params.notionalUp != params.notionalDown)) {
                // If amount is a smile, it must be balanced:
                revert AsymmetricAmount();
            }
        }

        uint256 spending = params.expectedPremium + (params.expectedPremium * params.maxSlippage) / 1e18;

        // Transfer premium:
        // NOTE: The PositionManager is just a middleman between the user and the DVP
        IERC20 baseToken = IERC20(dvp.baseToken());
        baseToken.safeTransferFrom(msg.sender, address(this), spending);
        baseToken.safeApprove(params.dvpAddr, spending);

        premium = dvp.mint(
            address(this),
            params.strike,
            params.notionalUp,
            params.notionalDown,
            params.expectedPremium,
            params.maxSlippage
        );

        if (spending > premium) {
            baseToken.safeTransfer(msg.sender, spending - premium);
        }

        // clear allowance
        baseToken.safeApprove(params.dvpAddr, 0);

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

        emit BuyDVP(tokenId, _positions[tokenId].expiry, params.notionalUp + params.notionalDown);
        emit Buy(params.dvpAddr, _positions[tokenId].expiry, premium, params.recipient);
    }

    function payoff(
        uint256 tokenId,
        uint256 notionalUp,
        uint256 notionalDown
    ) external view returns (uint256 payoff_, uint256 fee) {
        ManagedPosition storage position = _positions[tokenId];
        uint256 premiumProp = ((notionalUp + notionalDown) * position.premium) /
            (position.notionalUp + position.notionalDown);

        return IDVP(position.dvpAddr).payoff(position.expiry, position.strike, notionalUp, notionalDown, premiumProp);
    }

    function sell(SellParams calldata params) external isOwner(params.tokenId) returns (uint256 payoff_) {
        payoff_ = _sell(
            params.tokenId,
            params.notionalUp,
            params.notionalDown,
            params.expectedMarketValue,
            params.maxSlippage
        );
    }

    function sellAll(SellParams[] calldata params) external returns (uint256 totalPayoff_) {
        uint256 paramsLength = params.length;
        for (uint256 i = 0; i < paramsLength; i++) {
            if (ownerOf(params[i].tokenId) != msg.sender) {
                revert NotOwner();
            }
            totalPayoff_ += _sell(
                params[i].tokenId,
                params[i].notionalUp,
                params[i].notionalDown,
                params[i].expectedMarketValue,
                params[i].maxSlippage
            );
        }
    }

    function _sell(
        uint256 tokenId,
        uint256 notionalUp,
        uint256 notionalDown,
        uint256 expectedMarketValue,
        uint256 maxSlippage
    ) internal returns (uint256 payoff_) {
        ManagedPosition storage position = _positions[tokenId];
        // NOTE: as the positions within the DVP are all of the PositionManager, we must replicate this check here.
        if (notionalUp > position.notionalUp || notionalDown > position.notionalDown) {
            revert CantBurnMoreThanMinted();
        }

        if ((notionalUp > 0 && notionalDown > 0) && (notionalUp != notionalDown)) {
            // If amount is a smile, it must be balanced:
            revert AsymmetricAmount();
        }

        // NOTE: premium fix for the leverage issue annotated in the mint flow.
        // notional : position.notional = fix : position.premium
        uint256 premiumProp = ((notionalUp + notionalDown) * position.premium) /
            (position.notionalUp + position.notionalDown);

        // NOTE: the DVP already checks that the burned notional is lesser or equal to the position notional.
        // NOTE: the payoff is transferred directly from the DVP
        payoff_ = IDVP(position.dvpAddr).burn(
            position.expiry,
            msg.sender,
            position.strike,
            notionalUp,
            notionalDown,
            expectedMarketValue,
            maxSlippage,
            premiumProp
        );

        position.premium -= premiumProp;
        position.cumulatedPayoff += payoff_;
        position.notionalUp -= notionalUp;
        position.notionalDown -= notionalDown;

        emit Sell(position.dvpAddr, position.expiry, payoff_);

        if (position.notionalUp == 0 && position.notionalDown == 0) {
            delete _positions[tokenId];
            _burn(tokenId);
        }

        emit SellDVP(tokenId, (notionalUp + notionalDown), payoff_);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, ERC721Enumerable, IERC165) returns (bool) {
        return ERC721Enumerable.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }
}
