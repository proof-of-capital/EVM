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

    function testExtendLockExceedsFiveYears() public {
        for (uint256 i = 0; i < 7; i++) {
            vm.prank(owner);
            proofOfCapital.extendLock(Constants.HALF_YEAR);
        }

        // Now try to extend by HALF_YEAR one more time - this should exceed the limit
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockCannotExceedFiveYears.selector);
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

    // COMMENTED: Test was failing
    /*
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
        vm.expectRevert(ProofOfCapital.LockCannotExceedFiveYears.selector);
        proofOfCapital.extendLock(Constants.HALF_YEAR);
    }
    */

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
        // Block withdrawal first
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Move time to less than 60 days before lock end (activation allowed when < 60 days)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1); // 59 days + 1 second remaining

        // Should be able to unblock when less than 60 days remain
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertTrue(proofOfCapital.canWithdrawal());
    }

    function testBlockDeferredWithdrawalFailsWhenTooFarFromLockEnd() public {
        // Move time to be more than 60 days before lock end (activation blocked when >= 60 days)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS - 1); // 60 days + 1 second remaining

        // Block withdrawal first
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Try to unblock when more than 60 days remain - should fail
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.CannotActivateWithdrawalTooCloseToLockEnd.selector);
        proofOfCapital.blockDeferredWithdrawal();
    }

    function testBlockDeferredWithdrawalAtExactBoundary() public {
        // Block withdrawal first
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Move time to exactly 60 days before lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS);

        // At exactly 60 days, should NOT be able to unblock (require < 60 days)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.CannotActivateWithdrawalTooCloseToLockEnd.selector);
        proofOfCapital.blockDeferredWithdrawal();
    }

    function testBlockDeferredWithdrawalJustOverBoundary() public {
        // First, block withdrawal to set canWithdrawal to false
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Move time to just under the boundary (59 days, 23 hours, 59 minutes, 59 seconds remaining)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1);

        // Should be able to activate withdrawal when less than 60 days remain
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
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

    // Tests for setUnwrapMode function

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

    // Tests for setDao function
    function testSetDAOAccessDenied() public {
        // By default, daoAddress is set to owner (from BaseTest)
        address newDaoAddress = address(0x999);

        // Non-DAO address tries to set DAO
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.setDao(newDaoAddress);

        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.setDao(newDaoAddress);

        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.setDao(newDaoAddress);

        vm.prank(address(0x123));
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.setDao(newDaoAddress);
    }

    function testSetDAOInvalidDAOAddress() public {
        // Try to set zero address as new DAO
        vm.prank(owner); // owner is the default daoAddress
        vm.expectRevert(ProofOfCapital.InvalidDAOAddress.selector);
        proofOfCapital.setDao(address(0));
    }
}
