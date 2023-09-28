// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {IExchange} from "../src/interfaces/IExchange.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {AddressProvider} from "../src/AddressProvider.sol";
import {SwapAdapterRouter} from "../src/providers/SwapAdapterRouter.sol";
import {TestnetPriceOracle} from "../src/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "../src/testnet/TestnetSwapAdapter.sol";
import {TestnetRegistry} from "../src/testnet/TestnetRegistry.sol";
import {TestnetToken} from "../src/testnet/TestnetToken.sol";

contract SwapProviderRouterTest is Test {
    bytes4 constant _ADDRESS_ZERO = bytes4(keccak256("AddressZero()"));
    bytes4 constant _SLIPPAGE = bytes4(keccak256("Slippage()"));
    bytes4 constant _SWAP_ZERO = bytes4(keccak256("SwapZero()"));

    address _admin = address(0x1);
    address _alice = address(0x2);

    TestnetToken _token0;
    TestnetToken _token1;
    IPriceOracle _oracle;
    SwapAdapterRouter _swapRouter;
    IPriceOracle _swapOracle;
    IExchange _swap;

    function setUp() public {
        vm.startPrank(_admin);

        _oracle = new TestnetPriceOracle(address(0x123));
        _swapOracle = new TestnetPriceOracle(address(0x123));
        _swap = new TestnetSwapAdapter(address(_swapOracle));
        _swapRouter = new SwapAdapterRouter(address(_oracle));

        AddressProvider ap = new AddressProvider();
        TestnetRegistry r = new TestnetRegistry();
        ap.setExchangeAdapter(address(_swap));
        ap.setRegistry(address(r));
        _token0 = new TestnetToken("USDC", "");
        _token1 = new TestnetToken("ETH", "");
        _token0.setAddressProvider(address(ap));
        _token1.setAddressProvider(address(ap));
        vm.stopPrank();
    }

    function testConstructor() public {
        assertEq(address(_oracle), _swapRouter.getPriceOracle());
        assertEq(_admin, _swapRouter.owner());

        vm.expectRevert("Ownable: caller is not the owner");
        _swapRouter.setPriceOracle(address(0x100));

        vm.expectRevert("Ownable: caller is not the owner");
        _swapRouter.setAdapter(address(_token0), address(_token1), address(0x100));

        vm.expectRevert("Ownable: caller is not the owner");
        _swapRouter.setSlippage(address(_token0), address(_token1), 500);
    }

    function testSetters() public {
        vm.startPrank(_admin);

        _swapRouter.setPriceOracle(address(0x100));
        assertEq(address(0x100), _swapRouter.getPriceOracle());

        _swapRouter.setAdapter(address(_token0), address(_token1), address(0x101));
        assertEq(address(0x101), _swapRouter.getAdapter(address(_token0), address(_token1)));

        _swapRouter.setSlippage(address(_token0), address(_token1), 500);
        assertEq(500, _swapRouter.getSlippage(address(_token0), address(_token1)));

        vm.stopPrank();
    }

    /// @dev Fail when giving too little input
    function testSwapInFailDown() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 1.5e18;
        uint256 maxSlippage = 0.2e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, true);

        vm.startPrank(_alice);
        _token0.approve(address(_swapRouter), amount);
        vm.expectRevert(_SLIPPAGE);
        _swapRouter.swapIn(address(_token0), address(_token1), amount);
        vm.stopPrank();
    }

    /// @dev Fail when giving too much output
    function testSwapInFailUp() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 0.5e18;
        uint256 maxSlippage = 0.2e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, true);

        vm.startPrank(_alice);
        _token0.approve(address(_swapRouter), amount);
        vm.expectRevert(_SLIPPAGE);
        _swapRouter.swapIn(address(_token0), address(_token1), amount);
        vm.stopPrank();
    }

    function testSwapInOk() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 1.2e18;
        uint256 maxSlippage = 0.2e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, true);

        vm.startPrank(_alice);
        _token0.approve(address(_swapRouter), amount);
        _swapRouter.swapIn(address(_token0), address(_token1), amount);
        assertEq(0, _token0.balanceOf(_alice));
        assertApproxEqAbs((amount * 10 ** _token0.decimals()) / swapPriceRef, _token1.balanceOf(_alice), amount / 1e18);
        vm.stopPrank();
    }

    /// @dev Fail when requiring too much input
    function testSwapOutFailUp() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 1.5e18;
        uint256 maxSlippage = 0.2e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, false);

        vm.startPrank(_alice);
        uint256 t0IniBal = _token0.balanceOf(_alice);
        _token0.approve(address(_swapRouter), t0IniBal);
        vm.expectRevert("ERC20: insufficient allowance");
        _swapRouter.swapOut(address(_token0), address(_token1), amount, t0IniBal);
        vm.stopPrank();
    }

    /// @dev Fail when requiring too little input
    function testSwapOutFailDown() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 0.5e18;
        uint256 maxSlippage = 0.2e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, false);

        vm.startPrank(_alice);
        uint256 t0IniBal = _token0.balanceOf(_alice);
        _token0.approve(address(_swapRouter), t0IniBal);
        vm.expectRevert(_SLIPPAGE);
        _swapRouter.swapOut(address(_token0), address(_token1), amount, t0IniBal);
        vm.stopPrank();
    }

    function testSwapOutOk() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 1.1e18;
        uint256 maxSlippage = 0.2e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, false);

        vm.startPrank(_alice);
        uint256 t0IniBal = _token0.balanceOf(_alice);
        uint256 shouldSpend = (amount * swapPriceRef) / 10 ** _token1.decimals();
        _token0.approve(address(_swapRouter), t0IniBal);
        uint256 spent = _swapRouter.swapOut(address(_token0), address(_token1), amount, t0IniBal);
        assertApproxEqAbs(shouldSpend, spent, 1e3);
        assertEq(t0IniBal - spent, _token0.balanceOf(_alice));
        assertEq(amount, _token1.balanceOf(_alice));
        vm.stopPrank();
    }

    // function testSwapInFuzzy(uint256 amount, uint256 realPriceRef, uint256 swapPriceRef, uint256 maxSlippage) public {
    //     amount = bound(amount, 1e9, type(uint128).max); // avoid price to be too big
    //     realPriceRef = bound(realPriceRef, 1e9, type(uint128).max); // avoid price to be too big
    //     swapPriceRef = bound(swapPriceRef, 1e9, type(uint128).max); // avoid price to be too big
    //     vm.assume(realPriceRef < swapPriceRef);
    //     maxSlippage = bound(maxSlippage, 0.001e18, 0.5e18); // 0.1 - 50% - significant values

    //     _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, true);
    //     uint256 realPrice = _oracle.getPrice(address(_token0), address(_token1));
    //     uint256 swapPrice = _swapOracle.getPrice(address(_token0), address(_token1));

    //     vm.startPrank(_alice);
    //     _token0.approve(address(_swapRouter), amount);

    //     // check if expected output is 0
    //     uint256 expectedOutput = (amount * _swapOracle.getPrice(address(_token0), address(_token1))) / 1e18;
    //     if (expectedOutput == 0) {
    //         vm.expectRevert(_SWAP_ZERO);
    //         _swapRouter.swapIn(address(_token0), address(_token1), amount);
    //     } else if (_priceRangeOk(realPrice, swapPrice, maxSlippage)) {
    //         _swapRouter.swapIn(address(_token0), address(_token1), amount);
    //         assertEq(0, _token0.balanceOf(_alice));
    //         assertApproxEqAbs(
    //             (amount * 10 ** _token0.decimals()) / swapPriceRef,
    //             _token1.balanceOf(_alice),
    //             amount / 1e18
    //         );
    //     } else {
    //         vm.expectRevert(_SLIPPAGE);
    //         _swapRouter.swapIn(address(_token0), address(_token1), amount);
    //     }
    //     vm.stopPrank();
    // }

    // function testSwapOutFuzzy(uint256 amount, uint256 realPriceRef, uint256 swapPriceRef, uint256 maxSlippage) public {
    //     amount = bound(amount, 1e9, type(uint128).max); // avoid price to be too big
    //     realPriceRef = bound(realPriceRef, 1e9, type(uint128).max); // avoid price to be too big
    //     swapPriceRef = bound(swapPriceRef, 1e9, type(uint128).max); // avoid price to be too big
    //     vm.assume(realPriceRef < swapPriceRef);
    //     maxSlippage = bound(maxSlippage, 0.001e18, 0.5e18); // 0.1 - 50% - significant values

    //     _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, false);
    //     uint256 realPrice = _oracle.getPrice(address(_token0), address(_token1));
    //     uint256 swapPrice = _swapOracle.getPrice(address(_token0), address(_token1));

    //     vm.startPrank(_alice);
    //     uint256 t0IniBal = _token0.balanceOf(_alice);
    //     uint256 shouldSpend = (amount * swapPriceRef) / 10 ** _token1.decimals();
    //     _token0.approve(address(_swapRouter), t0IniBal);

    //     if (_priceRangeOk(realPrice, swapPrice, maxSlippage)) {
    //         uint256 spent = _swapRouter.swapOut(address(_token0), address(_token1), amount);
    //         assertApproxEqAbs(shouldSpend, spent, shouldSpend / 1e18);
    //         assertEq(t0IniBal - spent, _token0.balanceOf(_alice));
    //         assertEq(amount, _token1.balanceOf(_alice));
    //     } else {
    //         if (_priceRangeOkLow(realPrice, swapPrice, maxSlippage)) {
    //             vm.expectRevert("ERC20: insufficient allowance");
    //         } else {
    //             vm.expectRevert(_SLIPPAGE);
    //         }
    //         _swapRouter.swapOut(address(_token0), address(_token1), amount);
    //     }
    //     vm.stopPrank();
    // }

    function _adminSetup(
        uint256 swapAmount,
        uint256 realPriceRef,
        uint256 swapPriceRef,
        uint256 maxSlippage,
        bool isIn
    ) private {
        vm.startPrank(_admin);
        TestnetPriceOracle(address(_oracle)).setTokenPrice(address(_token0), 1e18);
        TestnetPriceOracle(address(_oracle)).setTokenPrice(address(_token1), realPriceRef);
        TestnetPriceOracle(address(_swapOracle)).setTokenPrice(address(_token0), 1e18);
        TestnetPriceOracle(address(_swapOracle)).setTokenPrice(address(_token1), swapPriceRef);
        _swapRouter.setPriceOracle(address(_oracle));
        _swapRouter.setAdapter(address(_token0), address(_token1), address(_swap));
        _swapRouter.setAdapter(address(_token1), address(_token0), address(_swap));
        _swapRouter.setSlippage(address(_token0), address(_token1), maxSlippage);
        _swapRouter.setSlippage(address(_token1), address(_token0), maxSlippage);
        _token0.setTransferRestriction(false);
        _token1.setTransferRestriction(false);

        if (isIn) {
            _token0.mint(_alice, swapAmount);
        } else {
            uint256 amountInMax = _swapRouter.getInputAmount(address(_token0), address(_token1), swapAmount);
            _token0.mint(_alice, amountInMax);
        }
        vm.stopPrank();
    }

    /// @dev Tells if the swap price within a range from the real one +/- slippage
    function _priceRangeOk(uint256 realPrice, uint256 swapPrice, uint256 maxSlippage) private pure returns (bool) {
        return
            _priceRangeOkHigh(realPrice, swapPrice, maxSlippage) && _priceRangeOkLow(realPrice, swapPrice, maxSlippage);
    }

    function _priceRangeOkHigh(uint256 realPrice, uint256 swapPrice, uint256 maxSlippage) private pure returns (bool) {
        return swapPrice * 1e18 <= realPrice * (1e18 + maxSlippage);
    }

    function _priceRangeOkLow(uint256 realPrice, uint256 swapPrice, uint256 maxSlippage) private pure returns (bool) {
        return swapPrice * 1e18 >= realPrice * (1e18 - maxSlippage);
    }
}