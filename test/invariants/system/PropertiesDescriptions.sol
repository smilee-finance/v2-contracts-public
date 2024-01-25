// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

abstract contract PropertiesDescriptions {
    struct InvariantInfo {
        string code;
        string desc;
    }

    // INVARIANTS
    InvariantInfo internal _IG_04 =   InvariantInfo("_IG_04",   "_IG_04: User cannot buy IG, sell it for a profit if neither: utilisation grows or price moves up for bull, down for bear, or both for smile");
    InvariantInfo internal _IG_05_1 =   InvariantInfo("_IG_05_1",   "_IG_05_1: A IG bull premium is always <= than that of a call with the same strike and notional");
    InvariantInfo internal _IG_05_2 =   InvariantInfo("_IG_05_2",   "_IG_05_2: A IG bull premium is always >= than that of a call with the strike in kb and same notional");
    InvariantInfo internal _IG_07_1 =   InvariantInfo("_IG_07_1",   "_IG_07_1: A IG bear premium is always <= than that of a put with the same strike and notional");
    InvariantInfo internal _IG_07_2 =   InvariantInfo("_IG_07_2",   "_IG_07_2: A IG bear premium is always >= than that of a put with the strike in kb and same notional");
    InvariantInfo internal _IG_08_1 =   InvariantInfo("_IG_08_1",   "_IG_08_1: A IG Smile premium is always <= than that of a straddle with the same strike and notional");
    InvariantInfo internal _IG_08_2 =   InvariantInfo("_IG_08_2",   "_IG_08_2: A IG Smile premium is always >= than that of a strangle with the strike in ka and kb and notional");
    InvariantInfo internal _IG_09 =   InvariantInfo("_IG_09",   "_IG_09: The option seller never gains more than the payoff");
    InvariantInfo internal _IG_10 =   InvariantInfo("_IG_10",   "_IG_10: The option buyer never loses more than the premium");
    InvariantInfo internal _IG_11 =   InvariantInfo("_IG_11",   "_IG_11: Payoff never exeed slippage");
    InvariantInfo internal _IG_12 =   InvariantInfo("_IG_12",   "_IG_12: A IG bull payoff is always positive above the strike price & zero at or below the strike price");
    InvariantInfo internal _IG_13 =   InvariantInfo("_IG_13",   "_IG_13: A IG bear payoff is always positive under the strike price & zero at or above the strike price");
    InvariantInfo internal _IG_15 =   InvariantInfo("_IG_15",   "_IG_15: Notional (aka V0) does not change during epoch");
    InvariantInfo internal _IG_16 =   InvariantInfo("_IG_16",   "_IG_16: Strike does not change during epoch");
    InvariantInfo internal _IG_17 =   InvariantInfo("_IG_17",   "_IG_17: IG finance params does not change during epoch");
    InvariantInfo internal _IG_18 =   InvariantInfo("_IG_18",   "_IG_18: IG minted never > than Notional (aka V0)");
    InvariantInfo internal _IG_20 =   InvariantInfo("_IG_20",   "_IG_20: IG price always >= 0 + MIN fee");
    InvariantInfo internal _IG_21 =   InvariantInfo("_IG_21",   "_IG_21: Fee always >= MIN fee");
    InvariantInfo internal _IG_22 =   InvariantInfo("_IG_22",   "_IG_22: IG bull delta is always positive -> control that limsup > 0 after every rollEpoch");
    InvariantInfo internal _IG_23 =   InvariantInfo("_IG_23",   "_IG_23: IG bear delta is always negative -> control that liminf < 0 after every rollEpoch");
    InvariantInfo internal _IG_27 =   InvariantInfo("_IG_27",   "_IG_27: IG smilee payoff is always positive if the strike price change & zero the strike price doesn't change");

    InvariantInfo internal _GENERAL_1   =   InvariantInfo("GENERAL_1",  "GENERAL_1: This should never revert");
    InvariantInfo internal _GENERAL_4   =   InvariantInfo("GENERAL_4",  "GENERAL_4: After timestamp roll-epoch should not revert");
    InvariantInfo internal _GENERAL_5   =   InvariantInfo("GENERAL_5",  "GENERAL_5: Can't revert before timestamp");
    InvariantInfo internal _GENERAL_6   =   InvariantInfo("GENERAL_6",  "GENERAL_6: Buy and sell should not revert");

    InvariantInfo internal _VAULT_3   =   InvariantInfo("VAULT_3",      "VAULT_3: Vault balances = (or >=) PendingWithdraw + PendingPayoff + PendingDeposit + (vault share * sharePrice)");
    InvariantInfo internal _VAULT_10  =   InvariantInfo("VAULT_10",     "VAULT_10: Payoff Transfer (which happens everytime an IG position is sold or burnt) <= base token in vualt");
    InvariantInfo internal _VAULT_11  =   InvariantInfo("VAULT_11",     "VAULT_11: Vaults never exeecds tokens available when swap to hedge delta");
    InvariantInfo internal _VAULT_13  =   InvariantInfo("VAULT_13",     "VAULT_13: OutstandingShares does not change during the epoch (liquidity is added to vault only at roll-epoch)");
    InvariantInfo internal _VAULT_16  =   InvariantInfo("VAULT_16",     "VAULT_16: SharePrice never goes to 0");
    InvariantInfo internal _VAULT_17  =   InvariantInfo("VAULT_17",     "VAULT_17: PendingWithdraw & PendingPayoff does not change during epoch");
    InvariantInfo internal _VAULT_18  =   InvariantInfo("VAULT_18",     "VAULT_18: NewPendingWithdraw & NewPendingPayoff are zero during epoch");
    InvariantInfo internal _VAULT_19  =   InvariantInfo("VAULT_19",     "VAULT_19: Withdrawal Share are converted at SharePrice (aka the fair price). Withdraw = withdrawal Share * Share Price");
    InvariantInfo internal _VAULT_23  =   InvariantInfo("VAULT_23",     "VAULT_23: OutstandingShare_epoch_t = OutstandingShare_epoch_t-1 + NewShare_at_roll_epoch - WithdrawalShare_at_roll_epoch");
}
