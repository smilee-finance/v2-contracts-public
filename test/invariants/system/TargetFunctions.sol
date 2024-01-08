// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";

/**
 * medusa fuzz --no-color
 * echidna . --contract CryticTester --config config.yaml
 */
abstract contract TargetFunctions is BaseTargetFunctions, Properties {
    function setup() internal virtual override {
      deploy();
    }

    function deposit(address user, uint256 amount) public {
      MockedVault igVault = MockedVault(ig.vault());
      TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), user, address(igVault), amount, _convertVm());

      hevm.prank(user);
      igVault.deposit(amount, user, 0);

      gt(baseToken.balanceOf(address(igVault)), 0, "");
    }

}
