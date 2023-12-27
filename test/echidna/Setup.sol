pragma solidity ^0.8.15;

import {IHevm} from "./IHevm.sol";

contract Setup {
    IHevm _hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    constructor() {}
}
