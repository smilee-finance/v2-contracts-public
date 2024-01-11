// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";

abstract contract Properties is Setup {
    // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);

    string internal constant IG_01      = "IG_01: The option buyer never loses more than the premium";
    string internal constant IG_02      = "IG_02: The option seller never gains more than the payoff";
    string internal constant IG_03      = "IG_03: Payoff never exeed slippage";
    string internal constant IG_BULL_01 = "IG_BULL_01: A IG bull payoff is always positive above the strike price & zero at or below the strike price";
    string internal constant IG_BEAR_01 = "IG_BEAR_01: A IG bear payoff is always positive under the strike price & zero at or above the strike price";
}
