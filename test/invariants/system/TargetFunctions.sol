// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {Setup} from "./Setup.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";
import {console} from "forge-std/console.sol";

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
        uint256 epochCounter;
    }

    struct EpochInfo {
        uint256 epochTimestamp;
        uint256 epochStrike;
    }

    BuyInfo[] internal bullTrades;
    BuyInfo[] internal bearTrades;
    BuyInfo[] internal smileeTrades;
    WithdrawInfo[] internal withdrawals;
    DepositInfo[] internal _depositInfo;

    EpochInfo[] internal epochs;

    mapping(uint256 => DepositInfo) internal depositInfo;
    mapping(address => bool) internal _pendingWithdraw;
    uint256 depositCounter = 0;

    function setup() internal virtual override {
        deploy();
        _initializeProperties();
    }

    //----------------------------------------------
    // VAULT
    //----------------------------------------------
    function deposit(uint256 amount) public {
        // precondition revert ExceedsMaxDeposit
        (, , , , uint256 totalDeposit, , , , ) = vault.vaultState();
        uint256 maxDeposit = vault.maxDeposit();
        uint256 depositCapacity = maxDeposit - totalDeposit;
        amount = _between(amount, MIN_VAULT_DEPOSIT, depositCapacity);
        console.log("** DEPOSIT", amount);
        VaultUtils.debugState(vault);

        precondition(block.timestamp < ig.getEpoch().current);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(vault), amount, _convertVm());
        gte(baseToken.balanceOf(msg.sender), amount, "ERROR: Minting baseToken");

        uint256 vaultInitialBalance = baseToken.balanceOf(address(vault));
        hevm.prank(msg.sender);
        try vault.deposit(amount, msg.sender, 0) {} catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_1);
        }

        gt(baseToken.balanceOf(address(vault)), vaultInitialBalance, "ERROR: Deposit fail");

        _depositInfo.push(DepositInfo(msg.sender, amount));
        VaultUtils.debugState(vault);
    }

    function redeem(uint256 index) public {
        index = _between(index, 0, depositCounter);

        DepositInfo storage depInfo = depositInfo[index];
        (uint256 heldByUser, uint256 heldByVault) = vault.shareBalances(depInfo.user);
        precondition(heldByVault > 0); // can't redeem shares before epoch roll

        hevm.prank(depInfo.user);
        try vault.redeem(heldByVault) {} catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_1);
        }

        eq(vault.balanceOf(depInfo.user), heldByUser + heldByVault, "");
    }

    function initiateWithdraw(uint256 index) public {
        precondition(_depositInfo.length > 0);
        index = _between(index, 0, _depositInfo.length - 1);
        precondition(block.timestamp < ig.getEpoch().current); // EpochFinished()

        DepositInfo storage depInfo = _depositInfo[index];

        precondition(!_pendingWithdraw[depInfo.user]); // ExistingIncompleteWithdraw()
        (uint256 heldByUser, uint256 heldByVault) = vault.shareBalances(depInfo.user);
        uint256 sharesToWithdraw = heldByUser + heldByVault;
        precondition(sharesToWithdraw > 0); // AmountZero()

        console.log("** WITHDRAW", sharesToWithdraw);
        VaultUtils.debugState(vault);

        hevm.prank(depInfo.user);
        try vault.initiateWithdraw(sharesToWithdraw) {} catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_1);
        }

        _pendingWithdraw[depInfo.user] = true;
        withdrawals.push(WithdrawInfo(depInfo.user, sharesToWithdraw, epochs.length));
        _popDepositInfo(index);
        VaultUtils.debugState(vault);
    }

    function completeWithdraw(uint256 index) public {
        precondition(withdrawals.length > 0);
        index = _between(index, 0, withdrawals.length - 1);

        WithdrawInfo storage withdrawInfo = withdrawals[index];
        precondition(withdrawInfo.epochCounter < epochs.length); // WithdrawTooEarly()

        // uint256 initialVaultBalance = baseToken.balanceOf(address(vault));
        uint256 initialUserBalance = baseToken.balanceOf(withdrawInfo.user);
        (uint256 withdrawEpoch, ) = vault.withdrawals(withdrawInfo.user);
        uint256 epochSharePrice = vault.epochPricePerShare(withdrawEpoch);
        uint256 expectedAmountToWithdraw = (withdrawInfo.amount * epochSharePrice) / 1e18;

        hevm.prank(withdrawInfo.user);
        try vault.completeWithdraw() {} catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_1);
        }

        eq(baseToken.balanceOf(withdrawInfo.user), initialUserBalance + expectedAmountToWithdraw, "");
        _pendingWithdraw[withdrawInfo.user] = false;
        _popWithdrawals(index);
    }

    //----------------------------------------------
    // USER OPs.
    //----------------------------------------------

    function buyBull(uint256 amount) public {
        VaultUtils.debugStateIG(ig);
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

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);

        (uint256 payoff, uint256 minPayoff, uint256 sellTokenPrice) = _sell(buyInfo_);

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, IG_09);
        gte(payoff, minPayoff, IG_11);

        if (epochs.length > buyInfo_.epochCounter) {
            if (sellTokenPrice > buyInfo_.strike) {
                t(payoff > 0, IG_12);
            } else {
                t(payoff == 0, IG_12);
            }
        } else {
            t(true, ""); // TODO: implement invariant
        }

        _popTrades(index, buyInfo_);
    }

    function sellBear(uint256 index) public {
        precondition(bearTrades.length > 0);
        index = _between(index, 0, bearTrades.length - 1);
        BuyInfo storage buyInfo_ = bearTrades[index];

        precondition(buyInfo_.amountUp == 0 && buyInfo_.amountDown > 0);

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);

        (uint256 payoff, uint256 minPayoff, uint256 sellTokenPrice) = _sell(buyInfo_);

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, IG_09);
        gte(payoff, minPayoff, IG_11);

        if (epochs.length > buyInfo_.epochCounter) {
            if (sellTokenPrice < buyInfo_.strike) {
                t(payoff > 0, IG_13);
            } else {
                t(payoff == 0, IG_13);
            }
        } else {
            t(true, ""); // TODO: implement invariant
        }

        _popTrades(index, buyInfo_);
    }

    function sellSmilee(uint256 index) public {
        precondition(smileeTrades.length > 0);
        index = _between(index, 0, smileeTrades.length - 1);
        BuyInfo storage buyInfo_ = smileeTrades[index];

        precondition(buyInfo_.amountUp != 0 && buyInfo_.amountDown != 0);

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);

        (uint256 payoff, uint256 minPayoff, uint256 sellTokenPrice) = _sell(buyInfo_);

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(baseToken.balanceOf(buyInfo_.recipient), initialUserBalance + payoff, IG_09);
        gte(payoff, minPayoff, IG_11);

        if (epochs.length > buyInfo_.epochCounter) {
            if (sellTokenPrice != buyInfo_.strike) {
                t(payoff > 0, IG_13);
            } else {
                t(payoff == 0, IG_13);
            }
        } else {
            t(true, ""); // TODO: implement invariant
        }

        _popTrades(index, buyInfo_);
    }

    //----------------------------------------------
    // ADMIN OPs.
    //----------------------------------------------

    function callAdminFunction(uint256 perc, uint256 input) public {
        perc = _between(perc, 0, 100);

        if (perc < 10) {
            console.log("SKIP");
            // DO NOTHING
            emit Debug("Do nothing");
            return;
        } else if (perc < 30) {
            // 20% - RollEpoch
            emit Debug("rollEpoch()");
            _rollEpoch();
        } else {
            // 70% - SetTokenPrice
            emit DebugUInt("setTokenPrice()", input);
            _setTokenPrice(input);
        }
    }

    function _rollEpoch() internal {
        console.log("** ROLLEPOCH");
        VaultUtils.debugState(vault);
        VaultUtils.debugStateIG(ig);
        uint256 currentEpoch = ig.getEpoch().current;
        uint256 currentStrike = ig.currentStrike();
        hevm.prank(admin);
        try ig.rollEpoch() {} catch (bytes memory err) {
            if (block.timestamp > currentEpoch) {
                // GENERAL 5
                _shouldNotRevertUnless(err, _GENERAL_5_AFTER_TIMESTAMP);
            }
            _shouldNotRevertUnless(err, _GENERAL_5_BEFORE_TIMESTAMP);
        }
        epochs.push(EpochInfo(currentEpoch, currentStrike));
        VaultUtils.debugState(vault);
        VaultUtils.debugStateIG(ig);
    }

    function _setTokenPrice(uint256 price) internal {
        if (TOKEN_PRICE_CAN_CHANGE) {
            TestnetPriceOracle apPriceOracle = TestnetPriceOracle(ap.priceOracle());
            address sideToken = vault.sideToken();

            price = _between(price, MIN_TOKEN_PRICE, MAX_TOKEN_PRICE);
            console.log("** SET TOKEN PRICE", price);
            hevm.prank(admin);
            apPriceOracle.setTokenPrice(sideToken, price);
        }
    }

    function _setFeePrice() internal {
        // FEE_PARAMS.timeToExpiryThreshold = 9999;
        FeeManager feeManager = FeeManager(ap.feeManager());
        feeManager.setDVPFee(address(ig), FEE_PARAMS);
    }

    //----------------------------------------------
    // COMMON
    //----------------------------------------------

    function _buy(uint256 amountUp, uint256 amountDown) internal {
        uint256 currentStrike = ig.currentStrike();
        (uint256 expectedPremium, uint256 fee) = ig.premium(currentStrike, amountUp, amountDown);
        uint256 maxPremium = expectedPremium + (SLIPPAGE * expectedPremium) / 1e18;

        TokenUtils.provideApprovedTokens(admin, address(baseToken), msg.sender, address(ig), maxPremium, _convertVm());
        uint256 initialUserBalance = baseToken.balanceOf(msg.sender);

        uint256 premium;

        hevm.prank(msg.sender);
        try ig.mint(msg.sender, currentStrike, amountUp, amountDown, expectedPremium, SLIPPAGE, 0) returns (
            uint256 _premium
        ) {
            premium = _premium;
        } catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_6);
        }

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
        uint256 payoff;

        hevm.prank(buyInfo_.recipient);
        try
            ig.burn(
                buyInfo_.epoch,
                buyInfo_.recipient,
                buyInfo_.strike,
                buyInfo_.amountUp,
                buyInfo_.amountDown,
                expectedPayoff,
                SLIPPAGE
            )
        returns (uint256 _payoff) {
            payoff = _payoff;
        } catch (bytes memory err) {
            _shouldNotRevertUnless(err, _GENERAL_6);
        }

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
        } else {
            smileeTrades[index] = smileeTrades[smileeTrades.length - 1];
            smileeTrades.pop();
        }
    }

    /// Removes element at the given index from deposit info
    function _popDepositInfo(uint256 index) internal {
        _depositInfo[index] = _depositInfo[_depositInfo.length - 1];
        _depositInfo.pop();
    }

    /// Removes element at the given index from withdrawals
    function _popWithdrawals(uint256 index) internal {
        withdrawals[index] = withdrawals[withdrawals.length - 1];
        withdrawals.pop();
    }

    //----------------------------------------------
    // INVARIANTS ASSERTIONS
    //----------------------------------------------

    function _shouldNotRevertUnless(bytes memory err, string memory _invariant) internal {
        if (!_ACCEPTED_REVERTS[_invariant][keccak256(err)]) {
            emit DebugBool(_invariant, _ACCEPTED_REVERTS[_invariant][keccak256(err)]);
            t(false, _invariant);
        }
        revert(string(err));
    }
}
