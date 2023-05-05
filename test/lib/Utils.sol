// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

library Utils {
    /**
        @notice Test fucntion to give a certain amount of base tokens to a Vault
        @param vault_ The address of the Vault
        @param amount The amount of asset to be moved to the Vault
     */
    function vaultPayoff(address vault_, int256 amount) external {
        IVault vault = IVault(vault_);
        TestnetToken asset = TestnetToken(vault.baseToken());
        if (amount > 0) {
            asset.mint(address(this), uint256(amount));
            asset.approve(vault_, uint256(amount));
        }
        vault.moveAsset(amount);

        if (amount < 0) {
            asset.burn(address(this), uint256(-amount));
        }
    }
}
