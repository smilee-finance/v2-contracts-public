// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IVault} from "./interfaces/IVault.sol";
import {DVPType} from "./lib/DVPType.sol";
import {Notional} from "./lib/Notional.sol";
import {OptionStrategy} from "./lib/OptionStrategy.sol";
import {Position} from "./lib/Position.sol";
import {DVP} from "./DVP.sol";

contract IG is DVP {
    using Notional for Notional.Info;

    /// @notice Common strike price for all impermanent gain positions in this DVP, set at epoch start
    uint256 public currentStrike;

    constructor(address vault_) DVP(vault_, DVPType.IG) {}

    /// @inheritdoc IDVP
    function mint(
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) external override returns (uint256 leverage) {
        strike;
        leverage = _mint(recipient, currentStrike, strategy, amount);
    }

    /// @inheritdoc IDVP
    function burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        bool strategy,
        uint256 amount
    ) external override returns (uint256 paidPayoff) {
        paidPayoff = _burn(epoch, recipient, strike, strategy, amount);
    }

    /// @inheritdoc IDVP
    function premium(uint256 strike, bool strategy, uint256 amount) public view virtual override returns (uint256) {
        strike;
        strategy;
        // ToDo: compute price and premium
        return amount / 10; // 10%
    }

    function payoffPerc() public view virtual override returns (uint256 callPerc, uint256 putPerc) {
        return (1e17, 1e17); // igPayoffPerc(currentStrike, oracle.getPrice(...))
    }

    function _initLiquidity() internal virtual override {
        _liquidity[currentEpoch].setup(currentStrike, IVault(vault).v0());
    }

    function _residualPayoff() internal virtual override returns (uint256 residualPayoff) {
        (uint256 callPerc, uint256 putPerc) = payoffPerc();

        uint256 pCall = (callPerc * _liquidity[currentEpoch].getOptioned(currentStrike, OptionStrategy.CALL)) / 1e18;
        uint256 pPut = (putPerc * _liquidity[currentEpoch].getOptioned(currentStrike, OptionStrategy.PUT)) / 1e18;

        _liquidity[currentEpoch].accountPayoff(currentStrike, OptionStrategy.CALL, pCall);
        _liquidity[currentEpoch].accountPayoff(currentStrike, OptionStrategy.PUT, pPut);

        residualPayoff = pCall + pPut;
    }
}
