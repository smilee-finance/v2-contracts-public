// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IVaultAccessNFT} from "../interfaces/IVaultAccessNFT.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
    @title Simple implementation of IVaultAccessNFT

    An example implementation of the priority access tokens for Smilee vaults.
 */
contract VaultAccessNFT is IVaultAccessNFT, ERC721, Ownable {
    uint256 private _currentId = 0;
    mapping(uint256 => uint256) private _priorityDeposit;
    IAddressProvider private immutable _ap;

    error CallerNotVault();
    error ExceedsAvailable();

    constructor(address addressProvider) ERC721("Smilee Vault Priority Access Token", "SPT") Ownable() {
        _ap = IAddressProvider(addressProvider);
    }

    /**
        @notice Creates a token
        @param receiver The accounting wallet for this token
        @param priorityDeposit The amount `receiver` will be allowed to deposit in Vaults with priority access
        @return tokenId The numerical ID of the minted token
     */
    function createToken(address receiver, uint256 priorityDeposit) public onlyOwner returns (uint tokenId) {
        tokenId = ++_currentId;
        _priorityDeposit[tokenId] = priorityDeposit;
        _mint(receiver, tokenId);
    }

    /// @inheritdoc IVaultAccessNFT
    function priorityAmount(uint256 tokenId) external view returns (uint256 amount) {
        _requireMinted(tokenId);
        return _priorityDeposit[tokenId];
    }

    /// @inheritdoc IVaultAccessNFT
    function decreasePriorityAmount(uint256 tokenId, uint256 amount) external {
        if (!IRegistry(_ap.registry()).isRegisteredVault(msg.sender)) {
            revert CallerNotVault();
        }

        if (amount > _priorityDeposit[tokenId]) {
            revert ExceedsAvailable();
        }

        _priorityDeposit[tokenId] -= amount;
        if (_priorityDeposit[tokenId] == 0) {
            _burn(tokenId);
        }
    }
}
