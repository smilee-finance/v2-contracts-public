// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";

abstract contract Properties is Setup {
  // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);

    string internal constant IG_09 = "IG_09: The option seller never gains more than the payoff";
    string internal constant IG_10 = "IG_10: The option buyer never loses more than the premium";
    string internal constant IG_11 = "IG_11: Payoff never exeed slippage";
    string internal constant IG_12 = "IG_12: A IG bull payoff is always positive above the strike price & zero at or below the strike price";
    string internal constant IG_13 = "IG_13: A IG bear payoff is always positive under the strike price & zero at or above the strike price";
}
