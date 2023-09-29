// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol"; 
import {console} from "forge-std/console.sol"; 
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {Position} from "../src/lib/Position.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {IG} from "../src/IG.sol";


contract ChainTest is Test {

    constructor() {
        uint256 forkId = vm.createFork(vm.rpcUrl("https://rpc-node-smil.dxit.it"));
        vm.selectFork(forkId);
    }

    function testino() public {
        // IG ig = IG(0x65dc24e40Eabb875382E8a42B1d503d2B9F4dB2E);
        // console.logBytes32(Position.getID(0x6D6745b17383168D1178d6e3354f1dCB3b18e86A, false, 1790190000000000000000));
        // //Position.Info memory info = ig._epochPositions(ig.currentEpoch(), Position.getID(0xCeb53FeB6C04E020BD25c9fac980A283942F8Eac, false, 1790190000000000193699));

        // console.log("CurrentEpoch", ig.currentEpoch());
        // console.log("CurrentStrike", ig.currentStrike());
        // Position.Info memory info = ig.getPosition(ig.currentEpoch(), 0xCeb53FeB6C04E020BD25c9fac980A283942F8Eac, false, 1790190000000000193699);
        // console.log(info.amount);
        // console.log(info.strategy);
        // console.log(info.strike);
        // console.log(info.epoch);
        // // ig.premium(0, false, 100000000000000000000);
        // IPositionManager pm = IPositionManager(0xCeb53FeB6C04E020BD25c9fac980A283942F8Eac);
        // console.log("Pos Strike", pm.positionDetail(1).strike);
        // IPositionManager.SellParams memory sellParams = IPositionManager.SellParams(
        //     1,
        //     100000000000000000000
        // );

        
        
        // IPositionManager.PositionDetail memory posDet = pm.positionDetail(1);
        // console.log(posDet.expiry);

        // // uint256 res = pm.tokenOfOwnerByIndex(0x6D6745b17383168D1178d6e3354f1dCB3b18e86A, 0);
        // // console.log("Res", res);
        // vm.startPrank(0x6D6745b17383168D1178d6e3354f1dCB3b18e86A);

        // IPositionManager.MintParams memory mintParams = IPositionManager.MintParams (
        //     1,
        //     0x65dc24e40Eabb875382E8a42B1d503d2B9F4dB2E,
        //     100000000000000000000,
        //     1790190000000000300000,
        //     false,
        //     0x6D6745b17383168D1178d6e3354f1dCB3b18e86A
        // );

        // //pm.mint(mintParams);
        // //pm.sell(sellParams);
    }
}
