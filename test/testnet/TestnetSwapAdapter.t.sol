// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Registry} from "../../src/Registry.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";

contract TestnetSwapAdapterTest is Test {
    bytes4 constant TokenNotSupported = bytes4(keccak256("TokenNotSupported()"));

    uint256 constant WAD = 10 ** 18;

    address adminWallet = address(0x1);
    address alice = address(0x2);

    TestnetSwapAdapter swapAdapter;
    TestnetToken wETH;
    TestnetToken wBTC;
    TestnetToken usdToken;

    function setUp() public {
        vm.startPrank(adminWallet);
        TestnetPriceOracle priceOracle = new TestnetPriceOracle(address(usdToken));
        swapAdapter = new TestnetSwapAdapter(address(priceOracle));

        Registry registry = new Registry();
        registry.register(address(swapAdapter));
        address controller = address(registry);

        wETH = new TestnetToken("Testnet WETH", "WETH");
        wETH.setController(controller);
        wETH.setSwapper(address(swapAdapter));

        wBTC = new TestnetToken("Testnet WBTC", "WBTC");
        wBTC.setController(controller);
        wBTC.setSwapper(address(swapAdapter));

        usdToken = new TestnetToken("Testnet USD", "USD");
        usdToken.setController(controller);
        usdToken.setSwapper(address(swapAdapter));

        priceOracle.setTokenPrice(address(wETH), 2000 * WAD);
        priceOracle.setTokenPrice(address(wBTC), 20000 * WAD);
        vm.stopPrank();
    }

    /**
     * A not owner user tries to set a new price oracle. Test have to fail due onlyOwner function.
     */
    function testTestnetSwapAdapterUnauthorized() public {
        //vm.startPrank(address(0x100));
        vm.expectRevert("Ownable: caller is not the owner");
        swapAdapter.changePriceOracle(address(0x100));
    }

    /**
     * The contact owner wants to change PriceOracle.
     */
    function testTestnetSwapAdapterChangePriceOracle() public {
        vm.startPrank(adminWallet);
        TestnetPriceOracle newPriceOracle = new TestnetPriceOracle(address(usdToken));

        swapAdapter.changePriceOracle(address(newPriceOracle));
        // TBD: priceOracle is internal. Evaluate to create a getter.
        //assertEq(address(newPriceOracle), swapAdapter.priceOracle);
    }

    /**
     * An user tries to get the the Receiving amount of a pair with tokenInAmount equals to 0.  The amount to receive have to be 0.
     */
    function testTestnetSwapAdapterGetSwapAmountOfZero() public {
        uint256 amountToReceive = swapAdapter.getSwapAmount(address(wETH), address(wBTC), 0);

        assertEq(0, amountToReceive);
    }

    /**
     * TBD: What happens when someone tries to swap the same token.
     */
    function testTestnetSwapAdapterGetSwapAmountOfSameToken() public {}

    /**
     * An user wants to get the receiving amount of a pair.
     */
    function testTestnetSwapAdapterGetSwapAmount() public {
        uint256 amountToReceive = swapAdapter.getSwapAmount(address(wETH), address(wBTC), 1 ether);

        assertEq(0.1 ether, amountToReceive);
    }

    /**
     *  An user wants to get the receiving amount of a pair. The worthest token has been swapped. 
     */
    function testTestnetSwapAdapterGetSwapAmountMoreWorthFirst() public {
        uint256 amountToReceive = swapAdapter.getSwapAmount(address(wBTC), address(wETH), 1 ether);

        assertEq(10 ether, amountToReceive);
    }

    /**
     * Normal Swap: An user wants to swap 10 wETH with 1 Bitcoin. 
     * Test if the getSwapAmount function and the swap gives the same result beside performing the swap.
     */
    function testTestnetSwapAdapterSwap() public {
        TokenUtils.provideApprovedTokens(adminWallet, address(wETH), alice, address(swapAdapter), 100 ether, vm);

        uint256 amountToReceive = swapAdapter.getSwapAmount(address(wETH), address(wBTC), 10 ether);

        vm.prank(alice);
        swapAdapter.swap(address(wETH), address(wBTC), 10 ether);

        assertEq(90 ether, wETH.balanceOf(alice));
        assertEq(amountToReceive. wBTC.balanceOf(alice);)
        assertEq(1 ether, wBTC.balanceOf(alice));
    }
}
