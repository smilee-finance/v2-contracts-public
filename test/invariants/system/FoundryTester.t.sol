// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract Handler is TargetFunctions, FoundryAsserts {
    constructor() {
        vm.deal(address(USER1), 100e18);
        vm.deal(address(USER2), 100e18);
        vm.deal(address(USER3), 100e18);

        setup();
    }

    function skipTime(uint256 input) public countCall("skipTime") {
        input = _between(input, 1, EPOCH_FREQUENCY * 2);
        hevm.warp(block.timestamp + input);
    }

    // modifier getSender() override {
    //     sender = uint160(msg.sender) % 3 == 0
    //         ? address(USER1)
    //         : uint160(msg.sender) % 3 == 1 ? address(USER2) : address(USER3);
    //     _;
    // }
}

contract FoundryTester is Test {
    Handler public handler;

    function setUp() public {
        handler = new Handler();
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 10000
    /// forge-config: default.invariant.depth = 300
    function invariant_callSummary() public view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("deposit", handler.calls("deposit"));
        console.log("redeem", handler.calls("redeem"));
        console.log("initiateWithdraw", handler.calls("initiateWithdraw"));
        console.log("completeWithdraw", handler.calls("completeWithdraw"));
        console.log("buyBull", handler.calls("buyBull"));
        console.log("buyBear", handler.calls("buyBear"));
        console.log("buySmilee", handler.calls("buySmilee"));
        console.log("sellBull", handler.calls("sellBull"));
        console.log("sellBear", handler.calls("sellBear"));
        console.log("sellSmilee", handler.calls("sellSmilee"));
        console.log("rollEpoch", handler.calls("rollEpoch"));
        console.log("setTokenPrice", handler.calls("setTokenPrice"));
        console.log("skipTime", handler.calls("skipTime"));
    }
}
