// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test() public {
        vm.warp(block.timestamp + 15790);
        deposit(753780546426345955413931157775832410930106);
        vm.warp(block.timestamp + 99568);
        callAdminFunction(
            42058281372472454962807870485987314089146113209336814108751744773162,
            94586397242477222477402127700118551742513176453076716598512929824532
        );
        callAdminFunction(
            42520534683753573551241396107604603541460636312716439758751609768970802983,
            3722225677400697555411638394426114732703479860560469910417771863973355293
        );
        initiateWithdraw(744596680349883318272300);
        vm.warp(block.timestamp + 59060);
        callAdminFunction(10, 2592262954105063);
    }
}
