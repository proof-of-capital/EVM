// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/ProofOfCapital.sol";

/**
 * @title UpgradeProofOfCapital
 * @dev Upgrade script for ProofOfCapital contract using UUPS proxy pattern
 */
contract UpgradeProofOfCapital is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable proxyAddress = payable(vm.envAddress("PROXY_ADDRESS"));

        console.log("=== Upgrading ProofOfCapital Contract ===");
        console.log("Deployer address:", vm.addr(deployerPrivateKey));
        console.log("Proxy address:", proxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        console.log("\n1. Deploying new implementation...");
        ProofOfCapital newImplementation = new ProofOfCapital();
        console.log("New implementation deployed at:", address(newImplementation));

        // Get proxy instance
        ProofOfCapital proofOfCapital = ProofOfCapital(proxyAddress);

        // Perform upgrade
        console.log("\n2. Performing upgrade...");
        proofOfCapital.upgradeToAndCall(address(newImplementation), "");
        console.log("Upgrade completed successfully");

        vm.stopBroadcast();

        // Verify upgrade
        console.log("\n=== Upgrade Verification ===");
        console.log("Proxy Address:", proxyAddress);
        console.log("New Implementation Address:", address(newImplementation));
        console.log("Is Active:", proofOfCapital.isActive());

        console.log("\n=== Upgrade Complete ===");
    }
}
