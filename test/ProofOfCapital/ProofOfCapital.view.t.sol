// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVMpragma solidity ^0.8.19;

import "../utils/BaseTest.sol";

contract ProofOfCapitalViewTest is BaseTest {
    
    function testTradingOpportunityWhenNotInTradingPeriod() public {
        // Initially, lock ends in 365 days, so we're not in trading period (>30 days remaining)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        uint256 currentTime = block.timestamp;
        
        // Verify we have more than 30 days remaining
        assertTrue(lockEndTime - currentTime > Constants.THIRTY_DAYS);
        
        // Trading opportunity should be false
        assertFalse(proofOfCapital.tradingOpportunity());
    }
    
    function testTradingOpportunityWhenInTradingPeriod() public {
        // Move time to within 30 days of lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.THIRTY_DAYS + 1); // 29 days remaining
        
        // Trading opportunity should be true
        assertTrue(proofOfCapital.tradingOpportunity());
    }
    
    function testTradingOpportunityAtExactBoundary() public {
        // Move time to exactly 30 days before lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.THIRTY_DAYS);
        
        // At exactly 30 days, condition is: remaining < 30 days
        // 30 days < 30 days = false, so trading opportunity should be false
        assertFalse(proofOfCapital.tradingOpportunity());
    }
    
    function testTradingOpportunityJustInsideBoundary() public {
        // Move time to just inside 30 days (29 days remaining)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.THIRTY_DAYS + 1);
        
        // 29 days < 30 days = true, so trading opportunity should be true
        assertTrue(proofOfCapital.tradingOpportunity());
    }
    
    function testTradingOpportunityAfterLockExtension() public {
        // Move to trading period
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.THIRTY_DAYS + 1);
        
        // Verify we're in trading period
        assertTrue(proofOfCapital.tradingOpportunity());
        
        // Extend lock by 3 months
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.THREE_MONTHS);
        
        // After extension, we should no longer be in trading period
        assertFalse(proofOfCapital.tradingOpportunity());
    }
    
    function testJettonAvailableInitialState() public {
        // Initially: totalJettonsSold = 10000e18 (from offset), jettonsEarned = 0
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        uint256 jettonsEarned = proofOfCapital.jettonsEarned();
        
        // Verify initial state
        assertEq(totalSold, 10000e18); // offsetJettons
        assertEq(jettonsEarned, 0);
        
        // jettonAvailable should be totalJettonsSold - jettonsEarned
        uint256 expectedAvailable = totalSold - jettonsEarned;
        assertEq(proofOfCapital.jettonAvailable(), expectedAvailable);
        assertEq(proofOfCapital.jettonAvailable(), 10000e18);
    }
    
    function testJettonAvailableWhenEarnedEqualsTotal() public {
        // This tests edge case where jettonsEarned equals totalJettonsSold
        // In initial state: totalJettonsSold = 10000e18, jettonsEarned = 0
        
        // We need to create scenario where jettonsEarned increases
        // This happens when return wallet sells tokens back to contract
        
        // Give tokens to return wallet
        vm.startPrank(owner);
        token.transfer(returnWallet, 10000e18);
        vm.stopPrank();
        
        // Return wallet sells tokens back (this increases jettonsEarned)
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.sellTokens(10000e18);
        vm.stopPrank();
        
        // Check if jettonsEarned increased
        uint256 jettonsEarned = proofOfCapital.jettonsEarned();
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        
        // jettonAvailable should be totalSold - jettonsEarned
        uint256 expectedAvailable = totalSold - jettonsEarned;
        assertEq(proofOfCapital.jettonAvailable(), expectedAvailable);
        
        // If jettonsEarned equals totalSold, available should be 0
        if (jettonsEarned == totalSold) {
            assertEq(proofOfCapital.jettonAvailable(), 0);
        }
    }
    
    function testJettonAvailableStateConsistency() public {
        // Test that jettonAvailable always equals totalJettonsSold - jettonsEarned
        
        // Record initial state
        uint256 initialTotalSold = proofOfCapital.totalJettonsSold();
        uint256 initialJettonsEarned = proofOfCapital.jettonsEarned();
        uint256 initialAvailable = proofOfCapital.jettonAvailable();
        
        // Verify initial consistency
        assertEq(initialAvailable, initialTotalSold - initialJettonsEarned);
        
        // After any state changes, consistency should be maintained
        // This is a property that should always hold
        assertTrue(proofOfCapital.jettonAvailable() == proofOfCapital.totalJettonsSold() - proofOfCapital.jettonsEarned());
    }
    
    function testViewFunctionsIntegration() public {
        // Test that view functions work correctly together
        
        // Initial state
        uint256 remaining = proofOfCapital.remainingSeconds();
        bool tradingOpp = proofOfCapital.tradingOpportunity();
        uint256 available = proofOfCapital.jettonAvailable();
        
        // Verify logical consistency
        // If remaining > 30 days, trading opportunity should be false
        if (remaining > Constants.THIRTY_DAYS) {
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
        assertEq(proofOfCapital.jettonAvailable(), available);
    }
    
    function testRemainingSecondsAfterLockEnd() public {
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1000);
        
        // Should return 0 when past lock end
        assertEq(proofOfCapital.remainingSeconds(), 0);
    }
    
    function testRemainingSecondsBeforeLockEnd() public {
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
        assertTrue(proofOfCapital.tradingOpportunity()); // 0 < 30 days is true
        
        // Test jettonAvailable consistency
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        uint256 jettonsEarned = proofOfCapital.jettonsEarned();
        uint256 expectedAvailable = totalSold - jettonsEarned;
        assertEq(proofOfCapital.jettonAvailable(), expectedAvailable);
    }
} 