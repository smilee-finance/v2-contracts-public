// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties {
    struct BuyInfo {
        address recipient;
        uint256 epoch;
        uint256 epochCounter;
        uint256 amountUp;
        uint256 amountDown;
        uint256 strike;
    }

    struct EpochInfo {
        uint256 epochTimestamp;
        uint256 epochStrike;
    }

    BuyInfo[] internal bullTrades;
    BuyInfo[] internal bearTrades;

    EpochInfo[] internal epochs;

    function setup() internal virtual override {
        deploy();
    }

    //----------------------------------------------
    // USER OPs.
    //----------------------------------------------

    function buyBull(uint256 amount) public {
        (, , , uint256 bullAvailNotional) = ig.notional();
        amount = _between(amount, 1000e18, bullAvailNotional);
        precondition(block.timestamp < ig.getEpoch().current);
        _buy(amount, 0);
    }

    function buyBear(uint256 amount) public {
        (, , uint256 bearAvailNotional, ) = ig.notional();
        amount = _between(amount, 1000e18, bearAvailNotional);
        precondition(block.timestamp < ig.getEpoch().current);

        _buy(0, amount);
    }

    function sellBull(uint256 index) public {
        index = _between(index, 0, bullTrades.length - 1);
        BuyInfo storage buyInfo_ = bullTrades[index];

        precondition(epochs.length > buyInfo_.epochCounter);
        precondition(buyInfo_.amountUp > 0 && buyInfo_.amountDown == 0);

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);

        (uint256 payoff, uint256 minPayoff, uint256 sellTokenPrice) = _sell(buyInfo_);
        _popTrades(index, buyInfo_);

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, IG_09);
        gte(payoff, minPayoff, IG_11);

        if (sellTokenPrice > buyInfo_.strike) {
            t(payoff > 0, IG_12);
        } else {
            t(payoff == 0, IG_12);
        }
    }

    function sellBear(uint256 index) public {
        index = _between(index, 0, bearTrades.length - 1);
        BuyInfo storage buyInfo_ = bearTrades[index];

        precondition(epochs.length > buyInfo_.epochCounter);
        precondition(buyInfo_.amountUp == 0 && buyInfo_.amountDown > 0);

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);

        (uint256 payoff, uint256 minPayoff, uint256 sellTokenPrice) = _sell(buyInfo_);
        _popTrades(index, buyInfo_);

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, IG_09);
        gte(payoff, minPayoff, IG_11);

        if (sellTokenPrice < buyInfo_.strike) {
            t(payoff > 0, IG_13);
        } else {
            t(payoff == 0, IG_13);
        }
    }

    //----------------------------------------------
    // ADMIN OPs.
    //----------------------------------------------

    function rollEpoch() public {
        uint256 currentEpoch = ig.getEpoch().current;
        uint256 currentStrike = ig.currentStrike();
        hevm.prank(admin);
        ig.rollEpoch();
        epochs.push(EpochInfo(currentEpoch, currentStrike));
    }

    function setTokenPrice(uint256 price) public {
        TestnetPriceOracle apPriceOracle = TestnetPriceOracle(ap.priceOracle());
        address sideToken = vault.sideToken();

        price = _between(price, 0.01e18, 1000e18);
        hevm.prank(admin);
        apPriceOracle.setTokenPrice(sideToken, price);
    }

    //----------------------------------------------
    // COMMON
    //----------------------------------------------

    function _buy(uint256 amountUp, uint256 amountDown) internal {
        uint256 currentStrike = ig.currentStrike();
        (uint256 expectedPremium /* uint256 _fee */, ) = ig.premium(currentStrike, amountUp, amountDown);
        uint256 maxPremium = expectedPremium + (0.03e18 * expectedPremium) / 1e18;

        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(ig), maxPremium, _convertVm());
        uint256 initialUserBalance = baseToken.balanceOf(msg.sender);
        uint256 premium = ig.mint(msg.sender, currentStrike, amountUp, amountDown, expectedPremium, 0.03e18);

        gte(baseToken.balanceOf(msg.sender), initialUserBalance - premium, IG_10);
        lte(premium, maxPremium, IG_11);

        if (amountUp > 0 && amountDown == 0) {
            bullTrades.push(
                BuyInfo(msg.sender, ig.getEpoch().current, epochs.length, amountUp, amountDown, currentStrike)
            );
        } else if (amountUp == 0 && amountDown > 0) {
            bearTrades.push(
                BuyInfo(msg.sender, ig.getEpoch().current, epochs.length, amountUp, amountDown, currentStrike)
            );
        }
    }

    function _sell(BuyInfo memory buyInfo_) internal returns (uint256, uint256, uint256) {
        TestnetPriceOracle apPriceOracle = TestnetPriceOracle(ap.priceOracle());
        address sideToken = vault.sideToken();
        uint256 sellTokenPrice = apPriceOracle.getTokenPrice(sideToken);

        // if one epoch have passed, get end price from current epoch
        if (epochs.length == buyInfo_.epochCounter + 1) {
            sellTokenPrice = ig.currentStrike();
        }

        // if more epochs have passed, get end price from trade subsequent epoch
        if (epochs.length > buyInfo_.epochCounter + 1) {
            EpochInfo storage epochInfo_ = epochs[buyInfo_.epochCounter + 1];
            sellTokenPrice = epochInfo_.epochStrike;
        }

        hevm.prank(buyInfo_.recipient);
        (uint256 expectedPayoff /* uint256 _fee */, ) = ig.payoff(
            buyInfo_.epoch,
            buyInfo_.strike,
            buyInfo_.amountUp,
            buyInfo_.amountDown
        );

        // uint256 maxPayoff = expectedPayoff + (0.03e18 * expectedPayoff) / 1e18;
        uint256 minPayoff = expectedPayoff - (0.03e18 * expectedPayoff) / 1e18;
        hevm.prank(buyInfo_.recipient);
        uint256 payoff = ig.burn(
            buyInfo_.epoch,
            buyInfo_.recipient,
            buyInfo_.strike,
            buyInfo_.amountUp,
            buyInfo_.amountDown,
            expectedPayoff,
            0.03e18
        );

        return (payoff, minPayoff, sellTokenPrice);
    }

    /// Removes element at the given index from trades
    function _popTrades(uint256 index, BuyInfo memory trade) internal {
        if (trade.amountUp > 0 && trade.amountDown == 0) {
            bullTrades[index] = bullTrades[bullTrades.length - 1];
            bullTrades.pop();
        } else if (trade.amountUp == 0 && trade.amountDown > 0) {
            bearTrades[index] = bearTrades[bearTrades.length - 1];
            bearTrades.pop();
        }
    }
}
