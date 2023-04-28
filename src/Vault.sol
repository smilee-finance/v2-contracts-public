// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {IVault} from "./interfaces/IVault.sol";

// TBD: implement the IERC4626 interface for the locked liquidity bucket ?

contract Vault is ERC1155Supply, IVault {
    address public dvpAddr;
    address public immutable baseToken;
    address public immutable sideToken;
    /// @dev Used as internal token_id within the ERC1155 implementation.
    uint256 internal lockedLiquidityBucket;
    /// @dev Used as internal token_id within the ERC1155 implementation.
    uint256 internal unlockedLiquidityBucket;

    error OnlyDVPAllowed();
    error LiquidityIsLocked();

    constructor (
        address baseToken_,
        address sideToken_
    ) ERC1155("") {
        baseToken = baseToken_;
        sideToken = sideToken_;
        lockedLiquidityBucket = 0;
        unlockedLiquidityBucket = 1;
        // TBD: make it ownable in order to set the DVP address
    }

    modifier onlyDVP() {
        if (msg.sender != dvpAddr) {
            revert OnlyDVPAllowed();
        }
        _;
    }

    function getPortfolio() public view override returns (uint256 baseTokenAmount, uint256 sideTokenAmount) {
        baseTokenAmount = totalSupply(lockedLiquidityBucket);
        sideTokenAmount = IERC20(sideToken).balanceOf(address(this));
    }

    function deposit(uint256 amount) external {
        IERC20(baseToken).transferFrom(msg.sender, address(this), amount);

        // Mint "shares":
        _mint(msg.sender, unlockedLiquidityBucket, amount, "");
    }

    function triggerEpochChange() external override onlyDVP {
        // TBD: what else to do

        // Switch the internal ERC1155 buckets (token IDs):
        uint256 tmp = lockedLiquidityBucket;
        lockedLiquidityBucket = unlockedLiquidityBucket;
        unlockedLiquidityBucket = tmp;
    }

    /// @inheritdoc ERC1155
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        if (id == lockedLiquidityBucket && to != dvpAddr) {
            revert LiquidityIsLocked();
        }
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /// @inheritdoc ERC1155
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (ids[i] == lockedLiquidityBucket && to != dvpAddr) {
                revert LiquidityIsLocked();
            }
        }
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }
}
