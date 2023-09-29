// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {AmountsMath} from "../../src/lib/AmountsMath.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {TestnetRegistry} from "../../src/testnet/TestnetRegistry.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {Utils} from "../utils/Utils.sol";

contract TestnetSwapAdapterTest is Test {
    using AmountsMath for uint256;

    bytes4 constant TokenNotSupported = bytes4(keccak256("TokenNotSupported()"));
    bytes4 constant PriceZero = bytes4(keccak256("PriceZero()"));

    uint256 constant WAD = 10 ** 18;

    address adminWallet = address(0x1);
    address alice = address(0x2);

    TestnetPriceOracle priceOracle;
    TestnetSwapAdapter dex;
    TestnetToken WETH;
    TestnetToken WBTC;
    TestnetToken USD;
    TestnetRegistry registry;

    constructor() {
        vm.startPrank(adminWallet);
        USD = new TestnetToken("Testnet USD", "USD");
        WETH = new TestnetToken("Testnet WETH", "WETH");
        WBTC = new TestnetToken("Testnet WBTC", "WBTC");

        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), adminWallet);
        registry = new TestnetRegistry();
        priceOracle = new TestnetPriceOracle(address(USD));
        dex = new TestnetSwapAdapter(address(priceOracle));

        ap.setRegistry(address(registry));
        ap.setExchangeAdapter(address(dex));

        USD.setAddressProvider(address(ap));
        WETH.setAddressProvider(address(ap));
        WBTC.setAddressProvider(address(ap));
        vm.stopPrank();
    }

    function setUp() public {
        vm.startPrank(adminWallet);
        priceOracle.setTokenPrice(address(WETH), 2000 * WAD);
        priceOracle.setTokenPrice(address(WBTC), 20000 * WAD);
        vm.stopPrank();
    }

    function testCannotChangePriceOracle() public {
        vm.expectRevert("Ownable: caller is not the owner");
        dex.changePriceOracle(address(0x100));
    }

    function testChangePriceOracle() public {
        vm.startPrank(adminWallet);
        TestnetPriceOracle newPriceOracle = new TestnetPriceOracle(address(USD));

        dex.changePriceOracle(address(newPriceOracle));
        // TBD: priceOracle is internal. Evaluate to create a getter.
        //assertEq(address(newPriceOracle), dex.priceOracle);
    }

    function testGetOutputAmountOfZero() public {
        uint256 amountToReceive = dex.getOutputAmount(address(WETH), address(WBTC), 0);
        assertEq(0, amountToReceive);
    }

    /**
        TBD: What happens when someone tries to swap the same token.
     */
    function testGetOutputAmountOfSameToken() public {
        uint256 amountToReceive = dex.getOutputAmount(address(WETH), address(WETH), 1 ether);
        assertEq(1 ether, amountToReceive);
    }

    function testGetOutputAmount() public {
        // NOTE: WETH is priced 2000 USD, WBTC is priced 20000 USD.
        uint256 amountToReceive = dex.getOutputAmount(address(WETH), address(WBTC), 1 ether);
        assertEq(0.1 ether, amountToReceive);

        amountToReceive = dex.getOutputAmount(address(WBTC), address(WETH), 1 ether);
        assertEq(10 ether, amountToReceive);
    }

    /**
        Input swap - alice inputs 10 WETH, gets 1 WBTC.
        Test if `getSwapAmount()` and the actual swap give the same result beside performing the swap.
     */
    function testSwapIn() public {
        TokenUtils.provideApprovedTokens(adminWallet, address(WETH), alice, address(dex), 100 ether, vm);

        uint256 input = 10 ether; // WETH
        uint256 amountToReceive = dex.getOutputAmount(address(WETH), address(WBTC), input);

        vm.prank(alice);
        dex.swapIn(address(WETH), address(WBTC), input);

        assertEq(90 ether, WETH.balanceOf(alice));
        assertEq(amountToReceive, WBTC.balanceOf(alice));
    }

    function testGetInputAmountOfZero() public {
        uint256 amountToProvide = dex.getInputAmount(address(WETH), address(WBTC), 0);
        assertEq(0, amountToProvide);
    }

    /**
        TBD: What happens when someone tries to swap the same token.
     */
    function testGetInputAmountOfSameToken() public {
        uint256 amountToProvide = dex.getInputAmount(address(WETH), address(WETH), 1 ether);
        assertEq(1 ether, amountToProvide);
    }

    function testGetInputAmount() public {
        // NOTE: WETH is priced 2000 USD, WBTC is priced 20000 USD.
        uint256 amountToProvide = dex.getInputAmount(address(WETH), address(WBTC), 1 ether);
        assertEq(10 ether, amountToProvide);

        amountToProvide = dex.getInputAmount(address(WBTC), address(WETH), 1 ether);
        assertEq(0.1 ether, amountToProvide);
    }

    /**
        Output swap - alice wants 1 WBTC, inputs 10 WETH
     */
    function testSwapOut() public {
        TokenUtils.provideApprovedTokens(adminWallet, address(WETH), alice, address(dex), 100 ether, vm);

        uint256 wanted = 1 ether; // WBTC
        uint256 amountToGive = dex.getInputAmount(address(WETH), address(WBTC), wanted);
        assertEq(10 ether, amountToGive);

        vm.prank(alice);
        dex.swapOut(address(WETH), address(WBTC), wanted, amountToGive);

        assertEq(90 ether, WETH.balanceOf(alice));
        assertEq(wanted, WBTC.balanceOf(alice));
    }

    /**
        Test `swapIn()` for fuzzy values of WBTC / WETH price
     */
    function testFuzzyPriceSwapIn(uint256 price) public {
        bool success = _setWbtcWethPrice(price);
        if (!success) {
            return;
        }

        uint256 input = 1 ether; // WETH
        TokenUtils.provideApprovedTokens(adminWallet, address(WETH), alice, address(dex), input, vm);

        if (price == 0) {
            vm.expectRevert(PriceZero);
            dex.getOutputAmount(address(WETH), address(WBTC), input);
            return;
        }

        uint256 wbtcForWethAmount = dex.getOutputAmount(address(WETH), address(WBTC), input);
        uint256 expextedWbtcForWethAmount = input.wmul(1e18).wdiv(price);
        assertEq(expextedWbtcForWethAmount, wbtcForWethAmount);

        vm.prank(alice);
        dex.swapIn(address(WETH), address(WBTC), input);
        assertEq(0, WETH.balanceOf(alice));
        assertEq(expextedWbtcForWethAmount, WBTC.balanceOf(alice));
    }

    /**
        Test `swapOut()` for fuzzy values of WBTC / WETH price
     */
    function testFuzzyPriceSwapOut(uint256 price) public {
        bool success = _setWbtcWethPrice(price);
        if (!success) {
            return;
        }

        uint256 output = 1 ether; // WBTC

        if (price == 0) {
            vm.expectRevert(PriceZero);
            dex.getInputAmount(address(WETH), address(WBTC), output);
            return;
        }

        uint256 wethForWbtcAmount = dex.getInputAmount(address(WETH), address(WBTC), output);
        uint256 expextedWethForWbtcAmount = output.wmul(price);
        assertEq(expextedWethForWbtcAmount, wethForWbtcAmount);

        TokenUtils.provideApprovedTokens(adminWallet, address(WETH), alice, address(dex), wethForWbtcAmount, vm);

        vm.prank(alice);
        dex.swapOut(address(WETH), address(WBTC), output, wethForWbtcAmount);
        assertEq(0, WETH.balanceOf(alice));
        assertEq(output, WBTC.balanceOf(alice));
    }

    function _setWbtcWethPrice(uint256 price) private returns (bool) {
        vm.startPrank(adminWallet);
        uint256 wethPrice = priceOracle.getPrice(address(WETH), address(USD));
        if (price > type(uint256).max / wethPrice) {
            vm.expectRevert();
            priceOracle.setTokenPrice(address(WBTC), price.wmul(wethPrice));
            vm.stopPrank();
            return false;
        }
        priceOracle.setTokenPrice(address(WBTC), price.wmul(wethPrice));
        vm.stopPrank();
        return true;
    }
}
