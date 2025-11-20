// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/ProofOfCapital.sol";

/**
 * @title DeployProofOfCapital
 * @dev Deployment script for ProofOfCapital contract using UUPS proxy pattern
 */
contract DeployProofOfCapital is Script {
    // Contract instances
    ProofOfCapital public proofOfCapital;

    // Deployment parameters as state variables to avoid "Stack too deep" error
    uint256 public deployerPrivateKey;
    address public launchToken;
    address public marketMakerAddress;
    address public returnWalletAddress;
    address public royaltyWalletAddress;
    uint256 public lockEndTime;
    uint256 public initialPricePerToken;
    uint256 public firstLevelTokenQuantity;
    uint256 public priceIncrementMultiplier;
    uint256 public levelIncreaseMultiplier;
    uint256 public trendChangeStep;
    uint256 public levelDecreaseMultiplierafterTrend;
    uint256 public profitPercentage;
    uint256 public offsetTokens;
    uint256 public controlPeriod;
    address public collateralAddress;
    uint256 public royaltyProfitPercent;
    address[] public oldContractAddresses;
    uint256 public profitBeforeTrendChange;
    address public daoAddress;

    function run() external {
        _loadEnvironmentVariables();
        _validateParameters();
        _logDeploymentInfo();
        _deployContracts();
        _verifyDeployment();
        _saveDeploymentInfo();

        console.log("\n=== Deployment Complete ===");
        console.log("Use this address to interact with the contract:", address(proofOfCapital));
    }

    /**
     * @dev Load all environment variables into state variables
     */
    function _loadEnvironmentVariables() internal {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        launchToken = vm.envAddress("LAUNCH_TOKEN");
        marketMakerAddress = vm.envAddress("MARKET_MAKER_ADDRESS");
        returnWalletAddress = vm.envAddress("RETURN_WALLET_ADDRESS");
        royaltyWalletAddress = vm.envAddress("ROYALTY_WALLET_ADDRESS");

        // Token support address is set by Makefile based on network
        collateralAddress = vm.envAddress("TOKEN_SUPPORT_ADDRESS");

        lockEndTime = vm.envUint("LOCK_END_TIME");
        initialPricePerToken = vm.envUint("INITIAL_PRICE_PER_TOKEN");
        firstLevelTokenQuantity = vm.envUint("FIRST_LEVEL_TOKEN_QUANTITY");
        priceIncrementMultiplier = vm.envUint("PRICE_INCREMENT_MULTIPLIER");
        levelIncreaseMultiplier = vm.envUint("LEVEL_INCREASE_MULTIPLIER");
        trendChangeStep = vm.envUint("TREND_CHANGE_STEP");
        levelDecreaseMultiplierafterTrend = vm.envUint("LEVEL_DECREASE_MULTIPLIER_AFTER_TREND");
        profitPercentage = vm.envUint("PROFIT_PERCENTAGE");
        offsetTokens = vm.envUint("OFFSET_TOKENS");
        controlPeriod = vm.envUint("CONTROL_PERIOD");
        royaltyProfitPercent = vm.envUint("ROYALTY_PROFIT_PERCENT");

        // Load optional parameters with defaults
        try vm.envUint("PROFIT_BEFORE_TREND_CHANGE") returns (uint256 value) {
            profitBeforeTrendChange = value;
        } catch {
            profitBeforeTrendChange = profitPercentage * 2; // Default: double profit before trend
        }

        try vm.envAddress("DAO_ADDRESS") returns (address value) {
            daoAddress = value;
        } catch {
            daoAddress = address(0); // Will default to owner in initialize
        }

        // Parse old contract addresses (optional)
        try vm.envString("OLD_CONTRACT_ADDRESSES") returns (string memory oldContractsStr) {
            if (bytes(oldContractsStr).length > 0) {
                oldContractAddresses = _parseAddresses(oldContractsStr);
            }
        } catch {
            // Leave empty array if no old contracts specified
        }
    }

    /**
     * @dev Validate deployment parameters
     */
    function _validateParameters() internal view {
        require(launchToken != address(0), "Invalid launch token address");
        require(marketMakerAddress != address(0), "Invalid market maker address");
        require(returnWalletAddress != address(0), "Invalid return wallet address");
        require(royaltyWalletAddress != address(0), "Invalid royalty wallet address");
        require(collateralAddress != address(0), "Invalid token support address");
        require(lockEndTime > block.timestamp, "Lock end time must be in the future");
        require(lockEndTime - block.timestamp <= 365 days * 2, "Lock period cannot exceed 2 years");
        require(initialPricePerToken > 0, "Initial price must be positive");
        require(royaltyProfitPercent > 0 && royaltyProfitPercent <= 1000, "Invalid royalty percentage");

        console.log("All parameters validated successfully");
    }

    /**
     * @dev Log deployment information
     */
    function _logDeploymentInfo() internal view {
        console.log("=== Deploying ProofOfCapital Contract ===");
        console.log("Deployer address:", vm.addr(deployerPrivateKey));
        console.log("Launch Token:", launchToken);
        console.log("Market Maker:", marketMakerAddress);
        console.log("Return Wallet:", returnWalletAddress);
        console.log("Royalty Wallet:", royaltyWalletAddress);
        console.log("Token Support Address:", collateralAddress);
    }

    /**
     * @dev Deploy contract directly (no proxy needed)
     */
    function _deployContracts() internal {
        vm.startBroadcast(deployerPrivateKey);

        // Prepare initialization parameters
        ProofOfCapital.InitParams memory initParams = _prepareInitParams();

        // Deploy contract directly
        console.log("\nDeploying ProofOfCapital contract...");
        proofOfCapital = new ProofOfCapital(initParams);
        console.log("Contract deployed at:", address(proofOfCapital));

        vm.stopBroadcast();
    }

    /**
     * @dev Prepare initialization parameters struct
     */
    function _prepareInitParams() internal view returns (ProofOfCapital.InitParams memory) {
        address deployer = vm.addr(deployerPrivateKey);
        return ProofOfCapital.InitParams({
            initialOwner: deployer,
            launchToken: launchToken,
            marketMakerAddress: marketMakerAddress,
            returnWalletAddress: returnWalletAddress,
            royaltyWalletAddress: royaltyWalletAddress,
            lockEndTime: lockEndTime,
            initialPricePerToken: initialPricePerToken,
            firstLevelTokenQuantity: firstLevelTokenQuantity,
            priceIncrementMultiplier: priceIncrementMultiplier,
            levelIncreaseMultiplier: levelIncreaseMultiplier,
            trendChangeStep: trendChangeStep,
            levelDecreaseMultiplierafterTrend: levelDecreaseMultiplierafterTrend,
            profitPercentage: profitPercentage,
            offsetTokens: offsetTokens,
            controlPeriod: controlPeriod,
            collateralAddress: collateralAddress,
            royaltyProfitPercent: royaltyProfitPercent,
            oldContractAddresses: oldContractAddresses,
            profitBeforeTrendChange: profitBeforeTrendChange,
            daoAddress: daoAddress
        });
    }

    /**
     * @dev Verify deployment success
     */
    function _verifyDeployment() internal view {
        console.log("\n=== Deployment Verification ===");
        console.log("ProofOfCapital Address:", address(proofOfCapital));

        console.log("\n=== Contract State Verification ===");
        console.log("Is Active:", proofOfCapital.isActive());
        console.log("Lock End Time:", proofOfCapital.lockEndTime());
        console.log("Current Price:", proofOfCapital.currentPrice());
        console.log("Total Tokens Sold:", proofOfCapital.totalLaunchSold());
        console.log("Contract Support Balance:", proofOfCapital.contractSupportBalance());
        console.log("Profit In Time:", proofOfCapital.profitInTime());
        console.log("Can Withdrawal:", proofOfCapital.canWithdrawal());
    }

    /**
     * @dev Parse comma-separated addresses string
     */
    function _parseAddresses(string memory addressesStr) internal pure returns (address[] memory) {
        // This is a simplified parser - in production you might want a more robust solution
        bytes memory strBytes = bytes(addressesStr);
        if (strBytes.length == 0) {
            return new address[](0);
        }

        // Count commas to determine array size
        uint256 count = 1;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == ",") {
                count++;
            }
        }

        address[] memory addresses = new address[](count);
        uint256 index = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= strBytes.length; i++) {
            if (i == strBytes.length || strBytes[i] == ",") {
                bytes memory addrBytes = new bytes(i - start);
                for (uint256 j = start; j < i; j++) {
                    addrBytes[j - start] = strBytes[j];
                }
                addresses[index] = _parseAddress(string(addrBytes));
                index++;
                start = i + 1;
            }
        }

        return addresses;
    }

    /**
     * @dev Parse address from string (removing spaces)
     */
    function _parseAddress(string memory addr) internal pure returns (address) {
        bytes memory addrBytes = bytes(addr);
        bytes memory cleanAddr = new bytes(42); // 0x + 40 hex chars
        uint256 cleanIndex = 0;

        for (uint256 i = 0; i < addrBytes.length; i++) {
            if (addrBytes[i] != " ") {
                cleanAddr[cleanIndex] = addrBytes[i];
                cleanIndex++;
            }
        }

        return vm.parseAddress(string(cleanAddr));
    }

    /**
     * @dev Save deployment information to file
     */
    function _saveDeploymentInfo() internal {
        string memory deploymentInfo = string(
            abi.encodePacked(
                "ProofOfCapital Deployment Info\n",
                "==============================\n",
                "Network: ",
                vm.toString(block.chainid),
                "\n",
                "Block Number: ",
                vm.toString(block.number),
                "\n",
                "Contract Address: ",
                vm.toString(address(proofOfCapital)),
                "\n",
                "Deployed At: ",
                vm.toString(block.timestamp),
                "\n"
            )
        );

        string memory filename = string(abi.encodePacked("deployment-", vm.toString(block.chainid), ".txt"));

        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);
    }
}
