// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IRegistry {
    /**
     * @notice Checks wheather an address is a DVP or not
     * @param  addr A generic address
     * @return ok Response of the check
     */
    function isRegistered(address addr) external view returns (bool ok);

    /**
     * Unregister an address from the registry
     * @param addr A generic address to remove
     */
    function unregister(address addr) external;
}
