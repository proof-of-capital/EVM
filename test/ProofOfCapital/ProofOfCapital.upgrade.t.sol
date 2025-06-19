// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM
pragma solidity ^0.8.19;

import "../utils/BaseTest.sol";

contract ProofOfCapitalUpgradeTest is BaseTest {
    
    function testUpgradeFlow() public {
        // Deploy new implementation
        ProofOfCapital newImplementation = new ProofOfCapital();
        
        // Step 1: Royalty proposes upgrade
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(newImplementation));
        
        // Check that upgrade is proposed
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(newImplementation));
        assertEq(proofOfCapital.upgradeProposalTime(), block.timestamp);
        assertFalse(proofOfCapital.upgradeConfirmed());
        
        // Step 2: Owner confirms upgrade within 30 days
        vm.prank(owner);
        proofOfCapital.confirmUpgrade();
        
        // Check that upgrade is confirmed
        assertTrue(proofOfCapital.upgradeConfirmed());
        assertEq(proofOfCapital.upgradeConfirmationTime(), block.timestamp);
        
        // Step 3: Wait 30 days after confirmation
        vm.warp(block.timestamp + Constants.THIRTY_DAYS + 1);
        
        // Step 4: Try to upgrade (should work now)
        vm.prank(owner);
        proofOfCapital.upgradeToAndCall(address(newImplementation), "");
        
        // Check that upgrade state is reset
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0));
        assertEq(proofOfCapital.upgradeProposalTime(), 0);
        assertFalse(proofOfCapital.upgradeConfirmed());
        assertEq(proofOfCapital.upgradeConfirmationTime(), 0);
    }
    
    function testUpgradeProposalByNonRoyalty() public {
        ProofOfCapital newImplementation = new ProofOfCapital();
        
        // Should revert when non-royalty tries to propose upgrade
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OnlyRoyaltyCanProposeUpgrade.selector);
        proofOfCapital.proposeUpgrade(address(newImplementation));
    }
    
    function testUpgradeConfirmationTimeout() public {
        ProofOfCapital newImplementation = new ProofOfCapital();
        
        // Royalty proposes upgrade
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(newImplementation));
        
        // Wait more than 30 days
        vm.warp(block.timestamp + Constants.THIRTY_DAYS + 1);
        
        // Owner tries to confirm after timeout
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UpgradeProposalExpired.selector);
        proofOfCapital.confirmUpgrade();
    }
    
    function testUpgradeWithoutConfirmation() public {
        ProofOfCapital newImplementation = new ProofOfCapital();
        
        // Royalty proposes upgrade
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(newImplementation));
        
        // Try to upgrade without confirmation
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UpgradeNotConfirmed.selector);
        proofOfCapital.upgradeToAndCall(address(newImplementation), "");
    }
    
    function testUpgradeBeforeConfirmationPeriod() public {
        ProofOfCapital newImplementation = new ProofOfCapital();
        
        // Royalty proposes upgrade
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(newImplementation));
        
        // Owner confirms upgrade
        vm.prank(owner);
        proofOfCapital.confirmUpgrade();
        
        // Try to upgrade immediately (should fail)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UpgradeConfirmationPeriodNotPassed.selector);
        proofOfCapital.upgradeToAndCall(address(newImplementation), "");
    }
    
    function testCancelUpgradeProposal() public {
        ProofOfCapital newImplementation = new ProofOfCapital();
        
        // Royalty proposes upgrade
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(newImplementation));
        
        // Owner cancels upgrade proposal
        vm.prank(owner);
        proofOfCapital.cancelUpgradeProposal();
        
        // Check that proposal is cancelled
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0));
        assertEq(proofOfCapital.upgradeProposalTime(), 0);
        assertFalse(proofOfCapital.upgradeConfirmed());
        assertEq(proofOfCapital.upgradeConfirmationTime(), 0);
    }
    
    function testUpgradeWithDifferentImplementation() public {
        // Deploy two different implementations
        ProofOfCapital proposedImplementation = new ProofOfCapital();
        ProofOfCapital differentImplementation = new ProofOfCapital();
        
        // Step 1: Royalty proposes upgrade with first implementation
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(proposedImplementation));
        
        // Step 2: Owner confirms upgrade
        vm.prank(owner);
        proofOfCapital.confirmUpgrade();
        
        // Step 3: Wait 30 days after confirmation
        vm.warp(block.timestamp + Constants.THIRTY_DAYS + 1);
        
        // Step 4: Try to upgrade with different implementation (should fail)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidAddress.selector);
        proofOfCapital.upgradeToAndCall(address(differentImplementation), "");
        
        // Verify that the proposed implementation is still the original one
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(proposedImplementation));
        assertTrue(proofOfCapital.upgradeConfirmed());
    }
    
    // Test the NoUpgradeProposed error when trying to confirm upgrade without a proposal
    function testConfirmUpgradeWithNoProposal() public {
        // Verify no upgrade is proposed initially
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0));
        
        // Try to confirm upgrade when no upgrade was proposed
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoUpgradeProposed.selector);
        proofOfCapital.confirmUpgrade();
    }
    
    // Test the NoUpgradeProposed error when trying to cancel upgrade without a proposal
    function testCancelUpgradeWithNoProposal() public {
        // Verify no upgrade is proposed initially
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0));
        
        // Try to cancel upgrade proposal when no proposal exists - owner
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoUpgradeProposed.selector);
        proofOfCapital.cancelUpgradeProposal();
        
        // Try to cancel upgrade proposal when no proposal exists - royalty wallet
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.NoUpgradeProposed.selector);
        proofOfCapital.cancelUpgradeProposal();
    }
    
    // Test the NoUpgradeProposed error when trying to authorize upgrade without a proposal
    function testAuthorizeUpgradeWithNoProposal() public {
        ProofOfCapital newImplementation = new ProofOfCapital();
        
        // Verify no upgrade is proposed initially
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0));
        
        // Try to upgrade when no upgrade was proposed
        // This will trigger _authorizeUpgrade internally
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoUpgradeProposed.selector);
        proofOfCapital.upgradeToAndCall(address(newImplementation), "");
    }
    
    function testUpgradeProposalWithInvalidAddress() public {
        // Test proposeUpgrade with zero address (InvalidAddress error)
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.InvalidAddress.selector);
        proofOfCapital.proposeUpgrade(address(0));
    }
    
    function testUpgradeAlreadyProposedInProposeUpgrade() public {
        ProofOfCapital newImplementation1 = new ProofOfCapital();
        ProofOfCapital newImplementation2 = new ProofOfCapital();
        
        // First proposal should succeed
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(newImplementation1));
        
        // Second proposal should fail with UpgradeAlreadyProposed
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.UpgradeAlreadyProposed.selector);
        proofOfCapital.proposeUpgrade(address(newImplementation2));
    }
    
    // Test for require(!upgradeConfirmed, UpgradeAlreadyProposed()) 
    function testProposeUpgradeWhenAlreadyConfirmed() public {
        // First proposal by royalty
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(0x111));
        
        // Owner confirms the upgrade
        vm.prank(owner);
        proofOfCapital.confirmUpgrade();
        
        // Verify upgrade is confirmed
        assertTrue(proofOfCapital.upgradeConfirmed());
        
        // Try to propose new upgrade when current one is already confirmed
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.UpgradeAlreadyProposed.selector);
        proofOfCapital.proposeUpgrade(address(0x222));
    }

    // Test for require(!upgradeConfirmed, UpgradeAlreadyProposed()) in confirmUpgrade
    function testConfirmUpgradeWhenAlreadyConfirmed() public {
        // First proposal by royalty
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(0x111));
        
        // Owner confirms the upgrade first time
        vm.prank(owner);
        proofOfCapital.confirmUpgrade();
        
        // Verify upgrade is confirmed
        assertTrue(proofOfCapital.upgradeConfirmed());
        
        // Try to confirm again when already confirmed
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UpgradeAlreadyProposed.selector);
        proofOfCapital.confirmUpgrade();
    }
    
    // Tests for access control in cancelUpgradeProposal
    function testCancelUpgradeProposalByOwner() public {
        // First proposal by royalty
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(0x111));
        
        // Owner cancels the upgrade
        vm.prank(owner);
        proofOfCapital.cancelUpgradeProposal();
        
        // Verify proposal was cancelled
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0));
        assertEq(proofOfCapital.upgradeProposalTime(), 0);
        assertFalse(proofOfCapital.upgradeConfirmed());
        assertEq(proofOfCapital.upgradeConfirmationTime(), 0);
    }
    
    function testCancelUpgradeProposalByRoyalty() public {
        // First proposal by royalty
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(0x111));
        
        // Royalty wallet cancels the upgrade
        vm.prank(royalty);
        proofOfCapital.cancelUpgradeProposal();
        
        // Verify proposal was cancelled
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0));
        assertEq(proofOfCapital.upgradeProposalTime(), 0);
        assertFalse(proofOfCapital.upgradeConfirmed());
        assertEq(proofOfCapital.upgradeConfirmationTime(), 0);
    }
    
    function testCancelUpgradeProposalAccessDenied() public {
        // First proposal by royalty
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(0x111));
        
        // Try to cancel by non-authorized address
        address nonAuthorized = address(0x999);
        vm.prank(nonAuthorized);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.cancelUpgradeProposal();
        
        // Verify proposal was not cancelled
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0x111));
        assertTrue(proofOfCapital.upgradeProposalTime() > 0);
    }
    
    function testCancelUpgradeProposalAfterRoyaltyChange() public {
        // First proposal by royalty
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(0x111));
        
        // Change royalty wallet
        address newRoyalty = address(0x777);
        vm.prank(royalty);
        proofOfCapital.changeRoyaltyWallet(newRoyalty);
        
        // Old royalty tries to cancel - should fail
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.cancelUpgradeProposal();
        
        // New royalty should be able to cancel
        vm.prank(newRoyalty);
        proofOfCapital.cancelUpgradeProposal();
        
        // Verify proposal was cancelled
        assertEq(proofOfCapital.proposedUpgradeImplementation(), address(0));
        assertEq(proofOfCapital.upgradeProposalTime(), 0);
    }
} 