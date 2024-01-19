// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

abstract contract PropertiesDescriptions {
    struct InvariantInfo {
        string code;
        string desc;
    }

    // INVARIANTS
    InvariantInfo internal _IG_09 =   InvariantInfo("_IG_09",   "_IG_09: The option seller never gains more than the payoff");
    InvariantInfo internal _IG_10 =   InvariantInfo("_IG_10",   "_IG_10: The option buyer never loses more than the premium");
    InvariantInfo internal _IG_11 =   InvariantInfo("_IG_11",   "_IG_11: Payoff never exeed slippage");
    InvariantInfo internal _IG_12 =   InvariantInfo("_IG_12",   "_IG_12: A IG bull payoff is always positive above the strike price & zero at or below the strike price");
    InvariantInfo internal _IG_13 =   InvariantInfo("_IG_13",   "_IG_13: A IG bear payoff is always positive under the strike price & zero at or above the strike price");

    InvariantInfo internal _GENERAL_1                     =   InvariantInfo("GENERAL_1",                    "GENERAL_1: This should never revert");
    InvariantInfo internal _GENERAL_5_BEFORE_TIMESTAMP    =   InvariantInfo("GENERAL_5_BEFORE_TIMESTAMP",   "GENERAL_5_BEFORE_TIMESTAMP: After timestamp roll-epoch should not revert");
    InvariantInfo internal _GENERAL_5_AFTER_TIMESTAMP     =   InvariantInfo("GENERAL_5_AFTER_TIMESTAMP",    "GENERAL_5_AFTER_TIMESTAMP: Can't revert before timestamp");
    InvariantInfo internal _GENERAL_6                     =   InvariantInfo("GENERAL_6",                    "GENERAL_6: Buy and sell should not revert");

    InvariantInfo internal _VAULT_3   =   InvariantInfo("VAULT_3",      "VAULT_3: Vault balances = (or >=) PendingWithdraw + PendingPayoff + PendingDeposit + (vault share * sharePrice)");
    InvariantInfo internal _VAULT_10  =   InvariantInfo("VAULT_10",     "VAULT_10: Payoff Transfer (which happens everytime an IG position is sold or burnt) <= base token in vualt");
    InvariantInfo internal _VAULT_11  =   InvariantInfo("VAULT_11",     "VAULT_11: Vaults never exeecds tokens available when swap to hedge delta");
    InvariantInfo internal _VAULT_13  =   InvariantInfo("VAULT_13",     "VAULT_13: OutstandingShares does not change during the epoch (liquidity is added to vault only at roll-epoch)");
    InvariantInfo internal _VAULT_16  =   InvariantInfo("VAULT_16",     "VAULT_16: SharePrice never goes to 0");
    InvariantInfo internal _VAULT_17  =   InvariantInfo("VAULT_17",     "VAULT_17: PendingWithdraw & PendingPayoff does not change during epoch");
    InvariantInfo internal _VAULT_18  =   InvariantInfo("VAULT_18",     "VAULT_18: NewPendingWithdraw & NewPendingPayoff are zero during epoch");
}
