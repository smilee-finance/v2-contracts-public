// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";

/**
 * medusa fuzz --no-color
 * echidna . --contract CryticTester --config config.yaml
 */
abstract contract TargetFunctions is BaseTargetFunctions, Properties {
    struct DepositInfo {
        address user;
        uint256 amount;
    }

    struct BuyInfo {
        address recipient;
        uint256 epoch;
        uint256 epochCounter;
        uint256 amountUp;
        uint256 amountDown;
        uint256 strike;
    }

    struct WithdrawInfo {
        address user;
        uint256 amount;
    }

    struct EpochInfo {
        uint256 epochTimestamp;
        uint256 epochStrike;
    }

    BuyInfo[] internal bullTrades;
    BuyInfo[] internal bearTrades;
    BuyInfo[] internal smileeTrades;
    WithdrawInfo[] internal withdrawals;

    EpochInfo[] internal epochs;

    mapping(uint256 => DepositInfo) internal depositInfo;
    uint256 depositCounter = 0;

    function setup() internal virtual override {
        deploy();
    }

    //----------------------------------------------
    // VAULT
    //----------------------------------------------
    function deposit(uint256 amount) public {
        amount = _between(amount, MIN_VAULT_DEPOSIT, MAX_VAULT_DEPOSIT);
        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(vault), amount, _convertVm());
        gte(baseToken.balanceOf(msg.sender), amount, "");

        hevm.prank(msg.sender);
        vault.deposit(amount, msg.sender, 0);

        gt(baseToken.balanceOf(address(vault)), 0, "");

        depositInfo[depositCounter] = DepositInfo(msg.sender, amount);
        depositCounter++;
    }

    function redeem(uint256 index) public {
        index = _between(index, 0, depositCounter);
        DepositInfo storage depInfo = depositInfo[index];

        (uint256 heldByUser, uint256 heldByVault) = vault.shareBalances(depInfo.user);
        precondition(depInfo.amount > 0);
        precondition(heldByVault > 0); // can't redeem befor epoch roll

        hevm.prank(depInfo.user);
        vault.redeem(heldByVault);

        eq(vault.balanceOf(depInfo.user), heldByUser + heldByVault, "");
        depInfo.amount = 0;
    }

    function initiateWithdraw(uint256 index) public {
        index = _between(index, 0, depositCounter);

        DepositInfo storage depInfo = depositInfo[index];
        (uint256 heldByUser, uint256 heldByVault) = vault.shareBalances(depInfo.user);
        precondition(depInfo.amount > 0);
        precondition((heldByVault >= depInfo.amount || heldByUser >= depInfo.amount));

        hevm.prank(depInfo.user);
        vault.initiateWithdraw(depInfo.amount);
        withdrawals.push(WithdrawInfo(depInfo.user, depInfo.amount));
    }

    function completeWithdraw(uint256 index) public {
        precondition(withdrawals.length > 0);
        index = _between(index, 0, withdrawals.length - 1);
        WithdrawInfo storage withdrawInfo = withdrawals[index];

        // uint256 initialVaultBalance = baseToken.balanceOf(address(vault));
        uint256 initialUserBalance = baseToken.balanceOf(withdrawInfo.user);
        (uint256 withdrawEpoch, ) = vault.withdrawals(withdrawInfo.user);
        uint256 epochSharePrice = vault.epochPricePerShare(withdrawEpoch);
        uint256 expectedAmountToWithdraw = (withdrawInfo.amount * epochSharePrice) / 1e18;

        hevm.prank(withdrawInfo.user);
        vault.completeWithdraw();

        eq(baseToken.balanceOf(withdrawInfo.user), initialUserBalance + expectedAmountToWithdraw, "");
        _popWithdrawals(index);
    }

    //----------------------------------------------
    // USER OPs.
    //----------------------------------------------

    function buyBull(uint256 amount) public {
        (, , , uint256 bullAvailNotional) = ig.notional();
        amount = _between(amount, MIN_OPTION_BUY, bullAvailNotional);
        precondition(block.timestamp < ig.getEpoch().current);
        _buy(amount, 0);
    }

    function buyBear(uint256 amount) public {
        (, , uint256 bearAvailNotional, ) = ig.notional();
        amount = _between(amount, MIN_OPTION_BUY, bearAvailNotional);
        precondition(block.timestamp < ig.getEpoch().current);
        _buy(0, amount);
    }

    function buySmilee(uint256 amount) public {
        (, , uint256 bearAvailNotional, uint256 bullAvailNotional) = ig.notional();
        uint256 minAvailNotional = bearAvailNotional;
        if (bullAvailNotional < minAvailNotional) {
            minAvailNotional = bullAvailNotional;
        }
        amount = _between(amount, MIN_OPTION_BUY, minAvailNotional);
        precondition(block.timestamp < ig.getEpoch().current);
        _buy(amount, amount);
    }

    function sellBull(uint256 index) public {
        precondition(bullTrades.length > 0);
        index = _between(index, 0, bullTrades.length - 1);
        BuyInfo storage buyInfo_ = bullTrades[index];

        precondition(epochs.length > buyInfo_.epochCounter);
        precondition(buyInfo_.amountUp > 0 && buyInfo_.amountDown == 0);

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);

        (uint256 payoff, uint256 minPayoff, uint256 sellTokenPrice) = _sell(buyInfo_);

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, IG_09);
        gte(payoff, minPayoff, IG_11);

        if (sellTokenPrice > buyInfo_.strike) {
            t(payoff > 0, IG_12);
        } else {
            t(payoff == 0, IG_12);
        }

        _popTrades(index, buyInfo_);
    }

    function sellBear(uint256 index) public {
        precondition(bearTrades.length > 0);
        index = _between(index, 0, bearTrades.length - 1);
        BuyInfo storage buyInfo_ = bearTrades[index];

        precondition(epochs.length > buyInfo_.epochCounter);
        precondition(buyInfo_.amountUp == 0 && buyInfo_.amountDown > 0);

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);

        (uint256 payoff, uint256 minPayoff, uint256 sellTokenPrice) = _sell(buyInfo_);

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, IG_09);
        gte(payoff, minPayoff, IG_11);
        if (sellTokenPrice < buyInfo_.strike) {
            t(payoff > 0, IG_13);
        } else {
            t(payoff == 0, IG_13);
        }

        _popTrades(index, buyInfo_);
    }

    function sellSmilee(uint256 index) public {
        precondition(smileeTrades.length > 0);
        index = _between(index, 0, smileeTrades.length - 1);
        BuyInfo storage buyInfo_ = smileeTrades[index];

        precondition(epochs.length > buyInfo_.epochCounter);
        precondition(buyInfo_.amountUp != 0 && buyInfo_.amountDown != 0);

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);

        (uint256 payoff, uint256 minPayoff, uint256 sellTokenPrice) = _sell(buyInfo_);

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, IG_09);
        gte(payoff, minPayoff, IG_11);
        if (sellTokenPrice != buyInfo_.strike) {
            t(payoff > 0, IG_13);
        } else {
            t(payoff == 0, IG_13);
        }

        _popTrades(index, buyInfo_);
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
        if (TOKEN_PRICE_CAN_CHANGE) {
            TestnetPriceOracle apPriceOracle = TestnetPriceOracle(ap.priceOracle());
            address sideToken = vault.sideToken();

            price = _between(price, MIN_TOKEN_PRICE, MAX_TOKEN_PRICE);
            hevm.prank(admin);
            apPriceOracle.setTokenPrice(sideToken, price);
        }
    }

    //----------------------------------------------
    // COMMON
    //----------------------------------------------

    function _buy(uint256 amountUp, uint256 amountDown) internal {
        uint256 currentStrike = ig.currentStrike();
        (uint256 expectedPremium /* uint256 _fee */, ) = ig.premium(currentStrike, amountUp, amountDown);
        uint256 maxPremium = expectedPremium + (SLIPPAGE * expectedPremium) / 1e18;

        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(ig), maxPremium, _convertVm());
        uint256 initialUserBalance = baseToken.balanceOf(msg.sender);
        hevm.prank(msg.sender);
        uint256 premium = ig.mint(msg.sender, currentStrike, amountUp, amountDown, expectedPremium, SLIPPAGE);

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
        } else {
            smileeTrades.push(
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

        // uint256 maxPayoff = expectedPayoff + (SLIPPAGE * expectedPayoff) / 1e18;
        uint256 minPayoff = expectedPayoff - (SLIPPAGE * expectedPayoff) / 1e18;
        hevm.prank(buyInfo_.recipient);
        uint256 payoff = ig.burn(
            buyInfo_.epoch,
            buyInfo_.recipient,
            buyInfo_.strike,
            buyInfo_.amountUp,
            buyInfo_.amountDown,
            expectedPayoff,
            SLIPPAGE
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

    /// Removes element at the given index from withdrawals
    function _popWithdrawals(uint256 index) internal {
        withdrawals[index] = withdrawals[withdrawals.length - 1];
        withdrawals.pop();
    }
}
