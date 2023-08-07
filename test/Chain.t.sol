// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IDVP} from "../src/interfaces/IDVP.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {OptionStrategy} from "../src/lib/OptionStrategy.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {IG} from "../src/IG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";

contract ChainTest is Test {
    constructor() {
        uint256 forkId = vm.createFork(vm.rpcUrl("https://rpc-node-smil.dxit.it"));
        vm.selectFork(forkId);
        
    }

    function testPremium() public {
        IG ig = IG(0x4e5ad53194b8C7a17647d956D6CF92D6262a517c);
        MockedVault vault = MockedVault(ig.vault());

        VaultUtils.logState(vault);
        vm.prank(0xd4039eB67CBB36429Ad9DD30187B94f6A5122215);
        vault.initiateWithdraw(5000000000000000000);

        //ig.premium(0, false, 100000000000000000000);
    }
}
