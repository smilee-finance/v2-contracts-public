// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {TokenUtils} from "./TokenUtils.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

library Utils {
    /// @dev Test function to give a certain amount of base tokens to a Vault
    function vaultPayoff(address tokenAdmin, address vault_, int256 amount, Vm vm) external {
        IVault vault = IVault(vault_);
        if (amount > 0) {
            TokenUtils.provideApprovedTokens(tokenAdmin, vault.baseToken(), tokenAdmin, vault_, uint256(amount), vm);
        }
        vault.moveAsset(amount);

        if (amount < 0) {
            TestnetToken(vault.baseToken()).burn(address(this), uint256(-amount));
        }
    }

    function skipDay(bool additionalSecond, Vm vm) external {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        vm.warp(block.timestamp + 1 days + secondToAdd);
    }

    /**
     * Function used to skip coverage on this file
     */
    function testCoverageSkip() private view {}
}
