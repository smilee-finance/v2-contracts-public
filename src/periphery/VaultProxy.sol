// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {IVaultParams} from "../interfaces/IVaultParams.sol";
import {IVaultProxy} from "../interfaces/IVaultProxy.sol";
import {IVaultUser} from "../interfaces/IVaultUser.sol";

contract VaultProxy is IVaultProxy {
    using SafeERC20 for IERC20;

    address private _addressProvider;

    error DepositToNonVaultContract();

    constructor(address provider) {
        _addressProvider = provider;
    }

    /// @inheritdoc IVaultProxy
    function deposit(DepositParams calldata params) external {
        IRegistry registry = IRegistry(IAddressProvider(_addressProvider).registry());
        if (!registry.isRegisteredVault(params.vault)) {
            revert DepositToNonVaultContract();
        }

        IERC20 baseToken = IERC20(IVaultParams(params.vault).baseToken());
        baseToken.safeTransferFrom(msg.sender, address(this), params.amount);
        baseToken.safeApprove(params.vault, params.amount);

        IVaultUser vault = IVaultUser(params.vault);
        vault.deposit(params.amount, params.recipient, params.accessTokenId);

        emit Deposit(params.vault, params.recipient, msg.sender, params.amount);
    }
}
