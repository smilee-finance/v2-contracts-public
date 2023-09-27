// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAddressProvider} from "./interfaces/IAddressProvider.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVaultProxy} from "./interfaces/IVaultProxy.sol";

contract VaultProxy is IVaultProxy {
    address private _addressProvider;

    error ApproveFailed();
    error DepositToNonVaultContract();
    error TransferFailed();

    constructor(address provider) {
        _addressProvider = provider;
    }

    /// @inheritdoc IVaultProxy
    function deposit(DepositParams calldata params) external {
        IRegistry registry = IRegistry(IAddressProvider(_addressProvider).registry());
        if (!registry.isRegisteredVault(params.vault)) {
            revert DepositToNonVaultContract();
        }

        IVault vault = IVault(params.vault);
        bool ok = IERC20(vault.baseToken()).transferFrom(msg.sender, address(this), params.amount);
        if (!ok) {
            revert TransferFailed();
        }
        ok = IERC20(vault.baseToken()).approve(params.vault, params.amount);
        if (!ok) {
            revert ApproveFailed();
        }
        vault.deposit(params.amount, params.recipient);

        emit Deposit(params.vault, params.recipient, msg.sender, params.amount);
    }
}
