// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";

library TokenUtils {
    /// @dev Create TestnetToken couple contracts
    function initTokens(
        address tokenAdmin,
        address controller,
        address swapper,
        Vm vm
    ) internal returns (address baseToken, address sideToken) {
        vm.startPrank(tokenAdmin);

        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        baseToken = address(token);

        token = new TestnetToken("Testnet WETH", "stWETH");
        token.setController(controller);
        token.setSwapper(swapper);
        sideToken = address(token);

        vm.stopPrank();
    }

    /// @dev Provide a certain amount of a given tokens to a given wallet, and approve exchange to a given address
    function provideApprovedTokens(
        address tokenAdmin,
        address token,
        address wallet,
        address approved,
        uint256 amount,
        Vm vm
    ) internal {
        vm.prank(tokenAdmin);
        TestnetToken(token).mint(wallet, amount);
        vm.prank(wallet);
        TestnetToken(token).approve(approved, amount);
    }

    /**
     * Function used to skip coverage on this file
     */
    function testCoverageSkip() private view {}
}
