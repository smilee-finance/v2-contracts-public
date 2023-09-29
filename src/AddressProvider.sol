// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAddressProvider} from "./interfaces/IAddressProvider.sol";

// TBD: add TimeLock
// TBD: return an immutable view to be used on each epoch ?
// TBD: merge with Registry.sol
contract AddressProvider is AccessControl, IAddressProvider {
    address public exchangeAdapter;
    address public priceOracle;
    address public marketOracle;
    address public registry;
    address public dvpPositionManager;
    address public vaultProxy;
    address public feeManager;
    address public vaultAccessNFT;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    error AddressZero();

    event ChangedExchangeAdapter(address newValue, address oldValue);
    event ChangedPriceOracle(address newValue, address oldValue);
    event ChangedMarketOracle(address newValue, address oldValue);
    event ChangedRegistry(address newValue, address oldValue);
    event ChangedPositionManager(address newValue, address oldValue);
    event ChangedVaultProxy(address newValue, address oldValue);
    event ChangedFeeManager(address newValue, address oldValue);

    constructor() AccessControl() {
        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    function _checkZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert AddressZero();
        }
    }

    function setExchangeAdapter(address exchangeAdapter_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(exchangeAdapter_);

        address previous = exchangeAdapter;
        exchangeAdapter = exchangeAdapter_;

        emit ChangedExchangeAdapter(exchangeAdapter_, previous);
    }

    function setPriceOracle(address priceOracle_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(priceOracle_);

        address previous = priceOracle;
        priceOracle = priceOracle_;

        emit ChangedPriceOracle(priceOracle_, previous);
    }

    function setMarketOracle(address marketOracle_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(marketOracle_);

        address previous = marketOracle;
        marketOracle = marketOracle_;

        emit ChangedMarketOracle(marketOracle_, previous);
    }

    function setRegistry(address registry_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(registry_);

        address previous = registry;
        registry = registry_;

        emit ChangedRegistry(registry_, previous);
    }

    function setDvpPositionManager(address posManager_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(posManager_);

        address previous = dvpPositionManager;
        dvpPositionManager = posManager_;

        emit ChangedPositionManager(posManager_, previous);
    }

    function setVaultProxy(address vaultProxy_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(vaultProxy_);

        address previous = vaultProxy;
        vaultProxy = vaultProxy_;

        emit ChangedVaultProxy(vaultProxy_, previous);
    }

    function setFeeManager(address feeManager_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(feeManager_);

        address previous = feeManager;
        feeManager = feeManager_;

        emit ChangedFeeManager(feeManager_, previous);
    }

    function setVaultAccessNFT(address vaultAccessNFT_) public {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(vaultAccessNFT_);

        address previous = vaultAccessNFT;
        vaultAccessNFT = vaultAccessNFT_;

        emit ChangedFeeManager(vaultAccessNFT_, previous);
    }
}
