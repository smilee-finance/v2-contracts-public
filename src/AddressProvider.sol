// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAddressProvider} from "./interfaces/IAddressProvider.sol";
import {TimeLock, TimeLockedAddress} from "./lib/TimeLock.sol";

// TBD: return an immutable view to be used on each epoch ?
// TBD: merge with Registry.sol
contract AddressProvider is AccessControl, IAddressProvider {
    using TimeLock for TimeLockedAddress;

    uint256 internal immutable _timeLockDelay;

    TimeLockedAddress internal _exchangeAdapter;
    TimeLockedAddress internal _priceOracle;
    TimeLockedAddress internal _marketOracle;
    TimeLockedAddress internal _registry;
    TimeLockedAddress internal _dvpPositionManager;
    TimeLockedAddress internal _vaultProxy;
    TimeLockedAddress internal _feeManager;
    TimeLockedAddress internal _vaultAccessNFT;

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

    constructor(uint256 timeLockDelay_) AccessControl() {
        _timeLockDelay = timeLockDelay_;

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

        address previous = _exchangeAdapter.get();
        _exchangeAdapter.set(exchangeAdapter_, _timeLockDelay);

        emit ChangedExchangeAdapter(exchangeAdapter_, previous);
    }

    function exchangeAdapter() public view returns (address) {
        return _exchangeAdapter.get();
    }

    function setPriceOracle(address priceOracle_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(priceOracle_);

        address previous = _priceOracle.get();
        _priceOracle.set(priceOracle_, _timeLockDelay);

        emit ChangedPriceOracle(priceOracle_, previous);
    }

    function priceOracle() public view returns (address) {
        return _priceOracle.get();
    }

    function setMarketOracle(address marketOracle_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(marketOracle_);

        address previous = _marketOracle.get();
        _marketOracle.set(marketOracle_, _timeLockDelay);

        emit ChangedMarketOracle(marketOracle_, previous);
    }

    function marketOracle() public view returns (address) {
        return _marketOracle.get();
    }

    function setRegistry(address registry_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(registry_);

        address previous = _registry.get();
        _registry.set(registry_, _timeLockDelay);

        emit ChangedRegistry(registry_, previous);
    }

    function registry() public view returns (address) {
        return _registry.get();
    }

    function setDvpPositionManager(address posManager_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(posManager_);

        address previous = _dvpPositionManager.get();
        _dvpPositionManager.set(posManager_, _timeLockDelay);

        emit ChangedPositionManager(posManager_, previous);
    }

    function dvpPositionManager() public view returns (address) {
        return _dvpPositionManager.get();
    }

    function setVaultProxy(address vaultProxy_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(vaultProxy_);

        address previous = _vaultProxy.get();
        _vaultProxy.set(vaultProxy_, _timeLockDelay);

        emit ChangedVaultProxy(vaultProxy_, previous);
    }

    function vaultProxy() public view returns (address) {
        return _vaultProxy.get();
    }

    function setFeeManager(address feeManager_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(feeManager_);

        address previous = _feeManager.get();
        _feeManager.set(feeManager_, _timeLockDelay);

        emit ChangedFeeManager(feeManager_, previous);
    }

    function feeManager() public view returns (address) {
        return _feeManager.get();
    }

    function setVaultAccessNFT(address vaultAccessNFT_) public {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(vaultAccessNFT_);

        address previous = _vaultAccessNFT.get();
        _vaultAccessNFT.set(vaultAccessNFT_, _timeLockDelay);

        emit ChangedFeeManager(vaultAccessNFT_, previous);
    }

    function vaultAccessNFT() public view returns (address) {
        return _vaultAccessNFT.get();
    }
}
