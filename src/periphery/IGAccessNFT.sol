// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IDVPAccessNFT} from "../interfaces/IDVPAccessNFT.sol";

/**
    @title Simple implementation of IDVPAccessNFT

    An example implementation of the priority access tokens for Smilee DVPs.
 */
contract IGAccessNFT is IDVPAccessNFT, ERC721Enumerable, AccessControl {
    uint256 private _currentId = 0;
    mapping(uint256 => uint256) private _capAmount;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    error NotionalCapExceeded();

    constructor() ERC721Enumerable() ERC721("Smilee Trade Priority Access Token", "STPT") AccessControl() {
        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC721Enumerable, IERC165) returns (bool) {
        return ERC721Enumerable.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }

    /**
        @notice Creates a token
        @param receiver The accounting wallet for this token
        @param capAmount_ The amount of notional `receiver` will be allowed to trade in DVP.
        @return tokenId The numerical ID of the minted token
     */
    function createToken(address receiver, uint256 capAmount_) external returns (uint tokenId) {
        _checkRole(ROLE_ADMIN);

        tokenId = ++_currentId;
        _capAmount[tokenId] = capAmount_;

        _mint(receiver, tokenId);
    }

    /**
        @notice Destroy a token
        @param tokenId The numerical ID of the token to burn
     */
    function destroyToken(uint256 tokenId) external {
        _checkRole(ROLE_ADMIN);
        _requireMinted(tokenId);

        _burn(tokenId);
    }

    /// @inheritdoc IDVPAccessNFT
    function capAmount(uint256 tokenId) external view returns (uint256 amount) {
        _requireMinted(tokenId);

        return _capAmount[tokenId];
    }

    /// @inheritdoc IDVPAccessNFT
    function checkCap(uint256 tokenId, uint256 amount) external view {
        _requireMinted(tokenId);

        if (amount > _capAmount[tokenId]) {
            revert NotionalCapExceeded();
        }
    }
}
