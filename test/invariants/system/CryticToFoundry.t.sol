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

    function test_2() public {
        vm.warp(block.timestamp + 65280);
        deposit(53660751925402942071444234319586906678597225057891828354971127042736941450);
        vm.warp(block.timestamp + 334984);
        callAdminFunction(2114683348797038701721556498398548843679748884308985742881043097095705417104, 2);
        vm.warp(block.timestamp + 29113);
        buyBull(10616969518659123581099617347038970877541454535286915844038626259034985343772);
    }
}
