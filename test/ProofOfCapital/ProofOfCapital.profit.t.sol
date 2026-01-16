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

import {BaseTestWithoutOffset} from "../utils/BaseTestWithoutOffset.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProofOfCapital} from "../../src/ProofOfCapital.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Constants} from "../../src/utils/Constant.sol";
import {IProofOfCapital} from "../../src/interfaces/IProofOfCapital.sol";

contract ProofOfCapitalProfitTest is BaseTestWithoutOffset {
    using SafeERC20 for IERC20;
    address public user = address(0x5);

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Setup tokens for users and add market maker permissions
        SafeERC20.safeTransfer(IERC20(address(token)), address(proofOfCapital), 500000e18);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 50000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), owner, 200000e18); // Give owner WETH for deposits
        SafeERC20.safeTransfer(IERC20(address(weth)), user, 100000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), marketMaker, 100000e18);

        // Set DAO first (required for setMarketMaker)
        address dao = address(0xDA0);
        proofOfCapital.setDao(dao);

        // Enable market maker for user to allow trading
        vm.stopPrank();
        vm.prank(dao);
        proofOfCapital.setMarketMaker(user, true);
        vm.startPrank(owner);

        vm.stopPrank();

        // Approve tokens
        vm.prank(user);
        weth.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(marketMaker);
        weth.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(returnWallet);
        token.approve(address(proofOfCapital), type(uint256).max);
    }

    function testClaimProfitOnRequestWhenProfitModeNotActive() public {
        // Disable profit on request mode
        vm.prank(owner);
        proofOfCapital.switchProfitMode(false);

        // Try to get profit when mode is not active (without any trading)
        // Function doesn't check profitInTime, it only checks if balance > 0
        // So it will revert with NoProfitAvailable instead
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.claimProfitOnRequest();
    }

    function testClaimProfitOnRequestWithNoProfitAvailable() public {
        // Try to get profit when there's no profit
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.claimProfitOnRequest();

        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.claimProfitOnRequest();
    }

    function testClaimProfitOnRequestUnauthorized() public {
        // Unauthorized user tries to get profit (without any trading)
        vm.prank(user);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.claimProfitOnRequest();
    }

    function testClaimProfitOnRequestOwnerSimple() public {
        // Enable profit on request mode (profitInTime = false for accumulation)
        vm.prank(owner);
        proofOfCapital.switchProfitMode(false);
        assertFalse(proofOfCapital.profitInTime());

        // Manually set owner profit balance for testing
        // We'll use the depositCollateral function to simulate profit accumulation
        vm.prank(owner);
        SafeERC20.safeTransfer(IERC20(address(weth)), address(proofOfCapital), 1000e18);

        // Manually set profit balance using internal state
        // Since we can't directly modify internal balance, we'll test error case

        // Owner requests profit when no profit available
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.claimProfitOnRequest();
    }

    function testClaimProfitOnRequestRoyaltySimple() public {
        // Royalty requests profit when no profit available
        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.claimProfitOnRequest();
    }

    function testClaimProfitOnRequestOwnerSuccess() public {
        // Use separate base test without offset
        BaseTestWithoutOffset baseTest = new BaseTestWithoutOffset();
        baseTest.setUp();

        ProofOfCapital testContract = baseTest.proofOfCapital();
        MockERC20 testToken = baseTest.token();
        MockERC20 testWeth = baseTest.weth();
        address testOwner = baseTest.owner();
        address testMarketMaker = baseTest.marketMaker();

        vm.startPrank(testOwner);

        // Transfer launch tokens from owner to contract and depositCollateral them
        uint256 tokensToDeposit = 100000e18; // Use smaller amount
        SafeERC20.safeTransfer(IERC20(address(testToken)), address(testContract), tokensToDeposit);
        testToken.approve(address(testContract), tokensToDeposit);
        testContract.depositLaunch(tokensToDeposit); // This increases launchBalance

        // Create contractCollateralBalance by depositing WETH
        uint256 depositAmount = 20000e18; // Use smaller amount
        testWeth.approve(address(testContract), depositAmount);
        testContract.depositCollateral(depositAmount);

        // Transfer WETH to market maker for purchases
        SafeERC20.safeTransfer(IERC20(address(testWeth)), testMarketMaker, 100000e18);
        vm.stopPrank();

        // Approve WETH for market maker
        vm.prank(testMarketMaker);
        testWeth.approve(address(testContract), type(uint256).max);

        // Enable profit accumulation mode (profitInTime = false)
        vm.prank(testOwner);
        testContract.switchProfitMode(false);
        assertFalse(testContract.profitInTime());

        // Record initial balances
        uint256 initialOwnerWethBalance = testWeth.balanceOf(testOwner);
        uint256 initialOwnerCollateralBalance = testContract.ownerCollateralBalance();
        assertEq(initialOwnerCollateralBalance, 0, "Initial owner collateral balance should be 0");

        // Market maker buys tokens to generate profit (this calls _handleLaunchTokenPurchaseCommon)
        // Use very small amount to avoid overflow in calculations
        // The issue is that remainderOfStepLocal can become negative in _calculateLaunchToGiveForCollateralAmount
        uint256 purchaseAmount = 3e18;
        vm.prank(testMarketMaker);
        testContract.buyLaunchTokens(purchaseAmount);

        // Verify profit was accumulated
        uint256 ownerCollateralBalanceAfterPurchase = testContract.ownerCollateralBalance();
        assertGt(
            ownerCollateralBalanceAfterPurchase, 0, "Owner collateral balance should be greater than 0 after purchase"
        );

        // Owner requests profit withdrawal
        vm.expectEmit(false, false, false, true);
        emit IProofOfCapital.ProfitWithdrawn(testOwner, ownerCollateralBalanceAfterPurchase);

        vm.prank(testOwner);
        testContract.claimProfitOnRequest();

        // Verify profit was withdrawn
        assertEq(testContract.ownerCollateralBalance(), 0, "Owner collateral balance should be 0 after withdrawal");
        assertEq(
            testWeth.balanceOf(testOwner),
            initialOwnerWethBalance + ownerCollateralBalanceAfterPurchase,
            "Owner should receive the profit amount"
        );
    }

    function testClaimProfitOnRequestRoyaltySuccess() public {
        // Use separate base test without offset
        BaseTestWithoutOffset baseTest = new BaseTestWithoutOffset();
        baseTest.setUp();

        ProofOfCapital testContract = baseTest.proofOfCapital();
        MockERC20 testToken = baseTest.token();
        MockERC20 testWeth = baseTest.weth();
        address testOwner = baseTest.owner();
        address testMarketMaker = baseTest.marketMaker();
        address testRoyalty = baseTest.royalty();

        vm.startPrank(testOwner);

        // Transfer launch tokens from owner to contract and depositCollateral them
        uint256 tokensToDeposit = 100000e18; // Use smaller amount
        SafeERC20.safeTransfer(IERC20(address(testToken)), address(testContract), tokensToDeposit);
        testToken.approve(address(testContract), tokensToDeposit);
        testContract.depositLaunch(tokensToDeposit); // This increases launchBalance

        // Create contractCollateralBalance by depositing WETH
        uint256 depositAmount = 20000e18; // Use smaller amount
        testWeth.approve(address(testContract), depositAmount);
        testContract.depositCollateral(depositAmount);

        // Transfer WETH to market maker for purchases
        SafeERC20.safeTransfer(IERC20(address(testWeth)), testMarketMaker, 100000e18);
        vm.stopPrank();

        // Approve WETH for market maker
        vm.prank(testMarketMaker);
        testWeth.approve(address(testContract), type(uint256).max);

        // Enable profit accumulation mode (profitInTime = false)
        vm.prank(testOwner);
        testContract.switchProfitMode(false);
        assertFalse(testContract.profitInTime());

        // Record initial balances
        uint256 initialRoyaltyWethBalance = testWeth.balanceOf(testRoyalty);
        uint256 initialRoyaltyCollateralBalance = testContract.royaltyCollateralBalance();
        assertEq(initialRoyaltyCollateralBalance, 0, "Initial royalty collateral balance should be 0");

        // Market maker buys tokens to generate profit (this calls _handleLaunchTokenPurchaseCommon)
        // Use very small amount to avoid overflow in calculations
        // The issue is that remainderOfStepLocal can become negative in _calculateLaunchToGiveForCollateralAmount
        uint256 purchaseAmount = 1e18;
        vm.prank(testMarketMaker);
        testContract.buyLaunchTokens(purchaseAmount);

        // Verify profit was accumulated
        uint256 royaltyCollateralBalanceAfterPurchase = testContract.royaltyCollateralBalance();
        assertGt(
            royaltyCollateralBalanceAfterPurchase,
            0,
            "Royalty collateral balance should be greater than 0 after purchase"
        );

        // Royalty wallet requests profit withdrawal
        vm.expectEmit(false, false, false, true);
        emit IProofOfCapital.ProfitWithdrawn(testRoyalty, royaltyCollateralBalanceAfterPurchase);

        vm.prank(testRoyalty);
        testContract.claimProfitOnRequest();

        // Verify profit was withdrawn
        assertEq(testContract.royaltyCollateralBalance(), 0, "Royalty collateral balance should be 0 after withdrawal");
        assertEq(
            testWeth.balanceOf(testRoyalty),
            initialRoyaltyWethBalance + royaltyCollateralBalanceAfterPurchase,
            "Royalty wallet should receive the profit amount"
        );
    }

    // Tests for changeProfitPercentage function
    function testChangeProfitPercentageOwnerIncrease() public {
        // Owner can only increase royalty percentage (from 500 to higher)
        uint256 newPercentage = 600; // 60%
        uint256 initialRoyaltyPercent = proofOfCapital.royaltyProfitPercent(); // Should be 500
        uint256 initialCreatorPercent = Constants.PERCENTAGE_DIVISOR - initialRoyaltyPercent; // Should be 500

        // Verify initial state
        assertEq(initialRoyaltyPercent, 500);
        assertEq(initialCreatorPercent, 500);

        // Owner increases royalty percentage
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(newPercentage);

        // Verify changes
        assertEq(proofOfCapital.royaltyProfitPercent(), newPercentage);
        assertEq(
            Constants.PERCENTAGE_DIVISOR - proofOfCapital.royaltyProfitPercent(),
            Constants.PERCENTAGE_DIVISOR - newPercentage
        );
    }

    function testChangeProfitPercentageRoyaltyDecrease() public {
        // Royalty wallet can only decrease royalty percentage (from 500 to lower)
        uint256 newPercentage = 400; // 40%
        uint256 initialRoyaltyPercent = proofOfCapital.royaltyProfitPercent(); // Should be 500

        // Verify initial state
        assertEq(initialRoyaltyPercent, 500);

        // Royalty wallet decreases royalty percentage
        vm.prank(royalty);
        proofOfCapital.changeProfitPercentage(newPercentage);

        // Verify changes
        assertEq(proofOfCapital.royaltyProfitPercent(), newPercentage);
        assertEq(
            Constants.PERCENTAGE_DIVISOR - proofOfCapital.royaltyProfitPercent(),
            Constants.PERCENTAGE_DIVISOR - newPercentage
        );
    }

    function testChangeProfitPercentageAccessDenied() public {
        uint256 newPercentage = 600;

        // Unauthorized users try to change profit percentage
        vm.prank(returnWallet);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);

        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);

        vm.prank(address(0x999));
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);

        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyProfitPercent(), 500);
    }

    function testChangeProfitPercentageInvalidPercentageZero() public {
        // Try to set percentage to 0
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(0);

        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(0);
    }

    function testChangeProfitPercentageInvalidPercentageExceedsMax() public {
        // Try to set percentage above PERCENTAGE_DIVISOR (1000)
        uint256 invalidPercentage = Constants.PERCENTAGE_DIVISOR + 1;

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(invalidPercentage);

        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(invalidPercentage);
    }

    function testChangeProfitPercentageOwnerCannotDecrease() public {
        // Owner tries to decrease royalty percentage (from 500 to lower)
        uint256 lowerPercentage = 400; // 40%

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.CannotDecreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(lowerPercentage);

        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyProfitPercent(), 500);
    }

    function testChangeProfitPercentageRoyaltyCannotIncrease() public {
        // Royalty wallet tries to increase royalty percentage (from 500 to higher)
        uint256 higherPercentage = 600; // 60%

        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.CannotIncreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(higherPercentage);

        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyProfitPercent(), 500);
    }

    function testChangeProfitPercentageEvent() public {
        uint256 newPercentage = 600;

        // Test event emission by owner
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IProofOfCapital.ProfitPercentageChanged(newPercentage);
        proofOfCapital.changeProfitPercentage(newPercentage);

        // Reset and test event emission by royalty
        uint256 lowerPercentage = 550;
        vm.prank(royalty);
        vm.expectEmit(false, false, false, true);
        emit IProofOfCapital.ProfitPercentageChanged(lowerPercentage);
        proofOfCapital.changeProfitPercentage(lowerPercentage);
    }

    function testChangeProfitPercentageBoundaryValues() public {
        // Test with boundary value 1 (minimum valid)
        vm.prank(royalty);
        proofOfCapital.changeProfitPercentage(1);
        assertEq(proofOfCapital.royaltyProfitPercent(), 1);
        assertEq(Constants.PERCENTAGE_DIVISOR - proofOfCapital.royaltyProfitPercent(), Constants.PERCENTAGE_DIVISOR - 1);

        // Test with boundary value PERCENTAGE_DIVISOR (maximum valid)
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(Constants.PERCENTAGE_DIVISOR);
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.PERCENTAGE_DIVISOR);
        assertEq(Constants.PERCENTAGE_DIVISOR - proofOfCapital.royaltyProfitPercent(), 0);
    }

    function testChangeProfitPercentageOwnerEqualToCurrent() public {
        // Owner tries to set the same percentage (not allowed - must be greater)
        uint256 currentPercentage = proofOfCapital.royaltyProfitPercent(); // 500

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.CannotDecreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(currentPercentage);
    }

    function testChangeProfitPercentageRoyaltyEqualToCurrent() public {
        // Royalty tries to set the same percentage (not allowed - must be less)
        uint256 currentPercentage = proofOfCapital.royaltyProfitPercent(); // 500

        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.CannotIncreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(currentPercentage);
    }

    function testChangeProfitPercentageSequentialChanges() public {
        // Test sequential changes: owner increases, then royalty decreases

        // Step 1: Owner increases from 500 to 700
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(700);
        assertEq(proofOfCapital.royaltyProfitPercent(), 700);
        assertEq(Constants.PERCENTAGE_DIVISOR - proofOfCapital.royaltyProfitPercent(), 300);

        // Step 2: Royalty decreases from 700 to 600
        vm.prank(royalty);
        proofOfCapital.changeProfitPercentage(600);
        assertEq(proofOfCapital.royaltyProfitPercent(), 600);
        assertEq(Constants.PERCENTAGE_DIVISOR - proofOfCapital.royaltyProfitPercent(), 400);

        // Step 3: Owner increases from 600 to 800
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(800);
        assertEq(proofOfCapital.royaltyProfitPercent(), 800);
        assertEq(Constants.PERCENTAGE_DIVISOR - proofOfCapital.royaltyProfitPercent(), 200);
    }

    function testChangeProfitPercentageStateConsistency() public {
        // Test that both percentages always sum to PERCENTAGE_DIVISOR
        uint256[] memory testPercentages = new uint256[](5);
        testPercentages[0] = 600;
        testPercentages[1] = 750;
        testPercentages[2] = 900;
        testPercentages[3] = 999;
        testPercentages[4] = 1000;

        for (uint256 i = 0; i < testPercentages.length; i++) {
            vm.prank(owner);
            proofOfCapital.changeProfitPercentage(testPercentages[i]);

            uint256 royaltyPercent = proofOfCapital.royaltyProfitPercent();
            uint256 creatorPercent = Constants.PERCENTAGE_DIVISOR - royaltyPercent;

            // Verify they sum to PERCENTAGE_DIVISOR
            assertEq(royaltyPercent + creatorPercent, Constants.PERCENTAGE_DIVISOR);
            assertEq(royaltyPercent, testPercentages[i]);
            assertEq(creatorPercent, Constants.PERCENTAGE_DIVISOR - testPercentages[i]);
        }
    }

    function testChangeProfitPercentageAccessAfterRoyaltyWalletChange() public {
        // Test access control after changing royalty wallet
        address newRoyaltyWallet = address(0x999);
        uint256 newPercentage = 400;

        // Change royalty wallet
        vm.prank(royalty);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);

        // Old royalty wallet should not have access anymore
        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);

        // New royalty wallet should have access
        vm.prank(newRoyaltyWallet);
        proofOfCapital.changeProfitPercentage(newPercentage);
        assertEq(proofOfCapital.royaltyProfitPercent(), newPercentage);
    }

    // Test for TradingNotAllowedOnlyMarketMakers require in _handleLaunchTokenPurchaseCommon
    function testBuyTokensTradingNotAllowedOnlyMarketMakers() public {
        // Create a regular user (not market maker, not owner)
        address regularUser = address(0x777);

        // Give WETH tokens to regular user
        vm.prank(owner);
        SafeERC20.safeTransfer(IERC20(address(weth)), regularUser, 10000e18);

        vm.prank(regularUser);
        weth.approve(address(proofOfCapital), type(uint256).max);

        // Verify user is not a market maker
        assertFalse(proofOfCapital.marketMakerAddresses(regularUser), "Regular user should not be market maker");

        // Create collateral balance first to enable token purchases
        vm.prank(returnWallet);
        proofOfCapital.sellLaunchTokensReturnWallet(15000e18);

        // Move time to be more than 60 days before lock end to remove time-based trading access
        uint256 mmLockEndTime = proofOfCapital.lockEndTime();
        vm.warp(mmLockEndTime - Constants.SIXTY_DAYS - 1);

        // Verify we're not in trading access period
        assertFalse(_checkTradingAccessHelper(), "Should not have trading access");

        // Regular user (non-market maker) tries to buy tokens without trading access
        vm.prank(regularUser);
        vm.expectRevert(IProofOfCapital.TradingNotAllowedOnlyMarketMakers.selector);
        proofOfCapital.buyLaunchTokens(1000e18);
    }

    function testBuyTokensWithTradingAccess() public {
        // Test that regular users can trade when they have trading access

        // Create a regular user (not market maker)
        address regularUser = address(0x777);

        // Give WETH tokens to regular user
        vm.prank(owner);
        SafeERC20.safeTransfer(IERC20(address(weth)), regularUser, 10000e18);

        vm.prank(regularUser);
        weth.approve(address(proofOfCapital), type(uint256).max);

        // Verify user is not a market maker
        assertFalse(proofOfCapital.marketMakerAddresses(regularUser), "Regular user should not be market maker");

        // Create collateral balance first to enable token purchases
        vm.prank(returnWallet);
        proofOfCapital.sellLaunchTokensReturnWallet(15000e18);

        // Activate trading access by scheduling deferred withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(owner, 1000e18);

        // Verify we now have trading access
        assertTrue(_checkTradingAccessHelper(), "Should have trading access");

        // Regular user should now be able to buy tokens
        uint256 initialTokenBalance = token.balanceOf(regularUser);

        vm.prank(regularUser);
        proofOfCapital.buyLaunchTokens(1000e18); // Should not revert

        // Verify tokens were purchased
        assertTrue(token.balanceOf(regularUser) > initialTokenBalance, "Regular user should receive tokens");
    }

    // Helper function to check trading access (mimics _checkTradingAccess logic)
    function _checkTradingAccessHelper() internal view returns (bool) {
        // Check control day
        bool controlDayAccess =
            (block.timestamp > Constants.THIRTY_DAYS + proofOfCapital.controlDay()
                && block.timestamp
                    < Constants.THIRTY_DAYS + proofOfCapital.controlDay() + proofOfCapital.controlPeriod());

        // Check deferred withdrawals
        bool deferredWithdrawalAccess = (proofOfCapital.launchDeferredWithdrawalDate() > 0)
            || (proofOfCapital.collateralTokenDeferredWithdrawalDate() > 0);

        // Check if less than 60 days remaining until lock end (more freedom for trading)
        bool timeAccess = (proofOfCapital.lockEndTime() < block.timestamp + Constants.SIXTY_DAYS);

        return controlDayAccess || deferredWithdrawalAccess || timeAccess;
    }
}
