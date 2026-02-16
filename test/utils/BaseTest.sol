// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM
// Proof of Capital is a technology for managing the issue of tokens that are backed by capital.
// The contract allows you to block the desired part of the issue for a selected period with a
// guaranteed buyback under pre-set conditions.

// During the lock-up period, only the market maker appointed by the contract creator has the
// right to buyback the tokens. Starting two months before the lock-up ends, any token holders
// can interact with the contract. They have the right to return their purchased tokens to the
// contract in exchange for the collateral.

// The goal of our technology is to create a market for assets backed by capital and
// transparent issuance management conditions.

// You can integrate the provided contract and Proof of Capital technology into your token if
// you specify the royalty wallet address of our project, listed on our website:
// https://proofofcapital.org

// All royalties collected are automatically used to repurchase the project’s core token, as
// specified on the website, and are returned to the contract.

// This is the third version of the contract. It introduces the following features: the ability to choose any jetton as collateral, build collateral with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {ProofOfCapital} from "../../src/ProofOfCapital.sol";
import {IProofOfCapital} from "../../src/interfaces/IProofOfCapital.sol";
import {Constants} from "../../src/utils/Constant.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockRoyalty} from "../mocks/MockRoyalty.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseTest is Test {
    using SafeERC20 for IERC20;
    using stdStorage for StdStorage;

    ProofOfCapital public proofOfCapital;
    MockERC20 public token;
    MockERC20 public weth;
    MockRoyalty public mockRoyalty;

    address public owner = address(0x1);
    address public royalty;
    address public returnWallet = address(0x3);
    address public marketMaker = address(0x4);

    StdStorage private _stdStore;

    function setUp() public virtual {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023

        vm.startPrank(owner);

        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");

        // Deploy mock royalty contract
        mockRoyalty = new MockRoyalty();
        royalty = address(mockRoyalty);

        // Prepare initialization parameters
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 10000e18, // Add offset to enable trading
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            collateralToken: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            RETURN_BURN_CONTRACT_ADDRESS: address(0),
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        // Deploy contract directly (no proxy needed)
        proofOfCapital = new ProofOfCapital(params);

        vm.stopPrank();
    }

    // Helper function to get valid initialization parameters
    function getValidParams() internal view returns (IProofOfCapital.InitParams memory) {
        return IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            collateralToken: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            RETURN_BURN_CONTRACT_ADDRESS: address(0),
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });
    }

    // Helper function to deploy contract with custom parameters
    function deployWithParams(IProofOfCapital.InitParams memory params) internal returns (ProofOfCapital) {
        return new ProofOfCapital(params);
    }

    // Helper function to create collateral balance in contract
    function createCollateralBalance(uint256 amount) internal {
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, amount * 2); // Give enough for selling back
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), amount * 2);
        proofOfCapital.sellLaunchTokensReturnWallet(amount); // This increases launchBalance
        vm.stopPrank();
    }

    // Helper function to get initialization parameters without offset
    function getParamsWithoutOffset() internal view returns (IProofOfCapital.InitParams memory) {
        return IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 0, // No offset
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            collateralToken: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            RETURN_BURN_CONTRACT_ADDRESS: address(0),
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });
    }

    // Helper function to initialize contract by processing all unaccounted offset
    // This sets isInitialized to true
    function initializeContract() internal {
        uint256 unaccountedOffset = proofOfCapital.unaccountedOffset();
        if (unaccountedOffset > 0) {
            // Setup trading access by manipulating controlDay to be in the past
            uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
            vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

            vm.prank(owner);
            proofOfCapital.calculateUnaccountedOffsetBalance(unaccountedOffset);

            assertTrue(proofOfCapital.isInitialized(), "Contract should be initialized after processing offset");
        }
    }
}
