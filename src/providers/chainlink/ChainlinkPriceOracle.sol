// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {AggregatorV3Interface} from "@chainlink/interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {AmountsMath} from "../../lib/AmountsMath.sol";
import {SignedMath} from "../../lib/SignedMath.sol";

contract ChainlinkPriceOracle is IPriceOracle, AccessControl {
    using AmountsMath for uint256;

    struct OracleValue {
        uint256 value;
        uint256 lastUpdate;
    }

    mapping(address => AggregatorV3Interface) internal _feeds;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    error AddressZero();
    error TokenNotSupported();
    error PriceZero();

    event ChangedTokenPriceFeed(address token, address feed);

    constructor() AccessControl() {
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

        _feeds[token] = AggregatorV3Interface(feed);

        emit ChangedTokenPriceFeed(token, feed);
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

        AggregatorV3Interface priceFeed = _feeds[token];
        if (address(priceFeed) == address(0)) {
            revert TokenNotSupported();
        }

        OracleValue memory price = _getFeedValue(priceFeed);

        return price.value;
    }

    function _getFeedValue(AggregatorV3Interface priceFeed) internal view returns (OracleValue memory datum) {
        /*
            latestRoundData SHOULD raise "No data present"
            if they do not have data to report, instead of returning unset values
            which could be misinterpreted as actual reported values.
        */
        (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();

        datum.value = AmountsMath.wrapDecimals(SignedMath.abs(answer), priceFeed.decimals());
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
