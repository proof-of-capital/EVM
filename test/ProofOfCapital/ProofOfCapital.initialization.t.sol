// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVMpragma solidity ^0.8.19;

import "../utils/BaseTest.sol";

contract ProofOfCapitalInitializationTest is BaseTest {
    ProofOfCapital public implementation;
    
    function setUp() public override {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023
        
        vm.startPrank(owner);
        
        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");
        
        // Deploy implementation
        implementation = new ProofOfCapital();
        
        vm.stopPrank();
    }
    
    // Test InitialPriceMustBePositive error
    function testInitializeInitialPriceMustBePositiveZero() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.initialPricePerToken = 0; // Invalid: zero price
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        vm.expectRevert(ProofOfCapital.InitialPriceMustBePositive.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    function testInitializeInitialPriceMustBePositiveValid() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.initialPricePerToken = 1; // Valid: minimum positive price
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should not revert
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital proofOfCapital = ProofOfCapital(address(proxy));
        
        // Verify price was set
        assertEq(proofOfCapital.initialPricePerToken(), 1);
    }
    
    // Test MultiplierTooHigh error
    function testInitializeMultiplierTooHigh() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierafterTrend = Constants.PERCENTAGE_DIVISOR; // Invalid: equal to divisor
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        vm.expectRevert(ProofOfCapital.MultiplierTooHigh.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    function testInitializeMultiplierTooHighAboveDivisor() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierafterTrend = Constants.PERCENTAGE_DIVISOR + 1; // Invalid: above divisor
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        vm.expectRevert(ProofOfCapital.MultiplierTooHigh.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    function testInitializeMultiplierValidAtBoundary() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierafterTrend = Constants.PERCENTAGE_DIVISOR - 1; // Valid: just below divisor
        params.offsetJettons = 100e18; // Smaller offset to avoid overflow in calculations
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should not revert
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital proofOfCapital = ProofOfCapital(address(proxy));
        
        // Verify multiplier was set
        assertEq(proofOfCapital.levelDecreaseMultiplierafterTrend(), Constants.PERCENTAGE_DIVISOR - 1);
    }
    
    // Test MultiplierTooLow error for levelIncreaseMultiplier
    function testInitializeLevelIncreaseMultiplierTooLow() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.levelIncreaseMultiplier = 0; // Invalid: zero multiplier
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        vm.expectRevert(ProofOfCapital.MultiplierTooLow.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    function testInitializeLevelIncreaseMultiplierValid() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.levelIncreaseMultiplier = 1; // Valid: minimum positive value
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should not revert
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital proofOfCapital = ProofOfCapital(address(proxy));
        
        // Verify multiplier was set
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 1);
    }
    
    // Test PriceIncrementTooLow error for priceIncrementMultiplier
    function testInitializePriceIncrementMultiplierTooLow() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.priceIncrementMultiplier = 0; // Invalid: zero multiplier
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        vm.expectRevert(ProofOfCapital.PriceIncrementTooLow.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    function testInitializePriceIncrementMultiplierValid() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.priceIncrementMultiplier = 1; // Valid: minimum positive value
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should not revert
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital proofOfCapital = ProofOfCapital(address(proxy));
        
        // Verify multiplier was set
        assertEq(proofOfCapital.priceIncrementMultiplier(), 1);
    }
    
    // Test InvalidRoyaltyProfitPercentage error - too low
    function testInitializeRoyaltyProfitPercentageTooLow() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 1; // Invalid: must be > 1
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        vm.expectRevert(ProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    function testInitializeRoyaltyProfitPercentageZero() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 0; // Invalid: must be > 1
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        vm.expectRevert(ProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    // Test InvalidRoyaltyProfitPercentage error - too high
    function testInitializeRoyaltyProfitPercentageTooHigh() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT + 1; // Invalid: above maximum
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        vm.expectRevert(ProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    function testInitializeRoyaltyProfitPercentageValidMinimum() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 2; // Valid: minimum value > 1
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should not revert
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital proofOfCapital = ProofOfCapital(address(proxy));
        
        // Verify percentage was set
        assertEq(proofOfCapital.royaltyProfitPercent(), 2);
    }
    
    function testInitializeRoyaltyProfitPercentageValidMaximum() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT; // Valid: exactly at maximum
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should not revert
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital proofOfCapital = ProofOfCapital(address(proxy));
        
        // Verify percentage was set
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.MAX_ROYALTY_PERCENT);
    }
    
    // Test boundary values for all parameters
    function testInitializeBoundaryValues() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        
        // Set all parameters to their boundary values with smaller offsetJettons
        params.initialPricePerToken = 1; // Minimum valid
        params.levelDecreaseMultiplierafterTrend = 500; // Safe value below divisor
        params.levelIncreaseMultiplier = 1; // Minimum valid
        params.priceIncrementMultiplier = 1; // Minimum valid
        params.royaltyProfitPercent = 2; // Minimum valid
        params.offsetJettons = 100e18; // Smaller offset to avoid overflow
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should not revert with all boundary values
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital proofOfCapital = ProofOfCapital(address(proxy));
        
        // Verify all parameters were set correctly
        assertEq(proofOfCapital.initialPricePerToken(), 1);
        assertEq(proofOfCapital.levelDecreaseMultiplierafterTrend(), 500);
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 1);
        assertEq(proofOfCapital.priceIncrementMultiplier(), 1);
        assertEq(proofOfCapital.royaltyProfitPercent(), 2);
    }
    
    // Test multiple failing conditions together
    function testInitializeMultipleInvalidParameters() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        
        // Set multiple invalid parameters - should fail on first one (initialPricePerToken)
        params.initialPricePerToken = 0; // Invalid
        params.levelIncreaseMultiplier = 0; // Also invalid, but won't be reached
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should fail with the first error it encounters
        vm.expectRevert(ProofOfCapital.InitialPriceMustBePositive.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
    
    // Test maximum valid values
    function testInitializeMaximumValidValues() public {
        ProofOfCapital.InitParams memory params = getValidParams();
        
        // Set to reasonable maximum values to avoid overflow
        params.initialPricePerToken = 1000e18; // Large but reasonable price
        params.levelDecreaseMultiplierafterTrend = 999; // Just below PERCENTAGE_DIVISOR
        params.levelIncreaseMultiplier = 10000; // Large but reasonable multiplier
        params.priceIncrementMultiplier = 10000; // Large but reasonable multiplier
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT; // Maximum royalty
        params.offsetJettons = 1000e18; // Smaller offset to avoid calculations overflow
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        // Should not revert with maximum values
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital proofOfCapital = ProofOfCapital(address(proxy));
        
        // Verify values were set
        assertEq(proofOfCapital.initialPricePerToken(), 1000e18);
        assertEq(proofOfCapital.levelDecreaseMultiplierafterTrend(), 999);
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 10000);
        assertEq(proofOfCapital.priceIncrementMultiplier(), 10000);
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.MAX_ROYALTY_PERCENT);
    }
    
    // Tests for _getPeriod function through initialization
    function testInitializeControlPeriodBelowMin() public {
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        
        // Setup init params with control period below minimum (1 second)
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(weth),
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 1000e18,
            controlPeriod: 1, // Way below minimum
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0)
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital testContract = ProofOfCapital(address(proxy));
        
        // Should be set to minimum
        assertEq(testContract.controlPeriod(), Constants.MIN_CONTROL_PERIOD);
        
        vm.stopPrank();
    }
    
    function testInitializeControlPeriodAboveMax() public {
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        
        // Setup init params with control period above maximum
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(weth),
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 1000e18,
            controlPeriod: Constants.MAX_CONTROL_PERIOD + 1 days, // Above maximum
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0)
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital testContract = ProofOfCapital(address(proxy));
        
        // Should be set to maximum
        assertEq(testContract.controlPeriod(), Constants.MAX_CONTROL_PERIOD);
        
        vm.stopPrank();
    }
    
    function testInitializeControlPeriodWithinRange() public {
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        
        // Calculate a valid period between min and max
        uint256 validPeriod = (Constants.MIN_CONTROL_PERIOD + Constants.MAX_CONTROL_PERIOD) / 2;
        
        // Setup init params with control period within valid range
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(weth),
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 1000e18,
            controlPeriod: validPeriod, // Within valid range
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0)
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital testContract = ProofOfCapital(address(proxy));
        
        // Should be set to the provided value
        assertEq(testContract.controlPeriod(), validPeriod);
        
        vm.stopPrank();
    }
    
    function testInitializeControlPeriodAtBoundaries() public {
        vm.startPrank(owner);
        
        // Test at minimum boundary
        {
            ProofOfCapital implementation = new ProofOfCapital();
            ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
                launchToken: address(token),
                marketMakerAddress: marketMaker,
                returnWalletAddress: returnWallet,
                royaltyWalletAddress: royalty,
                wethAddress: address(weth),
                lockEndTime: block.timestamp + 365 days,
                initialPricePerToken: 1e18,
                firstLevelJettonQuantity: 1000e18,
                priceIncrementMultiplier: 50,
                levelIncreaseMultiplier: 100,
                trendChangeStep: 5,
                levelDecreaseMultiplierafterTrend: 50,
                profitPercentage: 100,
                offsetJettons: 1000e18,
                controlPeriod: Constants.MIN_CONTROL_PERIOD, // Exactly minimum
                jettonSupportAddress: address(weth),
                royaltyProfitPercent: 500,
                oldContractAddresses: new address[](0)
            });
            
            bytes memory initData = abi.encodeWithSelector(
                ProofOfCapital.initialize.selector,
                params
            );
            
            ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
            ProofOfCapital testContract = ProofOfCapital(address(proxy));
            
            assertEq(testContract.controlPeriod(), Constants.MIN_CONTROL_PERIOD);
        }
        
        // Test at maximum boundary
        {
            ProofOfCapital implementation = new ProofOfCapital();
            ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
                launchToken: address(token),
                marketMakerAddress: marketMaker,
                returnWalletAddress: returnWallet,
                royaltyWalletAddress: royalty,
                wethAddress: address(weth),
                lockEndTime: block.timestamp + 365 days,
                initialPricePerToken: 1e18,
                firstLevelJettonQuantity: 1000e18,
                priceIncrementMultiplier: 50,
                levelIncreaseMultiplier: 100,
                trendChangeStep: 5,
                levelDecreaseMultiplierafterTrend: 50,
                profitPercentage: 100,
                offsetJettons: 1000e18,
                controlPeriod: Constants.MAX_CONTROL_PERIOD, // Exactly maximum
                jettonSupportAddress: address(weth),
                royaltyProfitPercent: 500,
                oldContractAddresses: new address[](0)
            });
            
            bytes memory initData = abi.encodeWithSelector(
                ProofOfCapital.initialize.selector,
                params
            );
            
            ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
            ProofOfCapital testContract = ProofOfCapital(address(proxy));
            
            assertEq(testContract.controlPeriod(), Constants.MAX_CONTROL_PERIOD);
        }
        
        vm.stopPrank();
    }
} 