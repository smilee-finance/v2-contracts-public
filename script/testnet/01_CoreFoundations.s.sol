// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {PositionManager} from "../../src/PositionManager.sol";
// import {Factory} from "../../src/Factory.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetRegistry} from "../../src/testnet/TestnetRegistry.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/01_CoreFoundations.s.sol:DeployCoreFoundations --fork-url $RPC_LOCALNET --broadcast -vvvv
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/01_CoreFoundations.s.sol:DeployCoreFoundations --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv
 */
contract DeployCoreFoundations is Script {
    uint256 internal _deployerPrivateKey;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    // NOTE: this is the script entrypoint
    function run() external {
        // The broadcast will records the calls and contract creations made and will replay them on-chain.
        // For reference, the broadcast transaction logs will be stored in the broadcast directory.
        vm.startBroadcast(_deployerPrivateKey);
        _doSomething();
        vm.stopBroadcast();
    }

    function _doSomething() internal {
        TestnetToken sUSD = new TestnetToken("Smilee USD", "sUSD");
        AddressProvider ap = new AddressProvider();

        TestnetPriceOracle priceOracle = new TestnetPriceOracle(address(sUSD));
        ap.setPriceOracle(address(priceOracle));
        ap.setMarketOracle(address(priceOracle));

        TestnetSwapAdapter swapper = new TestnetSwapAdapter(address(priceOracle));
        ap.setExchangeAdapter(address(swapper));

        FeeManager feeManager = new FeeManager(0.0035e18, 0.125e18, 0.0015e18, 0.125e18);
        ap.setFeeManager(address(feeManager));

        TestnetRegistry registry = new TestnetRegistry();
        ap.setRegistry(address(registry));

        sUSD.setAddressProvider(address(ap));
        PositionManager pm = new PositionManager();
        ap.setDvpPositionManager(address(pm));
    }
}
