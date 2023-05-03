// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";
import {Factory} from "../src/Factory.sol";
import {EpochFrequency} from "../src/lib/EpochFrequency.sol";
import {DVP} from "../src/DVP.sol";
import {DVPType} from "../src/lib/DVPType.sol";
import {Vault} from "../src/Vault.sol";
import {IG} from "../src/IG.sol";

contract FactoryTest is Test {
    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));

    address _tokenAdmin = address(0x1);

    TestnetToken _baseToken;
    TestnetToken _sideToken;
    uint256 _epochFrequency;
    Factory _factory;

    function setUp() public {
        address controller = address(_factory);
        address swapper = address(0x5);

        vm.startPrank(_tokenAdmin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setController(controller);
        token.setSwapper(swapper);
        _baseToken = token;

        token = new TestnetToken("Testnet WETH", "stWETH");
        token.setController(controller);
        token.setSwapper(swapper);
        _sideToken = token;

        Factory factory = new Factory();
        _factory = factory;

        vm.stopPrank();
        vm.warp(EpochFrequency.REF_TS);
    }

    function testFactoryUnauthorized() public {
        //vm.startPrank(address(0x100));
        vm.expectRevert("Ownable: caller is not the owner");
        _factory.createIGMarket(address(_baseToken), address(_sideToken), EpochFrequency.DAILY);
    }

    function testFactoryTokenBaseTokenZero() public {
        vm.startPrank(_tokenAdmin);

        vm.expectRevert(AddressZero);
        _factory.createIGMarket(address(0x0), address(_sideToken), EpochFrequency.DAILY);
    }

    function testFactoryTokenSideTokenZero() public {
        vm.startPrank(_tokenAdmin);

        vm.expectRevert(AddressZero);
        _factory.createIGMarket(address(_baseToken), address(0x0), EpochFrequency.DAILY);
    }

    function testFactoryCreatedDVP() public {
        vm.startPrank(_tokenAdmin);
        address dvp = _factory.createIGMarket(address(_baseToken), address(_sideToken), EpochFrequency.DAILY);
        DVP igDVP = DVP(dvp);

        assertEq(igDVP.baseToken(), address(_baseToken));
        assertEq(igDVP.sideToken(), address(_sideToken));
        assertEq(igDVP.optionType(), DVPType.IG);
        assertEq(igDVP.epochFrequency(), EpochFrequency.DAILY);
    }

    function testFactoryCreatedVault() public {
        vm.startPrank(_tokenAdmin);
        address dvp = _factory.createIGMarket(address(_baseToken), address(_sideToken), EpochFrequency.DAILY);
        DVP igDVP = DVP(dvp);
        Vault vault = Vault(igDVP.vault());
        assertEq(vault.baseToken(), address(_baseToken));
        assertEq(vault.sideToken(), address(_sideToken));
        assertEq(vault.epochFrequency(), EpochFrequency.DAILY);
    }
}
