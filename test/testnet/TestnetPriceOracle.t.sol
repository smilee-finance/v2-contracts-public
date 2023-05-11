// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";

contract TestnetPriceOracleTest is Test {
    bytes4 constant TokenNotSupported = bytes4(keccak256("TokenNotSupported()"));

    address adminWallet = address(0x1);

    TestnetPriceOracle priceOracle;

    address referenceToken = address(0x10000);

    function setUp() public {
        vm.prank(adminWallet);
        priceOracle = new TestnetPriceOracle(referenceToken);
    }

    /**
     * A not owner user tries to set a price of a token. Test have to fail due onlyOwner function.
     */
    function testTestnetPriceOracleUnauthorized() public {
        //vm.startPrank(address(0x100));
        vm.expectRevert("Ownable: caller is not the owner");
        priceOracle.setTokenPrice(address(0x100), 10);
    }

    /**
     * The owner tries to set a price for the 0 address. A TokenNotSupported error should be reverted.
     */
    function testTestnetPriceOracleSetTokenPriceFail() public {
        vm.prank(adminWallet);
        vm.expectRevert(TokenNotSupported);
        priceOracle.setTokenPrice(address(0), 10);
    }

    /**
     *  The owner tries to set a price for a generic token. The price has been setted properly.
     */
    function testTestnetPriceOracleSetTokenPrice() public {
        address genericTokenAddress = address(0x10001);

        vm.prank(adminWallet);
        priceOracle.setTokenPrice(genericTokenAddress, 10*(10**18));

        assertEq(10*(10**18), priceOracle.getTokenPrice(genericTokenAddress));
    }

    /**
     * Check price of reference token
     */
    function testTestnetPriceOracleGetTokenPriceReferenceToken() public {
        assertEq(1000000000000000000, priceOracle.getTokenPrice(referenceToken));
    }

    /**
     * An user tries to get the price of the 0 address. A TokenNotSupported error should be reverted.
     */ 
    function testTestnetPriceOracleGetTokenPriceAddressZero() public {
        vm.expectRevert(TokenNotSupported);
        priceOracle.getTokenPrice(address(0));
    }

    /**
     * An user tries to get the price of a token which it isn't listed. A TokenNotSupported error should be reverted.
     */
    function testTestnetPriceOracleGetTokenPriceMissingToken() public {
        address genericTokenAddress = address(0x10001);

        vm.expectRevert(TokenNotSupported);
        priceOracle.getTokenPrice(genericTokenAddress);
    }

    /**
     * An user tries to get the price of a pair coitains the 0 address. A TokenNotSupported error should be reverted.
     */
    function testTestnetPriceOracleGetPriceOfPairFailOneIsZeroAddress() public {
        address genericTokenAddress = address(0x10001);

        vm.prank(adminWallet);
        priceOracle.setTokenPrice(genericTokenAddress, 10*(10**18));

        vm.expectRevert(TokenNotSupported);
        priceOracle.getPrice(address(0), genericTokenAddress);
        
    }

    /**
     * An user wants to get a price for a pair of tokens.
     */
    function testTestnetPriceOracleGetPriceOfPair() public {
        address genericTokenAddress = address(0x10001);
        address anotherGenericTokenAddress = address(0x10002);


        vm.startPrank(adminWallet);
        priceOracle.setTokenPrice(genericTokenAddress, 10*(10**18));
        priceOracle.setTokenPrice(anotherGenericTokenAddress, 8*(10**18));
        vm.stopPrank();

        
        uint256 price = priceOracle.getPrice(genericTokenAddress, anotherGenericTokenAddress);
        assertEq(1250000000000000000, price);
        
    }


}
