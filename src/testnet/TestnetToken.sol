// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {AdminAccess} from "./AdminAccess.sol";
import {Factory} from "../Factory.sol";


/**
    @notice Token contract to be used under testing condition.
            Allows admin and dedicated contracts to mint and burn as many tokens as needed.
    @dev Transfer is blocked between wallets and only allowed from wallets to Liquidity Vaults and DVPs and viceversa.
         A Swapper contract is authorized to mint and burn tokens to simulate an exchange.
 */
contract TestnetToken is ERC20, AdminAccess {
    IRegistry private _controller;
    address private _swapper;

    error NotInitialized();
    error Unauthorized();

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) AdminAccess(msg.sender) {}

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

    modifier mintBurnAuth() {
        if (msg.sender != Admin && msg.sender != _swapper) {
            revert Unauthorized();
        }
        _;
    }

    modifier transferAuth(address from, address to) {
        if (
            msg.sender != Admin &&
            from != address(_controller) &&
            to != address(_controller) &&
            !_controller.isRegistered(from) &&
            !_controller.isRegistered(to)
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

    function setController(address controllerAddr) external onlyAdmin {
        _controller = Factory(controllerAddr);
    }

    function setSwapper(address swapper) external onlyAdmin {
        _swapper = swapper;
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override initialized transferAuth(msg.sender, to) returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override initialized transferAuth(from, to) returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    function _burn(address account, uint256 amount) internal virtual override initialized mintBurnAuth {
        super._burn(account, amount);
    }

    function _mint(address account, uint256 amount) internal virtual override initialized mintBurnAuth {
        super._mint(account, amount);
    }
}
