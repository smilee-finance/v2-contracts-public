pragma solidity ^0.8.21;

import {Setup} from "./Setup.sol";

contract Test is Setup {
    event Flag(bool);

    bool private flag0 = true;
    bool private flag1 = true;

    event Log(uint256);

    function set0(int val) public {
        hevm.warp(1703699435);
        if (val % 100 == 0) flag0 = false;
    }

    function set1(int val) public {
        // hevm.warp(1703799435);
        if (val % 10 == 0 && !flag0) flag1 = false;
    }

    function alwaystrue() public pure {
        assert(true);
    }

    function revert_always() public pure {
        assert(false);
    }

    function sometimesfalse() public {
        emit Flag(flag0);
        emit Flag(flag1);
        emit Log(block.timestamp);
        assert(flag1);
    }
}
