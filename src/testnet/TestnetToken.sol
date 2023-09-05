// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IRegistry} from "../interfaces/IRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
    @notice Token contract to be used under testnet condition.
    @dev Transfer is blocked between wallets and only allowed from wallets to
         Liquidity Vaults and DVPs and viceversa. A swapper contract is to mint
         and burn tokens to simulate an exchange.
 */
contract TestnetToken is ERC20, Ownable {
    // TBD: just use the TestnetRegistry contract...

    bool _transferRestricted;
    IRegistry private _controller;
    address private _swapper;

    error NotInitialized();
    error Unauthorized();

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable() {
        _transferRestricted = true;
    }

    /// MODIFIERS ///

    modifier initialized() {
        if (address(_controller) == address(0)) {
            revert NotInitialized();
        }
        if (_swapper == address(0)) {
            revert NotInitialized();
        }
        _;
    }

    modifier checkMintBurnRestriction() {
        if (msg.sender != owner() && msg.sender != _swapper) {
            revert Unauthorized();
        }
        _;
    }

    modifier checkTransferRestriction(address from, address to) {
        if (
            _transferRestricted &&
            (msg.sender != owner() && !_controller.isRegistered(from) && !_controller.isRegistered(to))
        ) {
            revert Unauthorized();
        }
        _;
    }

    /// LOGIC ///

    function getController() external view returns (address) {
        return address(_controller);
    }

    function getSwapper() external view returns (address) {
        return _swapper;
    }

    function setController(address controllerAddr) external onlyOwner {
        _controller = IRegistry(controllerAddr);
    }

    function setSwapper(address swapper) external onlyOwner {
        _swapper = swapper;
    }

    function setTransferRestriction(bool restricted) external onlyOwner {
        _transferRestricted = restricted;
    }

    function burn(address account, uint256 amount) external initialized checkMintBurnRestriction {
        _burn(account, amount);
    }

    function mint(address account, uint256 amount) external initialized checkMintBurnRestriction {
        _mint(account, amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override initialized checkTransferRestriction(msg.sender, to) returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override initialized checkTransferRestriction(from, to) returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}
