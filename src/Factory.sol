// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {DVPType} from "./lib/DVPType.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {IG} from "./IG.sol";
import {Registry} from "./Registry.sol";
import {Vault} from "./Vault.sol";

// ToDo: review and externalize the registry
contract Factory is Ownable, Registry {

    AddressProvider internal _addressProvider;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Vault is created when event is emitted
     * @param dvpAddress DVP address
     * @param vaultAddress Vault address
     * @param token Base Token address
     */
    event IGMarketCreated(address dvpAddress, address vaultAddress, address token);

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address addressProvider) Ownable() {
        _addressProvider = AddressProvider(addressProvider);
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
        Vault vault = new Vault(baseToken, sideToken, epochFrequency, address(_addressProvider));
        return address(vault);
    }

    function _createImpermanentGainDVP(address vault) internal returns (address) {
        IG dvp = new IG(vault, address(_addressProvider));
        return address(dvp);
    }

    /**
     * Create Impermanent Gain (IG) DVP associating vault to it. 
     * @param baseToken Base Token
     * @param sideToken Side Token
     * @param epochFrequency Epoch Frequency used for rollup and for handling epochs
     * @dev (see interfaces/IDVPImmutables.sol)
     * @return address The address of the created DVP
     */
    function createIGMarket(
        address baseToken,
        address sideToken,
        uint256 epochFrequency
    )
    external onlyOwner returns (address) 
    {
        address vault = _createVault(baseToken, sideToken, epochFrequency); 
        register(vault);
        address dvp = _createImpermanentGainDVP(vault);
        register(dvp);

        Vault(vault).setAllowedDVP(dvp);

        emit IGMarketCreated(dvp, vault, baseToken);  
        return dvp;
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
        VanillaDVP dvp = new VanillaDVP(baseToken, sideToken, vault);
        
        return address(dvp);
    }
    */

}