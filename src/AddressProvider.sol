// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ToDo: add TimeLock
// TBD: merge with Registry.sol
contract AddressProvider is Ownable {
    address public exchangeAdapter;
    address public priceOracle;
    address public marketOracle;
    address public registry;
    address public dvpPositionManager;
    address public vaultProxy;
    address public feeManager;

    error AddressZero();

    event ChangedExchangeAdapter(address newValue, address oldValue);
    event ChangedPriceOracle(address newValue, address oldValue);
    event ChangedMarketOracle(address newValue, address oldValue);
    event ChangedRegistry(address newValue, address oldValue);
    event ChangedPositionManager(address newValue, address oldValue);
    event ChangedVaultProxy(address newValue, address oldValue);
    event ChangedFeeManager(address newValue, address oldValue);

    constructor() Ownable() {}

    function _checkZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert AddressZero();
        }
    }

    function setExchangeAdapter(address exchangeAdapter_) external onlyOwner {
        _checkZeroAddress(exchangeAdapter_);

        address previous = exchangeAdapter;
        exchangeAdapter = exchangeAdapter_;

        emit ChangedExchangeAdapter(exchangeAdapter_, previous);
    }

    function setPriceOracle(address priceOracle_) external onlyOwner {
        _checkZeroAddress(priceOracle_);

        address previous = priceOracle;
        priceOracle = priceOracle_;

        emit ChangedPriceOracle(priceOracle_, previous);
    }

    function setMarketOracle(address marketOracle_) external onlyOwner {
        _checkZeroAddress(marketOracle_);

        address previous = marketOracle;
        marketOracle = marketOracle_;

        emit ChangedMarketOracle(marketOracle_, previous);
    }

    function setRegistry(address registry_) external onlyOwner {
        _checkZeroAddress(registry_);

        address previous = registry;
        registry = registry_;

        emit ChangedRegistry(registry_, previous);
    }

    function setDvpPositionManager(address posManager_) external onlyOwner {
        _checkZeroAddress(posManager_);

        address previous = dvpPositionManager;
        dvpPositionManager = posManager_;

        emit ChangedPositionManager(posManager_, previous);
    }

    function setVaultProxy(address vaultProxy_) external onlyOwner {
        _checkZeroAddress(vaultProxy_);

        address previous = vaultProxy;
        vaultProxy = vaultProxy_;

        emit ChangedVaultProxy(vaultProxy_, previous);
    }

    function setFeeManager(address feeManager_) external onlyOwner {
        _checkZeroAddress(feeManager_);

        address previous = feeManager;
        feeManager = feeManager_;

        emit ChangedFeeManager(feeManager_, previous);
    }
}
