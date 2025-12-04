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
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProofOfCapital} from "../../src/interfaces/IProofOfCapital.sol";
import {ProofOfCapital} from "../../src/ProofOfCapital.sol";
import {console} from "forge-std/console.sol";
import {Constants} from "../../src/utils/Constant.sol";

contract ProofOfCapitalSellTokensTest is BaseTest {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    StdStorage private _stdstore;
    address public user = address(0x5);

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Setup tokens for users
        SafeERC20.safeTransfer(IERC20(address(token)), address(proofOfCapital), 500000e18);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 50000e18);
        SafeERC20.safeTransfer(IERC20(address(token)), user, 50000e18);
        SafeERC20.safeTransfer(IERC20(address(token)), marketMaker, 50000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), user, 50000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), marketMaker, 50000e18);

        // Enable market maker for user to allow trading
        proofOfCapital.setMarketMaker(user, true);

        vm.stopPrank();

        // Approve tokens for all users
        vm.prank(user);
        token.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(returnWallet);
        token.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(marketMaker);
        token.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(user);
        weth.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(marketMaker);
        weth.approve(address(proofOfCapital), type(uint256).max);
    }

    // Test 1: InvalidAmount error when amount == 0
    function testSellTokensInvalidAmountZero() public {
        vm.prank(user);
        vm.expectRevert(IProofOfCapital.InvalidAmount.selector);
        proofOfCapital.sellLaunchTokens(0);
    }

    // Test 4: TradingNotAllowedOnlyMarketMakers error when user is not market maker
    function testSellTokensUserWithoutTradingAccessNotMarketMaker() public {
        // Remove market maker status from user
        vm.prank(owner);
        proofOfCapital.setMarketMaker(user, false);

        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS - 1);

        // User (not market maker) tries to sell without trading access
        vm.prank(user);
        vm.expectRevert(IProofOfCapital.TradingNotAllowedOnlyMarketMakers.selector);
        proofOfCapital.sellLaunchTokens(1000e18);
    }

    // Test 5: Trading access during control period
    function testSellTokensUserWithTradingAccessControlPeriod() public {
        // Remove market maker status from user first
        vm.prank(owner);
        proofOfCapital.setMarketMaker(user, false);

        // Move to control period
        uint256 controlDay = proofOfCapital.controlDay();
        vm.warp(controlDay + Constants.THIRTY_DAYS + 1);

        // User tries to sell during control period - gets NoTokensAvailableForBuyback
        // because no buyback tokens are available in initial state
        vm.prank(user);
        vm.expectRevert(IProofOfCapital.NoTokensAvailableForBuyback.selector);
        proofOfCapital.sellLaunchTokens(100e18);
    }

    // Test 6: Trading access when deferred withdrawal is scheduled
    function testSellTokensUserWithTradingAccessDeferredWithdrawalScheduled() public {
        // Remove market maker status from user first
        vm.prank(owner);
        proofOfCapital.setMarketMaker(user, false);

        // Schedule main token deferred withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(owner, 1000e18);

        // User tries to sell - gets NoTokensAvailableForBuyback in initial state
        vm.prank(user);
        vm.expectRevert(IProofOfCapital.NoTokensAvailableForBuyback.selector);
        proofOfCapital.sellLaunchTokens(100e18);
    }

    // Test 7: Token transfer failure scenario
    function testSellTokensTokenTransferFailure() public {
        // Give user insufficient approval for token transfer
        vm.prank(user);
        token.approve(address(proofOfCapital), 100e18);

        // Try to sell more than approved amount
        vm.prank(user);
        vm.expectRevert(); // Should revert due to insufficient allowance
        proofOfCapital.sellLaunchTokens(500e18);
    }

    function testSellTokensHitsConsoleLogBranch() public {
        // Test to hit the console.log branch in _calculateCollateralToPayForTokenAmount
        // This branch executes when localCurrentStep > currentStepEarned && localCurrentStep <= trendChangeStep

        // Create a custom contract with high trendChangeStep and some offset to trigger offset logic
        IProofOfCapital.InitParams memory customParams = getValidParams();
        customParams.trendChangeStep = 50; // Set very high trendChangeStep so currentStep stays within range
        customParams.offsetLaunch = 10000e18; // Add offset to trigger offset-related code with console.log to make buyback easier

        vm.prank(owner);
        ProofOfCapital customContract = new ProofOfCapital(customParams);

        // Transfer tokens from returnWallet to custom contract
        vm.prank(returnWallet);
        SafeERC20.safeTransfer(IERC20(address(token)), address(customContract), 30000e18);

        // Approve tokens for returnWallet
        vm.prank(returnWallet);
        token.approve(address(customContract), type(uint256).max);

        // First, returnWallet sells tokens to increase launchBalance
        vm.prank(returnWallet);
        customContract.sellLaunchTokensReturnWallet(20000e18);

        // Approve WETH for market maker (since buyLaunchTokens uses WETH as collateral)
        vm.prank(marketMaker);
        weth.approve(address(customContract), type(uint256).max);

        // Approve launch tokens for market maker (for sellLaunchTokens)
        vm.prank(marketMaker);
        token.approve(address(customContract), type(uint256).max);

        // Buy enough tokens to exceed offsetLaunch for buyback availability
        vm.prank(marketMaker);
        customContract.buyLaunchTokens(15000e18); // This should advance currentStep and make totalLaunchSold > offsetLaunch

        // Create unaccountedOffset to trigger offset processing
        // First, approve tokens for owner and depositCollateral to create offset balance
        vm.prank(owner);
        token.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositLaunch(2000e18); // This should create unaccountedOffset

        // Call calculateUnaccountedOffsetBalance to trigger offset processing and set offsetStep > 0
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(1000e18); // This should process offset and set offsetStep

        // Now create unaccountedCollateralBalance to trigger _calculateChangeOffsetCollateral
        vm.prank(owner);
        weth.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositCollateral(1000e18); // This creates unaccountedCollateralBalance

        // Call calculateUnaccountedCollateralBalance to trigger _calculateChangeOffsetCollateral
        vm.prank(owner);
        customContract.calculateUnaccountedCollateralBalance(500e18); // This should trigger console.log("trend change branch2")

        // Verify currentStep is in the desired range
        uint256 currentStep = customContract.currentStep();
        uint256 currentStepEarned = customContract.currentStepEarned();
        uint256 trendChangeStep = customContract.trendChangeStep();
        uint256 totalLaunchSold = customContract.totalLaunchSold();
        uint256 offsetLaunch = customContract.offsetLaunch();

        // Debug: print values
        console.log("currentStep:", currentStep);
        console.log("currentStepEarned:", currentStepEarned);
        console.log("trendChangeStep:", trendChangeStep);
        console.log("totalLaunchSold:", totalLaunchSold);
        console.log("offsetLaunch:", offsetLaunch);

        // Ensure we have currentStep > currentStepEarned and currentStep <= trendChangeStep for sell logic
        assertGt(currentStep, currentStepEarned, "currentStep should be greater than currentStepEarned");
        assertLe(currentStep, trendChangeStep, "currentStep should be <= trendChangeStep to hit the branch");
        assertGt(totalLaunchSold, offsetLaunch, "totalLaunchSold should be > offsetLaunch for buyback");

        // Now sell tokens - this should hit the console.log branch in _calculateCollateralToPayForTokenAmount
        uint256 sellAmount = 1000e18;
        uint256 balanceBefore = token.balanceOf(marketMaker);

        vm.prank(marketMaker);
        customContract.sellLaunchTokens(sellAmount);

        // Verify the sale was successful
        assertEq(token.balanceOf(marketMaker), balanceBefore - sellAmount, "Token balance should decrease after sell");
    }

    function testOffsetChangeHitsTrendChangeBranch() public {
        // Test to hit the "trend change branch" in _calculateChangeOffsetCollateral
        // This branch executes when localCurrentStep > trendChangeStep

        // Create a custom contract with low trendChangeStep to trigger "trend change branch"
        IProofOfCapital.InitParams memory customParams = getValidParams();
        customParams.trendChangeStep = 0; // Set low trendChangeStep so localCurrentStep > trendChangeStep
        customParams.offsetLaunch = 10000e18; // Add offset to trigger offset-related code

        vm.prank(owner);
        ProofOfCapital customContract = new ProofOfCapital(customParams);

        // Transfer tokens from returnWallet to custom contract
        vm.prank(returnWallet);
        SafeERC20.safeTransfer(IERC20(address(token)), address(customContract), 40000e18);

        // Transfer more tokens to returnWallet for additional sales
        vm.prank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 30000e18);

        // Approve tokens for returnWallet
        vm.prank(returnWallet);
        token.approve(address(customContract), type(uint256).max);

        // returnWallet sells tokens to add to contract balance
        vm.prank(returnWallet);
        customContract.sellLaunchTokensReturnWallet(5000e18);

        // Sell more tokens to ensure enough launch tokens are available
        vm.prank(returnWallet);
        customContract.sellLaunchTokensReturnWallet(20000e18);

        // Approve WETH for market maker
        vm.prank(marketMaker);
        weth.approve(address(customContract), type(uint256).max);

        // Buy enough tokens to exceed offsetLaunch for buyback availability
        vm.prank(marketMaker);
        customContract.buyLaunchTokens(15000e18); // This should advance currentStep and make totalLaunchSold > offsetLaunch

        // Create unaccountedOffset to trigger offset processing
        vm.prank(owner);
        token.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositLaunch(2000e18); // This should create unaccountedOffset

        // Call calculateUnaccountedOffsetBalance to trigger offset processing and set offsetStep > 0
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(1000e18); // This should process offset and set offsetStep

        // Now create unaccountedCollateralBalance to trigger _calculateChangeOffsetCollateral
        vm.prank(owner);
        weth.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositCollateral(1000e18); // This creates unaccountedCollateralBalance

        // Call calculateUnaccountedOffsetBalance to trigger _calculateOffset
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(500e18); // This should trigger "trend change branch" in _calculateOffset
    }

    function testOffsetCalculationHitsNormalBranch() public {
        // Test to hit the "offset_normal_branch" in _calculateOffset
        // This branch executes when localCurrentStep <= trendChangeStep

        // Create a custom contract with high trendChangeStep
        IProofOfCapital.InitParams memory customParams = getValidParams();
        customParams.trendChangeStep = 10; // High trendChangeStep so localCurrentStep <= trendChangeStep
        customParams.offsetLaunch = 10000e18;

        vm.prank(owner);
        ProofOfCapital customContract = new ProofOfCapital(customParams);

        // Transfer tokens from returnWallet to custom contract
        vm.prank(returnWallet);
        SafeERC20.safeTransfer(IERC20(address(token)), address(customContract), 40000e18);

        // Create unaccountedOffset
        vm.prank(owner);
        token.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositLaunch(2000e18);

        // First call to set offsetStep > 0
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(1000e18);

        // Now create more unaccountedOffset to trigger the condition check
        vm.prank(owner);
        customContract.depositLaunch(1000e18);

        // Second call - this should trigger _calculateOffset with localCurrentStep > 0 and check conditions
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(500e18);
    }

    function testOffsetCalculationHitsTrendChangeBranch() public {
        // Test to hit the "offset_trend_change_branch" in _calculateOffset
        // This branch executes when localCurrentStep > trendChangeStep

        // Create a custom contract with low trendChangeStep
        IProofOfCapital.InitParams memory customParams = getValidParams();
        customParams.trendChangeStep = 0; // Low trendChangeStep so localCurrentStep > trendChangeStep
        customParams.offsetLaunch = 10000e18;

        vm.prank(owner);
        ProofOfCapital customContract = new ProofOfCapital(customParams);

        // Transfer tokens from returnWallet to custom contract
        vm.prank(returnWallet);
        SafeERC20.safeTransfer(IERC20(address(token)), address(customContract), 40000e18);

        // Create unaccountedOffset
        vm.prank(owner);
        token.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositLaunch(2000e18);

        // First call to set offsetStep > 0
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(1000e18);

        // Now create more unaccountedOffset to trigger the condition check
        vm.prank(owner);
        customContract.depositLaunch(1000e18);

        // Second call - this should trigger _calculateOffset with localCurrentStep > 0 and check conditions
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(500e18);
    }

    function testConsoleLogOffsetTrendChangeBranch() public {
        // Dedicated test to verify console.log("offset_trend_change_branch") is triggered
        // This test creates conditions where localCurrentStep > trendChangeStep in _calculateOffset
        // When trendChangeStep = 0, any localCurrentStep > 0 will trigger the trend change branch

        // Create contract with trendChangeStep = 0 to force localCurrentStep > trendChangeStep
        IProofOfCapital.InitParams memory customParams = getValidParams();
        customParams.trendChangeStep = 0; // Any localCurrentStep > 0 will trigger trend change
        customParams.offsetLaunch = 10000e18;

        vm.prank(owner);
        ProofOfCapital customContract = new ProofOfCapital(customParams);

        // Setup tokens
        vm.prank(returnWallet);
        SafeERC20.safeTransfer(IERC20(address(token)), address(customContract), 40000e18);

        // Create offset balance
        vm.prank(owner);
        token.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositLaunch(2000e18);

        // Process offset to set initial offsetStep
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(1000e18);

        // Create additional offset balance
        vm.prank(owner);
        customContract.depositLaunch(1000e18);

        // This call triggers console.log("offset_trend_change_branch") in _calculateOffset
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(500e18);

        // Test verifies that offset trend change branch logic is executed
    }

    function testCollateralCalculationHitsNormalBranch() public {
        // Test to hit the "collateral_normal_branch" in _calculateChangeOffsetCollateral
        // This branch executes when localCurrentStep <= trendChangeStep

        // Create contract with high trendChangeStep
        IProofOfCapital.InitParams memory customParams = getValidParams();
        customParams.trendChangeStep = 10; // High trendChangeStep so localCurrentStep <= trendChangeStep
        customParams.offsetLaunch = 10000e18;

        vm.prank(owner);
        ProofOfCapital customContract = new ProofOfCapital(customParams);

        // Setup tokens
        vm.prank(returnWallet);
        SafeERC20.safeTransfer(IERC20(address(token)), address(customContract), 40000e18);

        // First, process offset to set offsetStep > 0
        vm.prank(owner);
        token.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositLaunch(2000e18);
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(1000e18);

        // Create collateral balance
        vm.prank(owner);
        weth.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositCollateral(2000e18); // This creates unaccountedCollateralBalance

        // Call calculateUnaccountedCollateralBalance - this should trigger _calculateChangeOffsetCollateral with collateral_normal_branch
        vm.prank(owner);
        customContract.calculateUnaccountedCollateralBalance(1000e18);
    }

    function testCollateralCalculationHitsTrendChangeBranch() public {
        // Test to hit the "collateral_trend_change_branch" in _calculateChangeOffsetCollateral
        // This branch executes when localCurrentStep > trendChangeStep

        // Create contract with low trendChangeStep
        IProofOfCapital.InitParams memory customParams = getValidParams();
        customParams.trendChangeStep = 0; // Low trendChangeStep so localCurrentStep > trendChangeStep
        customParams.offsetLaunch = 10000e18;

        vm.prank(owner);
        ProofOfCapital customContract = new ProofOfCapital(customParams);

        // Setup tokens
        vm.prank(returnWallet);
        SafeERC20.safeTransfer(IERC20(address(token)), address(customContract), 40000e18);

        // First, process offset to set offsetStep > 0
        vm.prank(owner);
        token.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositLaunch(2000e18);
        vm.prank(owner);
        customContract.calculateUnaccountedOffsetBalance(1000e18);

        // Create collateral balance
        vm.prank(owner);
        weth.approve(address(customContract), type(uint256).max);
        vm.prank(owner);
        customContract.depositCollateral(2000e18); // This creates unaccountedCollateralBalance

        // Call calculateUnaccountedCollateralBalance - this should trigger _calculateChangeOffsetCollateral with collateral_trend_change_branch
        vm.prank(owner);
        customContract.calculateUnaccountedCollateralBalance(1000e18);
    }

    function testBuyTokensHitsConsoleLogBranches() public {
        // Test to hit both console.log branches in _calculateLaunchToGiveForCollateralAmount
        // First branch: localCurrentStep > trendChangeStep (buy_branch_trend_change)
        // Second branch: localCurrentStep <= trendChangeStep (buy_branch_normal)

        // Create a custom contract with low trendChangeStep
        IProofOfCapital.InitParams memory customParams = getValidParams();
        customParams.trendChangeStep = 3; // Low trendChangeStep to test both branches
        customParams.offsetLaunch = 0; // No offset

        vm.prank(owner);
        ProofOfCapital customContract = new ProofOfCapital(customParams);

        // Transfer tokens from returnWallet to custom contract
        vm.prank(returnWallet);
        SafeERC20.safeTransfer(IERC20(address(token)), address(customContract), 40000e18);

        // Transfer more tokens to returnWallet for additional sales
        vm.prank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 30000e18);

        // Approve tokens for returnWallet
        vm.prank(returnWallet);
        token.approve(address(customContract), type(uint256).max);

        // returnWallet sells tokens to add to contract balance
        vm.prank(returnWallet);
        customContract.sellLaunchTokensReturnWallet(5000e18);

        // Approve WETH for market maker
        vm.prank(marketMaker);
        weth.approve(address(customContract), type(uint256).max);

        // Buy tokens in small amounts first to stay within trendChangeStep
        vm.prank(marketMaker);
        customContract.buyLaunchTokens(2000e18); // This triggers the "normal" branch (localCurrentStep <= trendChangeStep)

        // Check currentStep after first buy
        uint256 currentStepAfterFirst = customContract.currentStep();
        console.log("currentStep after first buy:", currentStepAfterFirst);

        // Verify first buy hit the "normal" branch: currentStep (1) <= trendChangeStep (3)
        assertGt(currentStepAfterFirst, 0, "currentStep should be > 0 after first buy");
        assertLe(currentStepAfterFirst, customContract.trendChangeStep(), "First buy should hit normal branch");

        // Sell more tokens to ensure enough launch tokens are available for second buy
        vm.prank(returnWallet);
        customContract.sellLaunchTokensReturnWallet(20000e18);

        // Buy more tokens to exceed trendChangeStep
        vm.prank(marketMaker);
        customContract.buyLaunchTokens(15000e18); // This triggers the "trend change" branch (localCurrentStep > trendChangeStep)

        // Check currentStep after second buy
        uint256 currentStepAfterSecond = customContract.currentStep();
        console.log("currentStep after second buy:", currentStepAfterSecond);
        console.log("trendChangeStep:", customContract.trendChangeStep());

        // Verify second buy hit the "trend change" branch: currentStep (9) > trendChangeStep (3)
        assertGt(currentStepAfterSecond, customContract.trendChangeStep(), "Second buy should hit trend change branch");
    }
}
