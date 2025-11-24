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
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Constants} from "../../src/utils/Constant.sol";

contract ProofOfCapitalViewTest is BaseTest {
    using SafeERC20 for IERC20;

    function testTradingOpportunityWhenNotInTradingPeriod() public view {
        // Initially, lock ends in 365 days, so we're not in trading period (>60 days remaining)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        uint256 currentTime = block.timestamp;

        // Verify we have more than 60 days remaining
        assertTrue(lockEndTime - currentTime > Constants.SIXTY_DAYS);

        // Trading opportunity should be false
        assertFalse(proofOfCapital.tradingOpportunity());
    }

    function testTradingOpportunityWhenInTradingPeriod() public {
        // Move time to within 60 days of lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1); // 59 days remaining

        // Trading opportunity should be true
        assertTrue(proofOfCapital.tradingOpportunity());
    }

    function testTradingOpportunityAtExactBoundary() public {
        // Move time to exactly 60 days before lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS);

        // At exactly 60 days, condition is: remaining < 60 days
        // 60 days < 60 days = false, so trading opportunity should be false
        assertFalse(proofOfCapital.tradingOpportunity());
    }

    function testTradingOpportunityJustInsideBoundary() public {
        // Move time to just inside 60 days (59 days remaining)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1);

        // 59 days < 60 days = true, so trading opportunity should be true
        assertTrue(proofOfCapital.tradingOpportunity());
    }

    function testTradingOpportunityAfterLockExtension() public {
        // Move to trading period
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1);

        // Verify we're in trading period
        assertTrue(proofOfCapital.tradingOpportunity());

        // Extend lock to current lockEndTime + 3 months
        vm.prank(owner);
        proofOfCapital.extendLock(lockEndTime + Constants.THREE_MONTHS);

        // After extension, we should no longer be in trading period
        assertFalse(proofOfCapital.tradingOpportunity());
    }

    function testTokenAvailableInitialState() public view {
        // Initially: offsetLaunch go to unaccountedOffset, not totalLaunchSold
        // So totalLaunchSold = 0, tokensEarned = 0
        uint256 totalSold = proofOfCapital.totalLaunchSold();
        uint256 tokensEarned = proofOfCapital.tokensEarned();

        // Verify initial state
        assertEq(totalSold, 0); // offsetLaunch are in unaccountedOffset, not totalLaunchSold
        assertEq(tokensEarned, 0);

        // tokenAvailable should be totalLaunchSold - tokensEarned
        uint256 expectedAvailable = totalSold - tokensEarned;
        assertEq(proofOfCapital.tokenAvailable(), expectedAvailable);
        assertEq(proofOfCapital.tokenAvailable(), 0); // No tokens available until offset is processed
    }

    function testTokenAvailableWhenEarnedEqualsTotal() public {
        // This tests edge case where tokensEarned equals totalLaunchSold
        // In initial state: totalLaunchSold = 10000e18, tokensEarned = 0

        // We need to create scenario where tokensEarned increases
        // This happens when return wallet sells tokens back to contract

        // Give tokens to return wallet
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 10000e18);
        vm.stopPrank();

        // Return wallet sells tokens back (this increases tokensEarned)
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.sellTokens(10000e18);
        vm.stopPrank();

        // Check if tokensEarned increased
        uint256 tokensEarned = proofOfCapital.tokensEarned();
        uint256 totalSold = proofOfCapital.totalLaunchSold();

        // tokenAvailable should be totalSold - tokensEarned
        uint256 expectedAvailable = totalSold - tokensEarned;
        assertEq(proofOfCapital.tokenAvailable(), expectedAvailable);

        // If tokensEarned equals totalSold, available should be 0
        if (tokensEarned == totalSold) {
            assertEq(proofOfCapital.tokenAvailable(), 0);
        }
    }

    function testTokenAvailableStateConsistency() public view {
        // Test that tokenAvailable always equals totalLaunchSold - tokensEarned

        // Record initial state
        uint256 initialTotalSold = proofOfCapital.totalLaunchSold();
        uint256 initialTokensEarned = proofOfCapital.tokensEarned();
        uint256 initialAvailable = proofOfCapital.tokenAvailable();

        // Verify initial consistency
        assertEq(initialAvailable, initialTotalSold - initialTokensEarned);

        // After any state changes, consistency should be maintained
        // This is a property that should always hold
        assertTrue(proofOfCapital.tokenAvailable() == proofOfCapital.totalLaunchSold() - proofOfCapital.tokensEarned());
    }

    function testViewFunctionsIntegration() public {
        // Test that view functions work correctly together

        // Initial state
        uint256 remaining = proofOfCapital.remainingSeconds();
        bool tradingOpp = proofOfCapital.tradingOpportunity();
        uint256 available = proofOfCapital.tokenAvailable();

        // Verify logical consistency
        // If remaining > 60 days, trading opportunity should be false
        if (remaining > Constants.SIXTY_DAYS) {
            assertFalse(tradingOpp);
        } else {
            assertTrue(tradingOpp);
        }

        // Available should always be >= 0
        assertTrue(available >= 0);

        // Move time forward but not past lock end
        vm.warp(block.timestamp + 10 days);

        // Remaining should have decreased
        uint256 newRemaining = proofOfCapital.remainingSeconds();
        assertTrue(newRemaining < remaining);

        // Available should remain the same (no trading activity)
        assertEq(proofOfCapital.tokenAvailable(), available);
    }

    function testRemainingSecondsAfterLockEnd() public {
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1000);

        // Should return 0 when past lock end
        assertEq(proofOfCapital.remainingSeconds(), 0);
    }

    function testRemainingSecondsBeforeLockEnd() public view {
        // Should return actual remaining time
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        uint256 currentTime = block.timestamp;
        uint256 expected = lockEndTime - currentTime;

        assertEq(proofOfCapital.remainingSeconds(), expected);
    }

    // Test edge cases for view functions
    function testViewFunctionsEdgeCases() public {
        // Test when lockEndTime is exactly at current time
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime);

        assertEq(proofOfCapital.remainingSeconds(), 0);
        assertTrue(proofOfCapital.tradingOpportunity()); // 0 < 60 days is true

        // Test tokenAvailable consistency
        uint256 totalSold = proofOfCapital.totalLaunchSold();
        uint256 tokensEarned = proofOfCapital.tokensEarned();
        uint256 expectedAvailable = totalSold - tokensEarned;
        assertEq(proofOfCapital.tokenAvailable(), expectedAvailable);
    }
}
