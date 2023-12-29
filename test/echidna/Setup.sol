// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IHevm} from "./IHevm.sol";
import {Vm} from "forge-std/Vm.sol";

contract Setup {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    IHevm internal vm;
    address internal alice = address(0xf9a);
    address internal bob = address(0xf9b);
    address internal tokenAdmin = address(0xf9c);

    constructor() {
        vm = IHevm(VM_ADDRESS);
    }

    function skipTo(uint256 to) internal {
        vm.warp(to);
    }

    function skipDay(bool additionalSecond) internal {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        vm.warp(block.timestamp + 1 days + secondToAdd);
    }

    function skipWeek(bool additionalSecond) internal {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        vm.warp(block.timestamp + 1 weeks + secondToAdd);
    }

    function _between(
        uint256 val,
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256) {
        return lower + (val % (upper - lower + 1));
    }

    function _convertVm() internal returns (Vm) {
        return Vm(address(vm));
    }
}
