// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "../../src/Vault.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

/**
    @notice a mocked vault to ease the testing of DVPs

    Such vault should allow the test to simulate the presence of enough liquidity for the DVP operations.
 */
contract MockedVault is Vault {
    bool internal _fakeLockedValue;
    uint256 internal _lockedValue;

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_,
        address addressProvider_
    ) Vault(baseToken_, sideToken_, epochFrequency_, addressProvider_) {}

    function setLockedValue(uint256 value) public {
        _lockedValue = value;
        _fakeLockedValue = true;
    }

    function useRealLockedValue() public {
        _fakeLockedValue = false;
    }

    function getLockedValue() view public override returns (uint256) {
        if (_fakeLockedValue) {
            return _lockedValue;
        }
        return super.getLockedValue();
    }

    // function moveTokens(int256 baseTokenAmount, int256 sideTokenAmount) public {
    //     _moveToken(baseToken, baseTokenAmount);
    //     _moveToken(sideToken, sideTokenAmount);
    // }

    function _moveToken(address token, int256 amount) internal {
        if (amount > 0) {
            IERC20(token).transferFrom(msg.sender, address(this), uint256(amount));
        } else {
            uint256 absAmount = uint256(-amount);
            if (token == baseToken && absAmount > _getLockedValue()) {
                revert ExceedsAvailable();
            }
            IERC20(token).transfer(msg.sender, absAmount);
        }
    }

    function moveValue(int256 percentage) public {
        // percentage
        // 10000 := 100%
        // 100 := 1%
        // revert if <= 100 %
        require(percentage >= -10000);

        uint256 sideTokens = IERC20(sideToken).balanceOf(address(this));
        _sellSideTokens(sideTokens);

        int256 baseDelta = int(_getLockedValue()) * percentage / 10000;
        _moveToken(baseToken, baseDelta);

        _splitIntoEqualWeightPortfolio();
    }

     /// @dev the current amount
    function getVaultLockedValue() public view returns (uint256) {
        return _getLockedValue();
    }
}
