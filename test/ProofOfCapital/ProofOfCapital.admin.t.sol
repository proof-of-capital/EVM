// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVMpragma solidity ^0.8.19;

import "../utils/BaseTest.sol";

contract ProofOfCapitalAdminTest is BaseTest {
    
    // Tests for extendLock function
    function testExtendLockWithHalfYear() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();
        
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.HALF_YEAR);
        
        assertEq(proofOfCapital.lockEndTime(), initialLockEndTime + Constants.HALF_YEAR);
    }
    
    function testExtendLockWithThreeMonths() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();
        
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.THREE_MONTHS);
        
        assertEq(proofOfCapital.lockEndTime(), initialLockEndTime + Constants.THREE_MONTHS);
    }
    
    function testExtendLockWithTenMinutes() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();
        
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.TEN_MINUTES);
        
        assertEq(proofOfCapital.lockEndTime(), initialLockEndTime + Constants.TEN_MINUTES);
    }
    
    function testExtendLockUnauthorized() public {
        // Non-owner tries to extend lock
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.extendLock(Constants.HALF_YEAR);
    }
    
    function testExtendLockExceedsTwoYears() public {
        // We start with 365 days, limit is 730 days (TWO_YEARS)
        // HALF_YEAR = 182.5 days approximately
        // So 365 + 182.5 = 547.5 days (still within 730 limit)
        // But 365 + 182.5 + 182.5 = 730 days (at the limit)
        
        // First extend by HALF_YEAR - should work
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.HALF_YEAR);
        
        // Second extend by THREE_MONTHS to get closer to limit - should work
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.THREE_MONTHS);
        
        // Now try to extend by HALF_YEAR - this should exceed the limit
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockCannotExceedTwoYears.selector);
        proofOfCapital.extendLock(Constants.HALF_YEAR);
    }
    
    function testExtendLockWithInvalidTimePeriod() public {
        // Try to extend with invalid time period (not one of the allowed constants)
        uint256 invalidTime = 100 days; // Not a valid period
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidTimePeriod.selector);
        proofOfCapital.extendLock(invalidTime);
    }
    
    function testExtendLockEvent() public {
        uint256 extensionTime = Constants.THREE_MONTHS;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        // Expecting LockExtended event with extensionTime parameter
        emit IProofOfCapital.LockExtended(extensionTime);
        proofOfCapital.extendLock(extensionTime);
    }
    
    function testExtendLockMultipleTimes() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();
        
        // First extension
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.THREE_MONTHS);
        
        uint256 afterFirstExtension = proofOfCapital.lockEndTime();
        assertEq(afterFirstExtension, initialLockEndTime + Constants.THREE_MONTHS);
        
        // Second extension
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.TEN_MINUTES);
        
        assertEq(proofOfCapital.lockEndTime(), afterFirstExtension + Constants.TEN_MINUTES);
    }
    
    function testExtendLockAtBoundaryOfTwoYears() public {
        // We start with 365 days lock, limit is 730 days
        // We can extend by exactly 365 days total
        
        // Extend by THREE_MONTHS multiple times to get close to the limit
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.THREE_MONTHS); // +90 days
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.THREE_MONTHS); // +90 days
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.THREE_MONTHS); // +90 days
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.THREE_MONTHS); // +90 days
        // Now we have 365 + 360 = 725 days, close to 730 limit
        
        // TEN_MINUTES should still work (it's very small)
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.TEN_MINUTES);
        
        // But HALF_YEAR should fail now
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockCannotExceedTwoYears.selector);
        proofOfCapital.extendLock(Constants.HALF_YEAR);
    }
    
    // Tests for blockDeferredWithdrawal function
    function testBlockDeferredWithdrawalFromTrueToFalse() public {
        // Initially canWithdrawal should be true (default)
        assertTrue(proofOfCapital.canWithdrawal());
        
        // Block deferred withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        
        // Should now be false
        assertFalse(proofOfCapital.canWithdrawal());
    }
    
    function testBlockDeferredWithdrawalFromFalseToTrueWhenTimeAllows() public {
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Now try to unblock when we have enough time (more than 30 days before lock end)
        // Lock is set to 365 days from start, so we should have enough time
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        
        // Should now be true again
        assertTrue(proofOfCapital.canWithdrawal());
    }
    
    function testBlockDeferredWithdrawalFailsWhenTooCloseToLockEnd() public {
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Move time forward to be within 30 days of lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.THIRTY_DAYS + 1 days); // 29 days before lock end
        
        // Try to unblock - should fail
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.CannotActivateWithdrawalTooCloseToLockEnd.selector);
        proofOfCapital.blockDeferredWithdrawal();
        
        // Should still be false
        assertFalse(proofOfCapital.canWithdrawal());
    }
    
    function testBlockDeferredWithdrawalAtExactBoundary() public {
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Move time forward to be exactly 30 days before lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.THIRTY_DAYS);
        
        // Try to unblock - should fail (condition is >, not >=)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.CannotActivateWithdrawalTooCloseToLockEnd.selector);
        proofOfCapital.blockDeferredWithdrawal();
    }
    
    function testBlockDeferredWithdrawalJustOverBoundary() public {
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Move time forward to be just over 30 days before lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.THIRTY_DAYS - 1); // 30 days + 1 second
        
        // Try to unblock - should work
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        
        // Should now be true
        assertTrue(proofOfCapital.canWithdrawal());
    }
    
    function testBlockDeferredWithdrawalUnauthorized() public {
        // Non-owner tries to block/unblock withdrawal
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.blockDeferredWithdrawal();
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.blockDeferredWithdrawal();
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.blockDeferredWithdrawal();
    }
    
    function testBlockDeferredWithdrawalMultipleToggles() public {
        // Start with true
        assertTrue(proofOfCapital.canWithdrawal());
        
        // Toggle to false
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Toggle back to true
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertTrue(proofOfCapital.canWithdrawal());
        
        // Toggle to false again
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Toggle back to true again
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertTrue(proofOfCapital.canWithdrawal());
    }
    
    function testBlockDeferredWithdrawalAfterLockExtension() public {
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Move time close to original lock end
        uint256 originalLockEndTime = proofOfCapital.lockEndTime();
        vm.warp(originalLockEndTime - Constants.THIRTY_DAYS + 1 days);
        
        // Extend the lock
        vm.prank(owner);
        proofOfCapital.extendLock(Constants.HALF_YEAR);
        
        // Now try to unblock - should work because lock was extended
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        
        // Should now be true
        assertTrue(proofOfCapital.canWithdrawal());
    }
    
    // Tests for setUnwrapMode function
    function testSetUnwrapModeSameUnwrapModeAlreadyActive() public {
        // Initially isNeedToUnwrap is true
        assertTrue(proofOfCapital.isNeedToUnwrap());
        
        // Try to set the same value (true)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.SameUnwrapModeAlreadyActive.selector);
        proofOfCapital.setUnwrapMode(true);
        
        // Change to false first
        vm.prank(owner);
        proofOfCapital.setUnwrapMode(false);
        assertFalse(proofOfCapital.isNeedToUnwrap());
        
        // Try to set the same value (false) again
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.SameUnwrapModeAlreadyActive.selector);
        proofOfCapital.setUnwrapMode(false);
    }
    
    function testSetUnwrapModeOnlyOwner() public {
        // Non-owner tries to set unwrap mode
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.setUnwrapMode(false);
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.setUnwrapMode(false);
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.setUnwrapMode(false);
        
        // Verify state wasn't changed
        assertTrue(proofOfCapital.isNeedToUnwrap());
    }
    
    function testSetUnwrapModeEvent() public {
        // Test event emission when changing from true to false
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IProofOfCapital.UnwrapModeChanged(false);
        proofOfCapital.setUnwrapMode(false);
        
        // Test event emission when changing from false to true
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IProofOfCapital.UnwrapModeChanged(true);
        proofOfCapital.setUnwrapMode(true);
    }
    
    function testSetUnwrapModeMultipleToggles() public {
        // Start with true (default)
        assertTrue(proofOfCapital.isNeedToUnwrap());
        
        // Toggle to false
        vm.prank(owner);
        proofOfCapital.setUnwrapMode(false);
        assertFalse(proofOfCapital.isNeedToUnwrap());
        
        // Toggle back to true
        vm.prank(owner);
        proofOfCapital.setUnwrapMode(true);
        assertTrue(proofOfCapital.isNeedToUnwrap());
        
        // Toggle to false again
        vm.prank(owner);
        proofOfCapital.setUnwrapMode(false);
        assertFalse(proofOfCapital.isNeedToUnwrap());
        
        // Toggle back to true again
        vm.prank(owner);
        proofOfCapital.setUnwrapMode(true);
        assertTrue(proofOfCapital.isNeedToUnwrap());
    }
    
    function testSetUnwrapModeAccessControl() public {
        // Test various unauthorized addresses
        address[] memory unauthorizedAddresses = new address[](5);
        unauthorizedAddresses[0] = royalty;
        unauthorizedAddresses[1] = returnWallet;
        unauthorizedAddresses[2] = marketMaker;
        unauthorizedAddresses[3] = address(0x999);
        unauthorizedAddresses[4] = address(this);
        
        for (uint256 i = 0; i < unauthorizedAddresses.length; i++) {
            vm.prank(unauthorizedAddresses[i]);
            vm.expectRevert();
            proofOfCapital.setUnwrapMode(false);
            
            // Verify state remains unchanged
            assertTrue(proofOfCapital.isNeedToUnwrap());
        }
        
        // Verify only owner can change
        vm.prank(owner);
        proofOfCapital.setUnwrapMode(false);
        assertFalse(proofOfCapital.isNeedToUnwrap());
    }
    
    // Tests for changeReturnWallet function
    function testChangeReturnWalletSuccess() public {
        address newReturnWallet = address(0x999);
        
        // Verify initial state
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
        
        // Change return wallet
        vm.prank(owner);
        proofOfCapital.changeReturnWallet(newReturnWallet);
        
        // Verify change
        assertEq(proofOfCapital.returnWalletAddress(), newReturnWallet);
    }
    
    function testChangeReturnWalletInvalidAddress() public {
        // Try to set zero address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidAddress.selector);
        proofOfCapital.changeReturnWallet(address(0));
        
        // Verify state wasn't changed
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
    }
    
    function testChangeReturnWalletOnlyOwner() public {
        address newReturnWallet = address(0x999);
        
        // Non-owner tries to change return wallet
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.changeReturnWallet(newReturnWallet);
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.changeReturnWallet(newReturnWallet);
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.changeReturnWallet(newReturnWallet);
        
        // Verify state wasn't changed
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
    }
    
    function testChangeReturnWalletEvent() public {
        address newReturnWallet = address(0x999);
        
        // Expect ReturnWalletChanged event
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IProofOfCapital.ReturnWalletChanged(newReturnWallet);
        proofOfCapital.changeReturnWallet(newReturnWallet);
    }
    
    function testChangeReturnWalletMultipleTimes() public {
        address firstNewWallet = address(0x777);
        address secondNewWallet = address(0x888);
        
        // First change
        vm.prank(owner);
        proofOfCapital.changeReturnWallet(firstNewWallet);
        assertEq(proofOfCapital.returnWalletAddress(), firstNewWallet);
        
        // Second change
        vm.prank(owner);
        proofOfCapital.changeReturnWallet(secondNewWallet);
        assertEq(proofOfCapital.returnWalletAddress(), secondNewWallet);
    }
    
    function testChangeReturnWalletToSameAddress() public {
        // Change to same address should work (no restriction)
        vm.prank(owner);
        proofOfCapital.changeReturnWallet(returnWallet);
        
        // Verify it's still the same
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
    }
    
    function testChangeReturnWalletValidAddresses() public {
        // Test with various valid addresses
        address[] memory validAddresses = new address[](4);
        validAddresses[0] = address(0x123);
        validAddresses[1] = address(0xABC);
        validAddresses[2] = address(this);
        validAddresses[3] = owner;
        
        for (uint256 i = 0; i < validAddresses.length; i++) {
            vm.prank(owner);
            proofOfCapital.changeReturnWallet(validAddresses[i]);
            assertEq(proofOfCapital.returnWalletAddress(), validAddresses[i]);
        }
    }
    
    // Tests for changeRoyaltyWallet function
    function testChangeRoyaltyWalletSuccess() public {
        address newRoyaltyWallet = address(0x999);
        
        // Verify initial state
        assertEq(proofOfCapital.royaltyWalletAddress(), royalty);
        
        // Change royalty wallet
        vm.prank(royalty);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);
        
        // Verify change
        assertEq(proofOfCapital.royaltyWalletAddress(), newRoyaltyWallet);
    }
    
    function testChangeRoyaltyWalletInvalidAddress() public {
        // Try to set zero address
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.InvalidAddress.selector);
        proofOfCapital.changeRoyaltyWallet(address(0));
        
        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyWalletAddress(), royalty);
    }
    
    function testChangeRoyaltyWalletOnlyRoyaltyWalletCanChange() public {
        address newRoyaltyWallet = address(0x999);
        
        // Non-royalty wallet tries to change royalty wallet
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);
        
        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);
        
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);
        
        vm.prank(address(0x123));
        vm.expectRevert(ProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);
        
        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyWalletAddress(), royalty);
    }
    
    function testChangeRoyaltyWalletEvent() public {
        address newRoyaltyWallet = address(0x999);
        
        // Expect RoyaltyWalletChanged event
        vm.prank(royalty);
        vm.expectEmit(true, false, false, false);
        emit IProofOfCapital.RoyaltyWalletChanged(newRoyaltyWallet);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);
    }
    
    function testChangeRoyaltyWalletMultipleTimes() public {
        address firstNewWallet = address(0x777);
        address secondNewWallet = address(0x888);
        
        // First change
        vm.prank(royalty);
        proofOfCapital.changeRoyaltyWallet(firstNewWallet);
        assertEq(proofOfCapital.royaltyWalletAddress(), firstNewWallet);
        
        // Second change (now firstNewWallet is the royalty wallet)
        vm.prank(firstNewWallet);
        proofOfCapital.changeRoyaltyWallet(secondNewWallet);
        assertEq(proofOfCapital.royaltyWalletAddress(), secondNewWallet);
    }
    
    function testChangeRoyaltyWalletToSameAddress() public {
        // Change to same address should work (no restriction)
        vm.prank(royalty);
        proofOfCapital.changeRoyaltyWallet(royalty);
        
        // Verify it's still the same
        assertEq(proofOfCapital.royaltyWalletAddress(), royalty);
    }
    
    function testChangeRoyaltyWalletValidAddresses() public {
        // Test with various valid addresses
        address[] memory validAddresses = new address[](4);
        validAddresses[0] = address(0x123);
        validAddresses[1] = address(0xABC);
        validAddresses[2] = address(this);
        validAddresses[3] = owner;
        
        address currentRoyaltyWallet = royalty;
        
        for (uint256 i = 0; i < validAddresses.length; i++) {
            vm.prank(currentRoyaltyWallet);
            proofOfCapital.changeRoyaltyWallet(validAddresses[i]);
            assertEq(proofOfCapital.royaltyWalletAddress(), validAddresses[i]);
            currentRoyaltyWallet = validAddresses[i];
        }
    }
    
    function testChangeRoyaltyWalletAccessControlAfterChange() public {
        address newRoyaltyWallet = address(0x999);
        
        // Change royalty wallet
        vm.prank(royalty);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);
        
        // Verify old royalty wallet can't change anymore
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(address(0x111));
        
        // Verify new royalty wallet can change
        address anotherNewWallet = address(0x111);
        vm.prank(newRoyaltyWallet);
        proofOfCapital.changeRoyaltyWallet(anotherNewWallet);
        assertEq(proofOfCapital.royaltyWalletAddress(), anotherNewWallet);
    }
    
    function testChangeRoyaltyWalletOwnerCannotChange() public {
        // Even owner cannot change royalty wallet
        address newRoyaltyWallet = address(0x999);
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);
        
        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyWalletAddress(), royalty);
    }
    
    // Tests for setMarketMaker function
    function testSetMarketMakerInvalidAddress() public {
        // Try to set market maker with zero address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidAddress.selector);
        proofOfCapital.setMarketMaker(address(0), true);
    }
    
    function testSetMarketMakerSuccess() public {
        address newMarketMaker = address(0x999);
        
        // Initially should not be market maker
        assertFalse(proofOfCapital.marketMakerAddresses(newMarketMaker));
        
        // Set as market maker
        vm.prank(owner);
        proofOfCapital.setMarketMaker(newMarketMaker, true);
        
        // Should now be market maker
        assertTrue(proofOfCapital.marketMakerAddresses(newMarketMaker));
    }
    
    function testSetMarketMakerRemove() public {
        // Initially marketMaker should be set
        assertTrue(proofOfCapital.marketMakerAddresses(marketMaker));
        
        // Remove market maker status
        vm.prank(owner);
        proofOfCapital.setMarketMaker(marketMaker, false);
        
        // Should no longer be market maker
        assertFalse(proofOfCapital.marketMakerAddresses(marketMaker));
    }
    
    function testSetMarketMakerOnlyOwner() public {
        address newMarketMaker = address(0x999);
        
        // Non-owner tries to set market maker
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.setMarketMaker(newMarketMaker, true);
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.setMarketMaker(newMarketMaker, true);
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.setMarketMaker(newMarketMaker, true);
    }
    
    function testSetMarketMakerEvent() public {
        address newMarketMaker = address(0x999);
        
        // Test event emission when setting market maker
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IProofOfCapital.MarketMakerStatusChanged(newMarketMaker, true);
        proofOfCapital.setMarketMaker(newMarketMaker, true);
        
        // Test event emission when removing market maker
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IProofOfCapital.MarketMakerStatusChanged(newMarketMaker, false);
        proofOfCapital.setMarketMaker(newMarketMaker, false);
    }
    
    // Tests for switchProfitMode function
    function testSwitchProfitModeEvent() public {
        // Test switching to false
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IProofOfCapital.ProfitModeChanged(false);
        proofOfCapital.switchProfitMode(false);
        
        // Test switching back to true
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IProofOfCapital.ProfitModeChanged(true);
        proofOfCapital.switchProfitMode(true);
    }
    
    function testSwitchProfitModeOnlyOwner() public {
        // Non-owner tries to switch profit mode
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.switchProfitMode(false);
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.switchProfitMode(false);
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.switchProfitMode(false);
    }
} 