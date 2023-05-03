// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {DVPType} from "./lib/DVPType.sol";
import {Vault} from "./Vault.sol";
import {IG} from "./IG.sol";

contract Factory is Ownable {

    // Map to save DVPs
    mapping(address => bool) registered;

    /** 
     * Create Vault given baseToken and sideToken
     * @param baseToken Base Token 
     * @param sideToken Side Token
     * @param epochFrequency Epoch Frequency used for rollup and for handling epochs
     * @dev (see interfaces/IDVPImmutables.sol)
     * @return address The address of the created Vault
     */
    function _createVault(
        address baseToken, 
        address sideToken, 
        uint256 epochFrequency
    ) 
        internal returns (address)  
    {
        Vault vault = new Vault(baseToken, sideToken, epochFrequency);
        return address(vault);
    }


    /**
     * Create Impermanent Gain (IG) DVP associating vault to it. 
     * @param baseToken Base Token
     * @param sideToken Side Token
     * @param epochFrequency Epoch Frequency used for rollup and for handling epochs
     * @dev (see interfaces/IDVPImmutables.sol)
     * @return address The address of the created DVP
     */
    function createIGDVP(
        address baseToken,
        address sideToken,
        uint256 epochFrequency
    ) 
    external returns (address) 
    {
        address vault = _createVault(baseToken, sideToken, epochFrequency); 
        IDVP dvp = new IG(baseToken, sideToken, vault);
        
        return address(dvp);
    }


    /**
     * Create Vanilla DVP associating vault to it.
     * @param baseToken Base Token
     * @param sideToken Side Token
     * @param epochFrequency Epoch Frequency used for rollup and for handling epochs
     * @return address The address of the created DVP
     */
    /**
    function createVanillaDVP(
        address baseToken,
        address sideToken,
        uint256 epochFrequency
    )
    external returns (address) {
        address vault = _createVault(baseToken, sideToken, epochFrequency); 
        IDVP dvp = new VanillaDVP(baseToken, sideToken, vault);
        
        return address(dvp);
    }
    */

    
}