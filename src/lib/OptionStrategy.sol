// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

library OptionStrategy {
    uint256 private constant VALIDITY_MASK = 2 ** 8 - 1 - 3; // 11111100 - only 2 bits
    uint256 private constant VANILLA_BIT = 0; // ...0001 - for VANILLA
    uint256 private constant CALL_BIT = 1; // ...0010 - for CALL

    /// @notice Returns if the strategy type is a valid one
    /// @param self The uint reprensenting the strategy
    /// @return True if the option type is supported
    function isValid(uint256 self) internal pure returns (bool) {
        return self & VALIDITY_MASK == 0;
    }

    /// @notice Returns if the strategy type is vanilla option or impermanent gain option
    /// @param self The uint reprensenting the strategy
    /// @return True if the option type is VANILLA
    function isVanilla(uint256 self) internal pure returns (bool) {
        return self & (1 << VANILLA_BIT) > 0;
    }

    /// @notice Returns if the strategy is PUT / CALL
    /// @param self The uint reprensenting the strategy
    /// @return True if the option direction is CALL
    function isCall(uint256 self) internal pure returns (bool) {
        return self & (1 << CALL_BIT) > 0;
    }

    function vanillaCall() internal pure returns (uint256) {
        return (1 << VANILLA_BIT) | (1 << CALL_BIT);
    }

    function vanillaPut() internal pure returns (uint256) {
        return (1 << VANILLA_BIT);
    }

    // Impermanent Gain UP
    function igCall() internal pure returns (uint256) {
        return (1 << CALL_BIT);
    }

    // Impermanent Gain DOWN
    function igPut() internal pure returns (uint256) {
        return 0;
    }
}
