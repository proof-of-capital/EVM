// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVMpragma solidity ^0.8.19;

import "../utils/BaseTest.sol";

contract ProofOfCapitalProfitTest is BaseTest {
    address public user = address(0x5);
    
    function setUp() public override {
        super.setUp();
        
        vm.startPrank(owner);
        
        // Setup tokens for users and add market maker permissions
        token.transfer(address(proofOfCapital), 1000000e18);
        weth.transfer(user, 10000e18);
        weth.transfer(marketMaker, 10000e18);
        
        // Enable market maker for user to allow trading
        proofOfCapital.setMarketMaker(user, true);
        
        vm.stopPrank();
        
        // Approve tokens
        vm.prank(user);
        weth.approve(address(proofOfCapital), type(uint256).max);
        
        vm.prank(marketMaker);
        weth.approve(address(proofOfCapital), type(uint256).max);
    }
    
    function testGetProfitOnRequestWhenProfitModeNotActive() public {
        // Disable profit on request mode
        vm.prank(owner);
        proofOfCapital.switchProfitMode(false);
        
        // Try to get profit when mode is not active (without any trading)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.ProfitModeNotActive.selector);
        proofOfCapital.getProfitOnRequest();
    }
    
    function testGetProfitOnRequestWithNoProfitAvailable() public {
        // Try to get profit when there's no profit
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.getProfitOnRequest();
        
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.getProfitOnRequest();
    }
    
    function testGetProfitOnRequestUnauthorized() public {
        // Unauthorized user tries to get profit (without any trading)
        vm.prank(user);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.getProfitOnRequest();
    }

    function testGetProfitOnRequestOwnerSimple() public {
        // Enable profit on request mode (should be enabled by default)
        assertTrue(proofOfCapital.profitInTime());
        
        // Manually set owner profit balance for testing
        // We'll use the deposit function to simulate profit accumulation
        vm.prank(owner);
        weth.transfer(address(proofOfCapital), 1000e18);
        
        // Manually set profit balance using internal state
        // Since we can't directly modify internal balance, we'll test error case
        
        // Owner requests profit when no profit available
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.getProfitOnRequest();
    }
    
    function testGetProfitOnRequestRoyaltySimple() public {
        // Royalty requests profit when no profit available
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.getProfitOnRequest();
    }
    
    // Tests for changeProfitPercentage function
    function testChangeProfitPercentageOwnerIncrease() public {
        // Owner can only increase royalty percentage (from 500 to higher)
        uint256 newPercentage = 600; // 60%
        uint256 initialRoyaltyPercent = proofOfCapital.royaltyProfitPercent(); // Should be 500
        uint256 initialCreatorPercent = proofOfCapital.creatorProfitPercent(); // Should be 500
        
        // Verify initial state
        assertEq(initialRoyaltyPercent, 500);
        assertEq(initialCreatorPercent, 500);
        
        // Owner increases royalty percentage
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(newPercentage);
        
        // Verify changes
        assertEq(proofOfCapital.royaltyProfitPercent(), newPercentage);
        assertEq(proofOfCapital.creatorProfitPercent(), Constants.PERCENTAGE_DIVISOR - newPercentage);
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
        assertEq(proofOfCapital.creatorProfitPercent(), Constants.PERCENTAGE_DIVISOR - newPercentage);
    }
    
    function testChangeProfitPercentageAccessDenied() public {
        uint256 newPercentage = 600;
        
        // Unauthorized users try to change profit percentage
        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);
        
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);
        
        vm.prank(address(0x999));
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);
        
        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyProfitPercent(), 500);
    }
    
    function testChangeProfitPercentageInvalidPercentageZero() public {
        // Try to set percentage to 0
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(0);
        
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(0);
    }
    
    function testChangeProfitPercentageInvalidPercentageExceedsMax() public {
        // Try to set percentage above PERCENTAGE_DIVISOR (1000)
        uint256 invalidPercentage = Constants.PERCENTAGE_DIVISOR + 1;
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(invalidPercentage);
        
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(invalidPercentage);
    }
    
    function testChangeProfitPercentageOwnerCannotDecrease() public {
        // Owner tries to decrease royalty percentage (from 500 to lower)
        uint256 lowerPercentage = 400; // 40%
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.CannotDecreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(lowerPercentage);
        
        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyProfitPercent(), 500);
    }
    
    function testChangeProfitPercentageRoyaltyCannotIncrease() public {
        // Royalty wallet tries to increase royalty percentage (from 500 to higher)
        uint256 higherPercentage = 600; // 60%
        
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.CannotIncreaseRoyalty.selector);
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
        assertEq(proofOfCapital.creatorProfitPercent(), Constants.PERCENTAGE_DIVISOR - 1);
        
        // Test with boundary value PERCENTAGE_DIVISOR (maximum valid)
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(Constants.PERCENTAGE_DIVISOR);
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.PERCENTAGE_DIVISOR);
        assertEq(proofOfCapital.creatorProfitPercent(), 0);
    }
    
    function testChangeProfitPercentageOwnerEqualToCurrent() public {
        // Owner tries to set the same percentage (not allowed - must be greater)
        uint256 currentPercentage = proofOfCapital.royaltyProfitPercent(); // 500
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.CannotDecreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(currentPercentage);
    }
    
    function testChangeProfitPercentageRoyaltyEqualToCurrent() public {
        // Royalty tries to set the same percentage (not allowed - must be less)
        uint256 currentPercentage = proofOfCapital.royaltyProfitPercent(); // 500
        
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.CannotIncreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(currentPercentage);
    }
    
    function testChangeProfitPercentageSequentialChanges() public {
        // Test sequential changes: owner increases, then royalty decreases
        
        // Step 1: Owner increases from 500 to 700
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(700);
        assertEq(proofOfCapital.royaltyProfitPercent(), 700);
        assertEq(proofOfCapital.creatorProfitPercent(), 300);
        
        // Step 2: Royalty decreases from 700 to 600
        vm.prank(royalty);
        proofOfCapital.changeProfitPercentage(600);
        assertEq(proofOfCapital.royaltyProfitPercent(), 600);
        assertEq(proofOfCapital.creatorProfitPercent(), 400);
        
        // Step 3: Owner increases from 600 to 800
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(800);
        assertEq(proofOfCapital.royaltyProfitPercent(), 800);
        assertEq(proofOfCapital.creatorProfitPercent(), 200);
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
            uint256 creatorPercent = proofOfCapital.creatorProfitPercent();
            
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
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);
        
        // New royalty wallet should have access
        vm.prank(newRoyaltyWallet);
        proofOfCapital.changeProfitPercentage(newPercentage);
        assertEq(proofOfCapital.royaltyProfitPercent(), newPercentage);
    }
} 