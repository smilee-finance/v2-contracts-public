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

    struct EpochInfo {
        uint256 epochTimestamp;
        uint256 epochStrike;
    }

    mapping(uint256 => DepositInfo) internal depositInfo;
    mapping(uint256 => BuyInfo) internal buyInfo;
    mapping(uint256 => EpochInfo) internal epochInfo;
    uint256 depositCounter = 0;
    uint256 buyCounter = 0;
    uint256 epochCounter = 0;

    function setup() internal virtual override {
        deploy();
    }

    //----------------------------------------------
    // IG
    //----------------------------------------------
    function buyBull(address recipient, uint256 amount) public {
        (, , , uint256 bullAvailNotional) = ig.notional();
        amount = _between(amount, 1000e18, bullAvailNotional);

        precondition(block.timestamp < ig.getEpoch().current);

        uint256 initialUserBalance = baseToken.balanceOf(recipient);
        uint256 currentStrike = ig.currentStrike();
        (uint256 expectedPremium /* uint256 _fee */, ) = ig.premium(currentStrike, amount, 0);
        uint256 maxPremium = expectedPremium + (0.03e18 * expectedPremium) / 1e18;
        TokenUtils.provideApprovedTokens(
            tokenAdmin,
            address(baseToken),
            recipient,
            address(ig),
            maxPremium,
            _convertVm()
        );
        initialUserBalance = baseToken.balanceOf(recipient);
        // uint256 minPremium = expectedPremium - (0.03e18 * expectedPremium) / 1e18;
        hevm.prank(recipient);
        uint256 premium = ig.mint(recipient, currentStrike, amount, 0, expectedPremium, 0.03e18);

        lte(premium, maxPremium, "GENERAL-01: Premium never exeed slippage max");
        // gte(premium, minPremium, "GENERAL-01: Premium never exeed slippage min");
        gte(
            baseToken.balanceOf(recipient),
            initialUserBalance - premium,
            "GENERAL-01: The option buyer never loses more than the premium"
        );

        uint256 currentEpoch = ig.getEpoch().current; // salvo strike per ogni epoca
        buyInfo[buyCounter] = BuyInfo(recipient, currentEpoch, epochCounter, amount, 0, currentStrike);
    }

    function sellBull(uint256 index) public {
        index = _between(index, 0, buyCounter);
        BuyInfo storage buyInfo_ = buyInfo[index];

        precondition(epochCounter > buyInfo_.epochCounter);
        precondition(buyInfo_.amountUp > 0 && buyInfo_.amountDown == 0);

        uint256 initialUserBalance = baseToken.balanceOf(buyInfo_.recipient);
        TestnetPriceOracle apPriceOracle = TestnetPriceOracle(ap.priceOracle());
        address sideToken = vault.sideToken();
        uint256 sellTokenPrice = apPriceOracle.getTokenPrice(sideToken);

        if (epochCounter == buyInfo_.epochCounter + 1) {
            sellTokenPrice = ig.currentStrike();
        }
        if (epochCounter > buyInfo_.epochCounter + 1) {
            EpochInfo storage epochInfo_ = epochInfo[buyInfo_.epochCounter + 1];
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

        // lte(payoff, maxPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(payoff, minPayoff, "IG BULL-01: Payoff never exeed slippage");
        gte(
            baseToken.balanceOf(buyInfo_.recipient),
            initialUserBalance + payoff,
            "IG BULL-01: The option seller never gains more than the payoff"
        );

        if (sellTokenPrice > buyInfo_.strike) {
            t(
                payoff > 0,
                "IG BULL-01: A IG bull payoff is always positive above the strike price & zero at or below the strike price"
            );
        } else {
            t(
                payoff == 0,
                "IG BULL-01: A IG bull payoff is always positive above the strike price & zero at or below the strike price"
            );
        }
        buyInfo_.amountUp = 0;
    }

    //----------------------------------------------
    // UTILS
    //----------------------------------------------

    function rollEpoch() public {
        uint256 currentEpoch = ig.getEpoch().current;
        uint256 currentStrike = ig.currentStrike();
        epochInfo[epochCounter] = EpochInfo(currentEpoch, currentStrike);
        hevm.prank(tokenAdmin);
        ig.rollEpoch();
        epochCounter++;
    }

    function setTokenPrice(uint256 price) public {
        TestnetPriceOracle apPriceOracle = TestnetPriceOracle(ap.priceOracle());
        address sideToken = vault.sideToken();

        price = _between(price, 0.01e18, 1000e18);
        apPriceOracle.setTokenPrice(sideToken, price);
    }
}
