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

// All royalties collected are automatically used to repurchase the project's core token, as
// specified on the website, and are returned to the contract.

// This is the third version of the contract. It introduces the following features: the ability to choose any jetton as collateral, build collateral with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.
pragma solidity 0.8.29;

import {BaseTest} from "../utils/BaseTest.sol";
import {ProofOfCapital} from "../../src/ProofOfCapital.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IProofOfCapital} from "../../src/interfaces/IProofOfCapital.sol";
import {Constants} from "../../src/utils/Constant.sol";

contract ProofOfCapitalInitializationTest is BaseTest {
    ProofOfCapital public implementation;

    function setUp() public override {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023

        vm.startPrank(owner);

        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");

        vm.stopPrank();
    }

    // Test InitialPriceMustBePositive error
    function testInitializeInitialPriceMustBePositiveZero() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.initialPricePerToken = 0; // Invalid: zero price

        vm.expectRevert(IProofOfCapital.InitialPriceMustBePositive.selector);
        new ProofOfCapital(params);
    }

    function testInitializeInitialPriceMustBePositiveValid() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.initialPricePerToken = 1; // Valid: minimum positive price

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify price was set
        assertEq(proofOfCapital.initialPricePerToken(), 1);
    }

    // Test InvalidLevelDecreaseMultiplierAfterTrend error
    function testInitializeMultiplierTooHigh() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierAfterTrend = int256(Constants.PERCENTAGE_DIVISOR); // Invalid: equal to divisor

        vm.expectRevert(IProofOfCapital.InvalidLevelDecreaseMultiplierAfterTrend.selector);
        new ProofOfCapital(params);
    }

    function testInitializeMultiplierTooHighAboveDivisor() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierAfterTrend = int256(Constants.PERCENTAGE_DIVISOR + 1); // Invalid: above divisor

        vm.expectRevert(IProofOfCapital.InvalidLevelDecreaseMultiplierAfterTrend.selector);
        new ProofOfCapital(params);
    }

    function testInitializeMultiplierValidAtBoundary() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierAfterTrend = int256(Constants.PERCENTAGE_DIVISOR - 1); // Valid: just below divisor
        params.offsetLaunch = 100e18; // Smaller offset to avoid overflow in calculations

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify multiplier was set
        assertEq(proofOfCapital.levelDecreaseMultiplierAfterTrend(), int256(Constants.PERCENTAGE_DIVISOR - 1));
    }

    // Test InvalidLevelIncreaseMultiplier error for levelIncreaseMultiplier
    function testInitializeLevelIncreaseMultiplierTooLow() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelIncreaseMultiplier = -int256(Constants.PERCENTAGE_DIVISOR); // Invalid: below minimum range

        vm.expectRevert(IProofOfCapital.InvalidLevelIncreaseMultiplier.selector);
        new ProofOfCapital(params);
    }

    function testInitializeLevelIncreaseMultiplierValid() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelIncreaseMultiplier = 1; // Valid: minimum positive value

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify multiplier was set
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 1);
    }

    // Test InvalidLevelIncreaseMultiplier error for levelIncreaseMultiplier above range
    function testInitializeLevelIncreaseMultiplierTooHigh() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelIncreaseMultiplier = int256(Constants.PERCENTAGE_DIVISOR); // Invalid: above maximum range

        vm.expectRevert(IProofOfCapital.InvalidLevelIncreaseMultiplier.selector);
        new ProofOfCapital(params);
    }

    // Test PriceIncrementTooLow error for priceIncrementMultiplier
    function testInitializePriceIncrementMultiplierTooLow() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.priceIncrementMultiplier = 0; // Invalid: zero multiplier

        vm.expectRevert(IProofOfCapital.PriceIncrementTooLow.selector);
        new ProofOfCapital(params);
    }

    function testInitializePriceIncrementMultiplierValid() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.priceIncrementMultiplier = 1; // Valid: minimum positive value

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify multiplier was set
        assertEq(proofOfCapital.priceIncrementMultiplier(), 1);
    }

    // Test InvalidRoyaltyProfitPercentage error - too low
    function testInitializeRoyaltyProfitPercentageTooLow() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 1; // Invalid: must be > 1

        vm.expectRevert(IProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ProofOfCapital(params);
    }

    function testInitializeRoyaltyProfitPercentageZero() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 0; // Invalid: must be > 1

        vm.expectRevert(IProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ProofOfCapital(params);
    }

    // Test InvalidRoyaltyProfitPercentage error - too high
    function testInitializeRoyaltyProfitPercentageTooHigh() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT + 1; // Invalid: above maximum

        vm.expectRevert(IProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ProofOfCapital(params);
    }

    function testInitializeRoyaltyProfitPercentageValidMinimum() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 2; // Valid: minimum value > 1

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify percentage was set
        assertEq(proofOfCapital.royaltyProfitPercent(), 2);
    }

    function testInitializeRoyaltyProfitPercentageValidMaximum() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT; // Valid: exactly at maximum

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify percentage was set
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.MAX_ROYALTY_PERCENT);
    }

    // Test boundary values for all parameters
    function testInitializeBoundaryValues() public {
        IProofOfCapital.InitParams memory params = getValidParams();

        // Set all parameters to their boundary values with smaller offsetLaunch
        params.initialPricePerToken = 1; // Minimum valid
        params.levelDecreaseMultiplierAfterTrend = 500; // Safe value below divisor
        params.levelIncreaseMultiplier = 1; // Minimum valid
        params.priceIncrementMultiplier = 1; // Minimum valid
        params.royaltyProfitPercent = 2; // Minimum valid
        params.offsetLaunch = 100e18; // Smaller offset to avoid overflow

        // Should not revert with all boundary values
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify all parameters were set correctly
        assertEq(proofOfCapital.initialPricePerToken(), 1);
        assertEq(proofOfCapital.levelDecreaseMultiplierAfterTrend(), 500);
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 1);
        assertEq(proofOfCapital.priceIncrementMultiplier(), 1);
        assertEq(proofOfCapital.royaltyProfitPercent(), 2);
    }

    // Test multiple failing conditions together
    function testInitializeMultipleInvalidParameters() public {
        IProofOfCapital.InitParams memory params = getValidParams();

        // Set multiple invalid parameters - should fail on first one (initialPricePerToken)
        params.initialPricePerToken = 0; // Invalid
        params.levelIncreaseMultiplier = 0; // Also invalid, but won't be reached

        // Should fail with the first error it encounters
        vm.expectRevert(IProofOfCapital.InitialPriceMustBePositive.selector);
        new ProofOfCapital(params);
    }

    // Test maximum valid values
    function testInitializeMaximumValidValues() public {
        IProofOfCapital.InitParams memory params = getValidParams();

        // Set to reasonable maximum values to avoid overflow
        params.initialPricePerToken = 1000e18; // Large but reasonable price
        params.levelDecreaseMultiplierAfterTrend = 999; // Just below PERCENTAGE_DIVISOR
        params.levelIncreaseMultiplier = 999; // Just below PERCENTAGE_DIVISOR
        params.priceIncrementMultiplier = 10000; // Large but reasonable multiplier
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT; // Maximum royalty
        params.offsetLaunch = 1000e18; // Smaller offset to avoid calculations overflow

        // Should not revert with maximum values
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify values were set
        assertEq(proofOfCapital.initialPricePerToken(), 1000e18);
        assertEq(proofOfCapital.levelDecreaseMultiplierAfterTrend(), 999);
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 999);
        assertEq(proofOfCapital.priceIncrementMultiplier(), 10000);
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.MAX_ROYALTY_PERCENT);
    }

    // Tests for _getPeriod function through initialization
    function testInitializeControlPeriodBelowMin() public {
        vm.startPrank(owner);
        // Setup init params with control period below minimum (1 second)
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 1000e18,
            controlPeriod: 1, // Way below minimum
            collateralToken: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        ProofOfCapital testContract = new ProofOfCapital(params);

        // Should be set to minimum
        assertEq(testContract.controlPeriod(), Constants.MIN_CONTROL_PERIOD);

        vm.stopPrank();
    }

    function testInitializeControlPeriodAboveMax() public {
        vm.startPrank(owner);
        // Setup init params with control period above maximum
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 1000e18,
            controlPeriod: Constants.MAX_CONTROL_PERIOD + 1 days, // Above maximum
            collateralToken: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        ProofOfCapital testContract = new ProofOfCapital(params);

        // Should be set to maximum
        assertEq(testContract.controlPeriod(), Constants.MAX_CONTROL_PERIOD);

        vm.stopPrank();
    }

    function testInitializeControlPeriodWithinRange() public {
        vm.startPrank(owner);
        // Calculate a valid period between min and max
        uint256 validPeriod = (Constants.MIN_CONTROL_PERIOD + Constants.MAX_CONTROL_PERIOD) / 2;

        // Setup init params with control period within valid range
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 1000e18,
            controlPeriod: validPeriod, // Within valid range
            collateralToken: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        ProofOfCapital testContract = new ProofOfCapital(params);

        // Should be set to the provided value
        assertEq(testContract.controlPeriod(), validPeriod);

        vm.stopPrank();
    }

    function testInitializeControlPeriodAtBoundaries() public {
        vm.startPrank(owner);

        // Test at minimum boundary
        {
            IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
                initialOwner: owner,
                launchToken: address(token),
                marketMakerAddress: marketMaker,
                returnWalletAddress: returnWallet,
                royaltyWalletAddress: royalty,
                lockEndTime: block.timestamp + 365 days,
                initialPricePerToken: 1e18,
                firstLevelTokenQuantity: 1000e18,
                priceIncrementMultiplier: 50,
                levelIncreaseMultiplier: 100,
                trendChangeStep: 5,
                levelDecreaseMultiplierAfterTrend: 50,
                profitPercentage: 100,
                offsetLaunch: 1000e18,
                controlPeriod: Constants.MIN_CONTROL_PERIOD, // Exactly minimum
                collateralToken: address(weth),
                royaltyProfitPercent: 500,
                oldContractAddresses: new address[](0),
                profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
                daoAddress: address(0), // Will default to owner
                collateralTokenOracle: address(0),
                collateralTokenMinOracleValue: 0
            });

            ProofOfCapital testContract = new ProofOfCapital(params);

            assertEq(testContract.controlPeriod(), Constants.MIN_CONTROL_PERIOD);
        }

        // Test at maximum boundary
        {
            IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
                initialOwner: owner,
                launchToken: address(token),
                marketMakerAddress: marketMaker,
                returnWalletAddress: returnWallet,
                royaltyWalletAddress: royalty,
                lockEndTime: block.timestamp + 365 days,
                initialPricePerToken: 1e18,
                firstLevelTokenQuantity: 1000e18,
                priceIncrementMultiplier: 50,
                levelIncreaseMultiplier: 100,
                trendChangeStep: 5,
                levelDecreaseMultiplierAfterTrend: 50,
                profitPercentage: 100,
                offsetLaunch: 1000e18,
                controlPeriod: Constants.MAX_CONTROL_PERIOD, // Exactly maximum
                collateralToken: address(weth),
                royaltyProfitPercent: 500,
                oldContractAddresses: new address[](0),
                profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
                daoAddress: address(0), // Will default to owner
                collateralTokenOracle: address(0),
                collateralTokenMinOracleValue: 0
            });

            ProofOfCapital testContract = new ProofOfCapital(params);

            assertEq(testContract.controlPeriod(), Constants.MAX_CONTROL_PERIOD);
        }

        vm.stopPrank();
    }

    // Tests for address validation requirements

    // Test CannotBeSelf error - returnWalletAddress matches old contract
    function testInitializeReturnWalletMatchesOldContract() public {
        address oldContract = address(0x123);
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = oldContract;

        IProofOfCapital.InitParams memory params = getValidParams();
        params.returnWalletAddress = oldContract; // Invalid: matches old contract
        params.oldContractAddresses = oldContracts;

        vm.expectRevert(IProofOfCapital.CannotBeSelf.selector);
        new ProofOfCapital(params);
    }

    // Test CannotBeSelf error - royaltyWalletAddress matches old contract
    function testInitializeRoyaltyWalletMatchesOldContract() public {
        address oldContract = address(0x123);
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = oldContract;

        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyWalletAddress = oldContract; // Invalid: matches old contract
        params.oldContractAddresses = oldContracts;

        vm.expectRevert(IProofOfCapital.CannotBeSelf.selector);
        new ProofOfCapital(params);
    }

    // Test CannotBeSelf error - returnWalletAddress equals royaltyWalletAddress
    function testInitializeReturnWalletEqualsRoyaltyWallet() public {
        address sameAddress = address(0x999);

        IProofOfCapital.InitParams memory params = getValidParams();
        params.returnWalletAddress = sameAddress; // Invalid: same as royalty wallet
        params.royaltyWalletAddress = sameAddress; // Invalid: same as return wallet

        vm.expectRevert(IProofOfCapital.CannotBeSelf.selector);
        new ProofOfCapital(params);
    }

    // Test multiple old contracts - returnWallet matches one of them
    function testInitializeReturnWalletMatchesMultipleOldContracts() public {
        address oldContract1 = address(0x123);
        address oldContract2 = address(0x456);
        address oldContract3 = address(0x789);

        address[] memory oldContracts = new address[](3);
        oldContracts[0] = oldContract1;
        oldContracts[1] = oldContract2;
        oldContracts[2] = oldContract3;

        IProofOfCapital.InitParams memory params = getValidParams();
        params.returnWalletAddress = oldContract2; // Invalid: matches middle old contract
        params.oldContractAddresses = oldContracts;

        vm.expectRevert(IProofOfCapital.CannotBeSelf.selector);
        new ProofOfCapital(params);
    }

    // Test multiple old contracts - royaltyWallet matches one of them
    function testInitializeRoyaltyWalletMatchesMultipleOldContracts() public {
        address oldContract1 = address(0x123);
        address oldContract2 = address(0x456);
        address oldContract3 = address(0x789);

        address[] memory oldContracts = new address[](3);
        oldContracts[0] = oldContract1;
        oldContracts[1] = oldContract2;
        oldContracts[2] = oldContract3;

        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyWalletAddress = oldContract3; // Invalid: matches last old contract
        params.oldContractAddresses = oldContracts;

        vm.expectRevert(IProofOfCapital.CannotBeSelf.selector);
        new ProofOfCapital(params);
    }

    // Test valid scenario - no conflicts
    function testInitializeValidAddressesNoConflicts() public {
        address oldContract1 = address(0x123);
        address oldContract2 = address(0x456);
        address uniqueReturnWallet = address(0x777);
        address uniqueRoyaltyWallet = address(0x888);

        address[] memory oldContracts = new address[](2);
        oldContracts[0] = oldContract1;
        oldContracts[1] = oldContract2;

        IProofOfCapital.InitParams memory params = getValidParams();
        params.returnWalletAddress = uniqueReturnWallet; // Valid: unique address
        params.royaltyWalletAddress = uniqueRoyaltyWallet; // Valid: unique address
        params.oldContractAddresses = oldContracts;

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify addresses were set correctly
        assertTrue(proofOfCapital.returnWalletAddresses(uniqueReturnWallet));
        assertEq(proofOfCapital.royaltyWalletAddress(), uniqueRoyaltyWallet);
    }

    // Test edge case - empty old contracts array
    function testInitializeEmptyOldContractsArray() public {
        address[] memory emptyOldContracts = new address[](0);

        IProofOfCapital.InitParams memory params = getValidParams();
        params.oldContractAddresses = emptyOldContracts;

        // Should not revert - no old contracts to check against
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify addresses were set correctly
        assertTrue(proofOfCapital.returnWalletAddresses(params.returnWalletAddress));
        assertEq(proofOfCapital.royaltyWalletAddress(), params.royaltyWalletAddress);
    }

    // Test complex scenario - multiple violations should fail on first one
    function testInitializeMultipleViolationsFailOnFirst() public {
        address sameAddress = address(0x999);
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = sameAddress;

        IProofOfCapital.InitParams memory params = getValidParams();
        // Multiple violations:
        // 1. returnWalletAddress matches old contract (checked first)
        // 2. returnWalletAddress equals royaltyWalletAddress (checked third)
        params.returnWalletAddress = sameAddress; // Invalid: matches old contract
        params.royaltyWalletAddress = sameAddress; // Also invalid but won't be reached
        params.oldContractAddresses = oldContracts;

        // Should fail with first error encountered (returnWallet matches old contract)
        vm.expectRevert(IProofOfCapital.CannotBeSelf.selector);
        new ProofOfCapital(params);
    }

    // Test boundary case - exactly one old contract
    function testInitializeExactlyOneOldContract() public {
        address oldContract = address(0x123);
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = oldContract;

        // Test valid case first
        IProofOfCapital.InitParams memory paramsValid = getValidParams();
        paramsValid.oldContractAddresses = oldContracts;
        paramsValid.returnWalletAddress = address(0x777); // Different from old contract
        paramsValid.royaltyWalletAddress = address(0x888); // Different from old contract

        // Should not revert
        ProofOfCapital proofOfCapitalValid = new ProofOfCapital(paramsValid);

        assertTrue(proofOfCapitalValid.returnWalletAddresses(address(0x777)));
        assertEq(proofOfCapitalValid.royaltyWalletAddress(), address(0x888));
    }

    // Test zero address scenario (should pass address validation but may fail other checks)
    function testInitializeZeroAddressInOldContracts() public {
        address[] memory oldContracts = new address[](2);
        oldContracts[0] = address(0);
        oldContracts[1] = address(0x123);

        IProofOfCapital.InitParams memory params = getValidParams();
        params.returnWalletAddress = address(0); // Zero address - matches old contract
        params.oldContractAddresses = oldContracts;

        vm.expectRevert(IProofOfCapital.CannotBeSelf.selector);
        new ProofOfCapital(params);
    }

    // Test ProfitBeforeTrendChangeMustBePositive error
    function testInitializeProfitBeforeTrendChangeMustBePositiveZero() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.profitBeforeTrendChange = 0; // Invalid: zero value

        vm.expectRevert(IProofOfCapital.ProfitBeforeTrendChangeMustBePositive.selector);
        new ProofOfCapital(params);
    }

    function testInitializeProfitBeforeTrendChangeMustBePositiveValid() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.profitBeforeTrendChange = 1; // Valid: minimum positive value

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify value was set
        assertEq(proofOfCapital.profitBeforeTrendChange(), 1);
    }
}
