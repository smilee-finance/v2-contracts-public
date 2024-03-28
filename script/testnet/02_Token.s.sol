// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
// import {SwapAdapterRouter} from "@project/providers/SwapAdapterRouter.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/02_Token.s.sol:DeployToken --fork-url $RPC_LOCALNET --broadcast -vvvv --sig 'deployToken(string memory)' <SYMBOL>
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/02_Token.s.sol:DeployToken --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv --sig 'deployToken(string memory)' <SYMBOL>
 */
contract DeployToken is EnhancedScript {

    uint256 internal _deployerPrivateKey;
    uint256 internal _adminPrivateKey;
    AddressProvider internal _ap;
    address internal _sUSD;
    address internal _swapAdapter;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _ap = AddressProvider(_readAddress(txLogs, "AddressProvider"));
        _sUSD = _readAddress(txLogs, "TestnetToken");
        _swapAdapter = _readAddress(txLogs, "TestnetSwapAdapter");
    }

    function run() external {
        address sETH = _deployToken("ETH");
        setTokenPrice(sETH, 3440e18);
    }

    function deployToken(string memory symbol) public {
        _deployToken(symbol);
    }

    function _deployToken(string memory symbol) internal returns (address sTokenAddr) {
        string memory tokenName = string.concat("Smilee ", symbol);
        string memory tokenSymbol = string.concat("s", symbol);

        vm.startBroadcast(_deployerPrivateKey);
        TestnetToken sToken = new TestnetToken(tokenName, tokenSymbol);
        sToken.setTransferRestriction(false);
        sToken.setAddressProvider(address(_ap));
        sTokenAddr = address(sToken);
        vm.stopBroadcast();

        console.log(string.concat("Token s", symbol, " deployed at"), sTokenAddr);

        // vm.startBroadcast(_adminPrivateKey);
        // SwapAdapterRouter swapAdapterRouter = SwapAdapterRouter(_ap.exchangeAdapter());
        // swapAdapterRouter.setAdapter(_sUSD, sTokenAddr, _swapAdapter);
        // swapAdapterRouter.setAdapter(sTokenAddr, _sUSD, _swapAdapter);
        // vm.stopBroadcast();
    }

    function setTokenPrice(address token, uint256 price) public {
        TestnetPriceOracle priceOracle = TestnetPriceOracle(_ap.priceOracle());

        vm.startBroadcast(_deployerPrivateKey);
        priceOracle.setTokenPrice(token, price);
        vm.stopBroadcast();
    }

    function mint(address tokenAddr, address recipient, uint256 amount) public {
        TestnetToken sToken = TestnetToken(tokenAddr);
        amount = amount * (10 ** sToken.decimals());

        vm.startBroadcast(_deployerPrivateKey);
        sToken.mint(recipient, amount);
        vm.stopBroadcast();
    }

}
