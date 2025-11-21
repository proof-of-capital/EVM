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

contract ProofOfCapitalReturnWalletChangeTest is BaseTest {
    address public newReturnWallet = address(0x999);
    address public anotherNewReturnWallet = address(0xAAA);

    // Helper function to ensure lock is active (trading access is false)
    function ensureLockIsActive() internal {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();

        // Ensure we're more than 60 days before lock end
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
    }

    // Helper function to make trading active (lock is not active)
    function makeTradingActive() internal {
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1); // Within 60 days
    }

    // ========== Tests for proposeReturnWalletChange ==========

    function testProposeReturnWalletChangeSuccess() public {
        ensureLockIsActive();

        address initialReturnWallet = proofOfCapital.returnWalletAddress();
        assertEq(initialReturnWallet, returnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
        assertEq(proofOfCapital.proposedReturnWalletChangeTime(), 0);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ProofOfCapital.ReturnWalletChangeProposed(newReturnWallet, block.timestamp);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);

        assertEq(proofOfCapital.proposedReturnWalletAddress(), newReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletChangeTime(), block.timestamp);
        // Return wallet should not change yet
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
    }

    function testProposeReturnWalletChangeOnlyOwner() public {
        ensureLockIsActive();

        // Non-owner tries to propose
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeLockIsActive() public {
        makeTradingActive();

        // Try to propose when trading is active (lock is not active)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockIsActive.selector);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeInvalidAddress() public {
        ensureLockIsActive();

        // Try to propose with zero address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidAddress.selector);
        proofOfCapital.proposeReturnWalletChange(address(0));

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithOwnerAddress() public {
        ensureLockIsActive();

        // Try to propose with owner address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(owner);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithReserveOwnerAddress() public {
        ensureLockIsActive();

        address reserveOwnerAddr = proofOfCapital.reserveOwner();

        // Try to propose with reserveOwner address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(reserveOwnerAddr);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithLaunchTokenAddress() public {
        ensureLockIsActive();

        // Try to propose with launchToken address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(address(token));

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithWethAddress() public {
        ensureLockIsActive();

        // Try to propose with wethAddress
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(address(weth));

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithTokenCollateralAddress() public {
        ensureLockIsActive();

        address tokenCollateralAddr = proofOfCapital.collateralAddress();

        // Try to propose with collateralAddress
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(tokenCollateralAddr);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithCurrentReturnWalletAddress() public {
        ensureLockIsActive();

        // Try to propose with current returnWalletAddress
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(returnWallet);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithRoyaltyWalletAddress() public {
        ensureLockIsActive();

        // Try to propose with royaltyWalletAddress
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(royalty);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithRecipientDeferredWithdrawalLaunch() public {
        ensureLockIsActive();

        // First, schedule a deferred withdrawal to set recipientDeferredWithdrawalLaunch
        address recipient = address(0x777);
        uint256 amount = 1000e18;

        // Create collateral balance first
        createCollateralBalance(amount * 2);

        vm.prank(owner);
        proofOfCapital.tokenDeferredWithdrawal(recipient, amount);

        address scheduledRecipient = proofOfCapital.recipientDeferredWithdrawalLaunch();

        // After scheduling deferred withdrawal, trading becomes active (lock is not active)
        // So we cannot propose a change - we get LockIsActive error
        // Note: The conflict check happens after the lock check, so we get LockIsActive first
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockIsActive.selector);
        proofOfCapital.proposeReturnWalletChange(scheduledRecipient);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithRecipientDeferredWithdrawalCollateralToken() public {
        ensureLockIsActive();

        // First, schedule a deferred withdrawal to set recipientDeferredWithdrawalCollateralToken
        address recipient = address(0x888);
        uint256 amount = 1000e18;

        // Create collateral balance first
        createCollateralBalance(amount * 2);

        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        address scheduledRecipient = proofOfCapital.recipientDeferredWithdrawalCollateralToken();

        // After scheduling deferred withdrawal, trading becomes active (lock is not active)
        // So we cannot propose a change - we get LockIsActive error
        // Note: The conflict check happens after the lock check, so we get LockIsActive first
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockIsActive.selector);
        proofOfCapital.proposeReturnWalletChange(scheduledRecipient);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithMarketMakerAddress() public {
        ensureLockIsActive();

        // Try to propose with marketMaker address (already a market maker)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(marketMaker);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithNewMarketMakerAddress() public {
        ensureLockIsActive();

        // Add a new market maker
        address newMarketMaker = address(0xBBB);
        vm.prank(owner);
        proofOfCapital.setMarketMaker(newMarketMaker, true);

        // Try to propose with new market maker address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(newMarketMaker);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeWithOldContractAddress() public {
        ensureLockIsActive();

        // Register an old contract
        address oldContract = address(0xCCC);
        vm.prank(owner);
        proofOfCapital.registerOldContract(oldContract);

        // Try to propose with old contract address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.proposeReturnWalletChange(oldContract);

        // Verify no proposal was made
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeReturnWalletChangeMultipleTimes() public {
        ensureLockIsActive();

        // First proposal
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), newReturnWallet);
        uint256 firstProposalTime = proofOfCapital.proposedReturnWalletChangeTime();

        // Move time forward to ensure second proposal has different timestamp
        vm.warp(block.timestamp + 1);

        // Second proposal (should overwrite first)
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(anotherNewReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), anotherNewReturnWallet);
        assertGt(proofOfCapital.proposedReturnWalletChangeTime(), firstProposalTime);
    }

    // ========== Tests for confirmReturnWalletChange ==========

    function testConfirmReturnWalletChangeSuccess() public {
        ensureLockIsActive();

        // First, propose a change
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);

        uint256 proposalTime = proofOfCapital.proposedReturnWalletChangeTime();
        assertEq(proofOfCapital.proposedReturnWalletAddress(), newReturnWallet);
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);

        // Wait 24 hours
        vm.warp(proposalTime + Constants.ONE_DAY);

        // Confirm the change
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ProofOfCapital.ReturnWalletChangeConfirmed(newReturnWallet);
        proofOfCapital.confirmReturnWalletChange();

        // Verify change was applied
        assertEq(proofOfCapital.returnWalletAddress(), newReturnWallet);
        // Verify proposal was cleared
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
        assertEq(proofOfCapital.proposedReturnWalletChangeTime(), 0);
    }

    function testConfirmReturnWalletChangeOnlyOwner() public {
        ensureLockIsActive();

        // Propose a change
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);
        vm.warp(block.timestamp + Constants.ONE_DAY);

        // Non-owner tries to confirm
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.confirmReturnWalletChange();

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.confirmReturnWalletChange();

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.confirmReturnWalletChange();

        // Verify change was not applied
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
        // Verify proposal still exists
        assertEq(proofOfCapital.proposedReturnWalletAddress(), newReturnWallet);
    }

    function testConfirmReturnWalletChangeLockIsActive() public {
        // Propose a change while lock is active
        ensureLockIsActive();
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);
        uint256 proposalTime = proofOfCapital.proposedReturnWalletChangeTime();
        vm.warp(proposalTime + Constants.ONE_DAY);

        // Make trading active (lock is not active)
        makeTradingActive();

        // Try to confirm when trading is active
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockIsActive.selector);
        proofOfCapital.confirmReturnWalletChange();

        // Verify change was not applied
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
        // Verify proposal still exists
        assertEq(proofOfCapital.proposedReturnWalletAddress(), newReturnWallet);
    }

    function testConfirmReturnWalletChangeNoProposal() public {
        ensureLockIsActive();

        // Try to confirm without a proposal
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoReturnWalletChangeProposed.selector);
        proofOfCapital.confirmReturnWalletChange();

        // Verify return wallet unchanged
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
    }

    function testConfirmReturnWalletChangeDelayNotPassed() public {
        ensureLockIsActive();

        // Propose a change
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);
        uint256 proposalTime = proofOfCapital.proposedReturnWalletChangeTime();

        // Try to confirm immediately (delay not passed)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.ReturnWalletChangeDelayNotPassed.selector);
        proofOfCapital.confirmReturnWalletChange();

        // Try to confirm after 23 hours (still not enough)
        vm.warp(proposalTime + Constants.ONE_DAY - 1);
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.ReturnWalletChangeDelayNotPassed.selector);
        proofOfCapital.confirmReturnWalletChange();

        // Verify change was not applied
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);
        // Verify proposal still exists
        assertEq(proofOfCapital.proposedReturnWalletAddress(), newReturnWallet);
    }

    function testConfirmReturnWalletChangeExactlyAfterOneDay() public {
        ensureLockIsActive();

        // Propose a change
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);
        uint256 proposalTime = proofOfCapital.proposedReturnWalletChangeTime();

        // Confirm exactly after 24 hours
        vm.warp(proposalTime + Constants.ONE_DAY);
        vm.prank(owner);
        proofOfCapital.confirmReturnWalletChange();

        // Verify change was applied
        assertEq(proofOfCapital.returnWalletAddress(), newReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testConfirmReturnWalletChangeAfterMoreThanOneDay() public {
        ensureLockIsActive();

        // Propose a change
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);
        uint256 proposalTime = proofOfCapital.proposedReturnWalletChangeTime();

        // Confirm after more than 24 hours
        vm.warp(proposalTime + Constants.ONE_DAY + 1 hours);
        vm.prank(owner);
        proofOfCapital.confirmReturnWalletChange();

        // Verify change was applied
        assertEq(proofOfCapital.returnWalletAddress(), newReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testConfirmReturnWalletChangeAfterProposalOverwrite() public {
        ensureLockIsActive();

        // First proposal
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);
        uint256 firstProposalTime = proofOfCapital.proposedReturnWalletChangeTime();

        // Wait a bit
        vm.warp(firstProposalTime + 12 hours);

        // Second proposal (overwrites first)
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(anotherNewReturnWallet);
        uint256 secondProposalTime = proofOfCapital.proposedReturnWalletChangeTime();

        // Try to confirm based on first proposal time (should fail)
        vm.warp(firstProposalTime + Constants.ONE_DAY);
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.ReturnWalletChangeDelayNotPassed.selector);
        proofOfCapital.confirmReturnWalletChange();

        // Confirm based on second proposal time (should succeed)
        vm.warp(secondProposalTime + Constants.ONE_DAY);
        vm.prank(owner);
        proofOfCapital.confirmReturnWalletChange();

        // Verify change was applied to second proposal
        assertEq(proofOfCapital.returnWalletAddress(), anotherNewReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));
    }

    function testProposeAndConfirmFullFlow() public {
        ensureLockIsActive();

        // Step 1: Propose
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(newReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), newReturnWallet);
        assertEq(proofOfCapital.returnWalletAddress(), returnWallet);

        // Step 2: Wait 24 hours
        uint256 proposalTime = proofOfCapital.proposedReturnWalletChangeTime();
        vm.warp(proposalTime + Constants.ONE_DAY);

        // Step 3: Confirm
        vm.prank(owner);
        proofOfCapital.confirmReturnWalletChange();
        assertEq(proofOfCapital.returnWalletAddress(), newReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), address(0));

        // Step 4: Can propose again with different address
        ensureLockIsActive();
        vm.prank(owner);
        proofOfCapital.proposeReturnWalletChange(anotherNewReturnWallet);
        assertEq(proofOfCapital.proposedReturnWalletAddress(), anotherNewReturnWallet);
    }
}

