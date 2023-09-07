// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVaultProxy} from "./interfaces/IVaultProxy.sol";

contract VaultProxy is IVaultProxy {
    address private _registry;

    error DepositToNonVaultContract();

    // ToDo: replace injected registry with address provider
    constructor(address registry) {
        _registry = registry;
    }

    /// @inheritdoc IVaultProxy
    function deposit(DepositParams calldata params) external {
        // ToDo: review as the vault is not registered; only DVPs
        if (!IRegistry(_registry).isRegistered(params.vault)) {
            revert DepositToNonVaultContract();
        }

        IVault vault = IVault(params.vault);
        IERC20(vault.baseToken()).transferFrom(msg.sender, address(this), params.amount);
        IERC20(vault.baseToken()).approve(params.vault, params.amount);
        vault.deposit(params.amount, params.recipient);

        emit Deposit(params.vault, params.recipient, msg.sender, params.amount);
    }
}
