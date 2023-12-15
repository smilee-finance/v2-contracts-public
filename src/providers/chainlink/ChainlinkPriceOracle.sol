// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {AmountsMath} from "../../lib/AmountsMath.sol";

contract ChainlinkPriceOracle is IPriceOracle, AccessControl {
    using AmountsMath for uint256;

    struct OracleValue {
        uint256 value;
        uint256 lastUpdate;
    }

    /// @dev index is token address
    mapping(address => AggregatorV3Interface) public feeds;
    /// @dev index is token address
    mapping(address => uint256) internal _maxDelay;

    uint256 internal _defaultMaxDelay;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    error AddressZero();
    error TokenNotSupported();
    error PriceZero();
    error PriceNegative();
    error PriceTooOld();

    event ChangedTokenPriceFeed(address token, address feed);
    event ChangedTokenPriceFeedMaxDelay(address token, uint256 delay);

    constructor() AccessControl() {
        _defaultMaxDelay = 1 days;

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    /**
        @notice Set the Chainlink aggregator for the price feed <token>/<reference_currency>.
        @param token The ERC20 token.
        @param feed The Chainlink (proxy) aggregator for the price feed <token>/<reference_currency>.
        @dev Assume only aggregators with the same reference currency (e.g. USD).
        @dev Keep in mind the specific aggregator's heartbit and deviation thresholds.
     */
    function setPriceFeed(address token, address feed) external {
        _checkRole(ROLE_ADMIN);
        if (token == address(0) || feed == address(0)) {
            revert AddressZero();
        }

        feeds[token] = AggregatorV3Interface(feed);

        emit ChangedTokenPriceFeed(token, feed);
    }

    function setPriceFeedMaxDelay(address token, uint256 delay) external {
        _checkRole(ROLE_ADMIN);
        if (token == address(0) || address(feeds[token]) == address(0)) {
            revert AddressZero();
        }

        _maxDelay[token] = delay;

        emit ChangedTokenPriceFeedMaxDelay(token, delay);
    }

    function getPriceFeedMaxDelay(address token) public view returns (uint256 maxDelay) {
        maxDelay = _maxDelay[token];
        if (maxDelay == 0) {
            maxDelay = _defaultMaxDelay;
        }
    }

    /**
        @notice Return Price of token in USD
        @param token Address of token
        @return price Price of token in USD
     */
    function getTokenPrice(address token) public view returns (uint256) {
        if (token == address(0)) {
            revert AddressZero();
        }

        AggregatorV3Interface priceFeed = feeds[token];
        if (address(priceFeed) == address(0)) {
            revert TokenNotSupported();
        }

        OracleValue memory price = _getFeedValue(priceFeed);

        // Protect against stale feeds:
        if (block.timestamp - price.lastUpdate > getPriceFeedMaxDelay(token)) {
            revert PriceTooOld();
        }

        return price.value;
    }

    function _getFeedValue(AggregatorV3Interface priceFeed) internal view returns (OracleValue memory datum) {
        /*
            latestRoundData SHOULD raise "No data present"
            if they do not have data to report, instead of returning unset values
            which could be misinterpreted as actual reported values.
        */
        (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();

        if (answer < 0) {
            revert PriceNegative();
        }

        datum.value = AmountsMath.wrapDecimals(uint256(answer), priceFeed.decimals());
        datum.lastUpdate = updatedAt;
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address token0, address token1) external view returns (uint256) {
        // NOTE: both prices are expected to be in the same reference currency (e.g. USD)
        uint256 token0Price = getTokenPrice(token0);
        uint256 token1Price = getTokenPrice(token1);

        if (token1Price == 0) {
            revert PriceZero();
        }

        return token0Price.wdiv(token1Price);
    }
}
