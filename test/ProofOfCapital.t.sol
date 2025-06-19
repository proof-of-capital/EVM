// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVMpragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ProofOfCapital.sol";
import "../src/interfaces/IProofOfCapital.sol";
import "../src/utils/Constant.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

// Add proper WETH mock with deposit functionality
contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
    
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
    
    // Allow contract to receive ETH
    receive() external payable {}
}

contract ProofOfCapitalTest is Test {
    ProofOfCapital public proofOfCapital;
    MockERC20 public token;
    MockERC20 public weth;
    
    address public owner = address(0x1);
    address public royalty = address(0x2);
    address public returnWallet = address(0x3);
    address public marketMaker = address(0x4);
    
    function setUp() public {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023
        
        vm.startPrank(owner);
        
        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");
        
        // Deploy implementation
        ProofOfCapital implementation = new ProofOfCapital();
        
        // Prepare initialization parameters
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
            offsetJettons: 10000e18, // Add offset to enable trading
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0)
        });
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        proofOfCapital = ProofOfCapital(address(proxy));
        
        vm.stopPrank();
    }
    
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
    
    // Tests for jettonDeferredWithdrawal function
    function testJettonDeferredWithdrawalSuccess() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Schedule deferred withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Check that variables are set correctly
        assertEq(proofOfCapital.recipientDeferredWithdrawalMainJetton(), recipient);
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalAmount(), amount);
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalDate(), block.timestamp + Constants.THIRTY_DAYS);
    }
    
    function testJettonDeferredWithdrawalEmitsEvent() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        uint256 expectedExecuteTime = block.timestamp + Constants.THIRTY_DAYS;
        
        // Expect the event to be emitted
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IProofOfCapital.DeferredWithdrawalScheduled(recipient, amount, expectedExecuteTime);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
    }
    
    function testJettonDeferredWithdrawalInvalidRecipientZeroAddress() public {
        uint256 amount = 1000e18;
        
        // Try with zero address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidRecipientOrAmount.selector);
        proofOfCapital.jettonDeferredWithdrawal(address(0), amount);
    }
    
    function testJettonDeferredWithdrawalInvalidAmountZero() public {
        address recipient = address(0x123);
        
        // Try with zero amount
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidRecipientOrAmount.selector);
        proofOfCapital.jettonDeferredWithdrawal(recipient, 0);
    }
    
    function testJettonDeferredWithdrawalInvalidRecipientAndAmount() public {
        // Try with both zero address and zero amount
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidRecipientOrAmount.selector);
        proofOfCapital.jettonDeferredWithdrawal(address(0), 0);
    }
    
    function testJettonDeferredWithdrawalWhenWithdrawalBlocked() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Try to schedule deferred withdrawal when blocked
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
    }
    
    function testJettonDeferredWithdrawalAlreadyScheduled() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        uint256 amount1 = 1000e18;
        uint256 amount2 = 2000e18;
        
        // Schedule first withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient1, amount1);
        
        // Try to schedule second withdrawal (should fail)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.MainJettonDeferredWithdrawalAlreadyScheduled.selector);
        proofOfCapital.jettonDeferredWithdrawal(recipient2, amount2);
    }
    
    function testJettonDeferredWithdrawalUnauthorized() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Non-owner tries to schedule withdrawal
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
    }
    
    function testJettonDeferredWithdrawalWithDifferentAmounts() public {
        address recipient = address(0x123);
        
        // Test with different valid amounts
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1;
        amounts[1] = 100e18;
        amounts[2] = 1000000e18;
        amounts[3] = type(uint256).max;
        
        for (uint256 i = 0; i < amounts.length; i++) {
            // Reset state by stopping any existing withdrawal
            if (proofOfCapital.mainJettonDeferredWithdrawalAmount() > 0) {
                vm.prank(owner);
                proofOfCapital.stopJettonDeferredWithdrawal();
            }
            
            // Schedule withdrawal with this amount
            vm.prank(owner);
            proofOfCapital.jettonDeferredWithdrawal(recipient, amounts[i]);
            
            // Verify amount is set correctly
            assertEq(proofOfCapital.mainJettonDeferredWithdrawalAmount(), amounts[i]);
        }
    }
    
    function testJettonDeferredWithdrawalAfterUnblocking() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Block withdrawal first
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Unblock withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertTrue(proofOfCapital.canWithdrawal());
        
        // Now schedule withdrawal should work
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Verify it was scheduled
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalAmount(), amount);
        assertEq(proofOfCapital.recipientDeferredWithdrawalMainJetton(), recipient);
    }
    
    function testJettonDeferredWithdrawalDateCalculation() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Record current time
        uint256 currentTime = block.timestamp;
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Verify date is set correctly (current time + 30 days)
        uint256 expectedDate = currentTime + Constants.THIRTY_DAYS;
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalDate(), expectedDate);
        
        // Move time forward and schedule another (after stopping first)
        vm.warp(block.timestamp + 10 days);
        vm.prank(owner);
        proofOfCapital.stopJettonDeferredWithdrawal();
        
        uint256 newCurrentTime = block.timestamp;
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        uint256 newExpectedDate = newCurrentTime + Constants.THIRTY_DAYS;
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalDate(), newExpectedDate);
    }
    
    // Tests for stopJettonDeferredWithdrawal function (testing each require)
    function testStopJettonDeferredWithdrawalSuccess() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // First schedule a withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Verify it was scheduled
        assertTrue(proofOfCapital.mainJettonDeferredWithdrawalDate() > 0);
        
        // Stop the withdrawal
        vm.prank(owner);
        proofOfCapital.stopJettonDeferredWithdrawal();
        
        // Verify it was stopped
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalAmount(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalMainJetton(), owner);
    }
    
    function testStopJettonDeferredWithdrawalByRoyalty() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // First schedule a withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Stop the withdrawal using royalty wallet
        vm.prank(royalty);
        proofOfCapital.stopJettonDeferredWithdrawal();
        
        // Verify it was stopped
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalDate(), 0);
    }
    
    function testStopJettonDeferredWithdrawalAccessDenied() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // First schedule a withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Try to stop with unauthorized addresses
        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopJettonDeferredWithdrawal();
        
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopJettonDeferredWithdrawal();
    }
    
    function testStopJettonDeferredWithdrawalNoDeferredWithdrawalScheduled() public {
        // Try to stop without scheduling first
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopJettonDeferredWithdrawal();
        
        // Try with royalty wallet
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopJettonDeferredWithdrawal();
    }
    
    // Tests for confirmJettonDeferredWithdrawal function (testing each require)
    function testConfirmJettonDeferredWithdrawalDeferredWithdrawalBlocked() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Block withdrawals
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        
        // Try to confirm when blocked
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
    }
    
    function testConfirmJettonDeferredWithdrawalNoDeferredWithdrawalScheduled() public {
        // Try to confirm without scheduling
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
    }
    
    function testConfirmJettonDeferredWithdrawalWithdrawalDateNotReached() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Try to confirm before 30 days
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
        
        // Move time forward but not enough
        vm.warp(block.timestamp + Constants.THIRTY_DAYS - 1);
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
    }
    
    function testConfirmJettonDeferredWithdrawalInsufficientJettonBalance() public {
        // Test specific require: contractJettonBalance > totalJettonsSold
        // Default state: contractJettonBalance = 0, totalJettonsSold = 10000e18 (from offset)
        // This creates the exact condition for InsufficientJettonBalance error
        
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Verify initial state - contractJettonBalance should be <= totalJettonsSold
        uint256 contractBalance = proofOfCapital.contractJettonBalance();
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        
        // In our setup: contractJettonBalance = 0, totalJettonsSold = 10000e18 (offsetJettons)
        assertTrue(contractBalance <= totalSold, "Setup verification: contractJettonBalance should be <= totalJettonsSold");
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Move time forward to pass date requirement
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Try to confirm - should fail with InsufficientJettonBalance
        // because contractJettonBalance (0) <= totalJettonsSold (10000e18)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InsufficientJettonBalance.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
    }
    
    function testConfirmJettonDeferredWithdrawalInsufficientJettonBalanceSpecific() public {
        // Test specific require: contractJettonBalance > totalJettonsSold
        // Default state: contractJettonBalance = 0, totalJettonsSold = 10000e18 (from offset)
        // This creates the exact condition for InsufficientJettonBalance error
        
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Verify initial state - contractJettonBalance should be <= totalJettonsSold
        uint256 contractBalance = proofOfCapital.contractJettonBalance();
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        
        // In our setup: contractJettonBalance = 0, totalJettonsSold = 10000e18 (offsetJettons)
        assertTrue(contractBalance <= totalSold, "Setup verification: contractJettonBalance should be <= totalJettonsSold");
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Move time forward to pass date requirement
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Try to confirm - should fail with InsufficientJettonBalance
        // because contractJettonBalance (0) <= totalJettonsSold (10000e18)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InsufficientJettonBalance.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
    }
    
    function testConfirmJettonDeferredWithdrawalRequire5_InsufficientAmount() public {
        // Create scenario where:
        // 1. contractJettonBalance > totalJettonsSold (to pass require 4)
        // 2. contractJettonBalance - totalJettonsSold < mainJettonDeferredWithdrawalAmount (to fail require 5)
        
        address recipient = address(0x123);
        
        // Use returnWallet to sell tokens back to contract, which increases contractJettonBalance
        // From _handleReturnWalletSale: contractJettonBalance += amount;
        
        vm.startPrank(owner);
        
        // First, give some tokens to returnWallet to sell back
        token.transfer(returnWallet, 50000e18);
        
        vm.stopPrank();
        
        // ReturnWallet sells tokens back, which increases contractJettonBalance
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellTokens(50000e18); // This should increase contractJettonBalance
        vm.stopPrank();
        
        // Check the state - this should now have contractJettonBalance > totalJettonsSold
        uint256 contractBalance = proofOfCapital.contractJettonBalance();
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        
        // Ensure we have the first condition: contractJettonBalance > totalJettonsSold
        require(contractBalance > totalSold, "Setup failed: need contractJettonBalance > totalJettonsSold");
        
        // Calculate available tokens
        uint256 availableTokens = contractBalance - totalSold;
        
        // Request exactly availableTokens + 1 to trigger InsufficientAmount
        uint256 requestedAmount = availableTokens + 1;
        
        // Schedule withdrawal for more than available
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, requestedAmount);
        
        // Move time forward to pass the date check
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Now confirm withdrawal - should fail with exactly InsufficientAmount
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InsufficientAmount.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
    }
    
    function testConfirmJettonDeferredWithdrawalOnlyOwner() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Try to confirm with non-owner addresses
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.confirmJettonDeferredWithdrawal();
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.confirmJettonDeferredWithdrawal();
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.confirmJettonDeferredWithdrawal();
        
        vm.prank(recipient);
        vm.expectRevert();
        proofOfCapital.confirmJettonDeferredWithdrawal();
    }
    
    // Simple working test cases (without complex state setup)
    function testConfirmJettonDeferredWithdrawalBasicValidation() public {
        // Test that all our basic require checks work as expected
        
        // Test 1: No withdrawal scheduled
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
        
        // Test 2: Schedule and test date not reached
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, amount);
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
        
        // Test 3: Block withdrawals and test blocked error
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.confirmJettonDeferredWithdrawal();
    }

    function testConfirmJettonDeferredWithdrawalSuccess() public {
        // Test successful execution of confirmJettonDeferredWithdrawal
        // Need to create state where all require conditions pass:
        // 1. canWithdrawal = true (default)
        // 2. mainJettonDeferredWithdrawalDate != 0 (withdrawal scheduled)
        // 3. block.timestamp >= mainJettonDeferredWithdrawalDate (date reached)
        // 4. contractJettonBalance > totalJettonsSold (sufficient balance)
        // 5. contractJettonBalance - totalJettonsSold >= mainJettonDeferredWithdrawalAmount (sufficient available)
        
        address recipient = address(0x123);
        uint256 withdrawalAmount = 1000e18;
        
        // Step 1: Create state where contractJettonBalance > totalJettonsSold
        // Use returnWallet to sell tokens back to contract, increasing contractJettonBalance
        vm.startPrank(owner);
        token.transfer(returnWallet, 10000e18);
        vm.stopPrank();
        
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.sellTokens(10000e18); // This increases contractJettonBalance
        vm.stopPrank();
        
        // Step 2: Schedule withdrawal with amount less than available
        vm.prank(owner);
        proofOfCapital.jettonDeferredWithdrawal(recipient, withdrawalAmount);
        
        // Verify withdrawal is scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalMainJetton(), recipient);
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalAmount(), withdrawalAmount);
        assertTrue(proofOfCapital.mainJettonDeferredWithdrawalDate() > 0);
        
        // Step 3: Move time forward to reach withdrawal date
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Step 4: Get balances before confirmation
        uint256 recipientBalanceBefore = token.balanceOf(recipient);
        uint256 contractBalanceBefore = proofOfCapital.contractJettonBalance();
        
        // Verify we have sufficient balance for withdrawal
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        uint256 available = contractBalanceBefore - totalSold;
        assertTrue(available >= withdrawalAmount, "Insufficient available tokens for withdrawal");
        
        // Step 5: Confirm withdrawal - should succeed
        vm.prank(owner);
        proofOfCapital.confirmJettonDeferredWithdrawal();
        
        // Step 6: Verify successful execution
        // Check token transfer
        assertEq(token.balanceOf(recipient), recipientBalanceBefore + withdrawalAmount);
        
        // Check contract balance decreased
        assertEq(proofOfCapital.contractJettonBalance(), contractBalanceBefore - withdrawalAmount);
        
        // Check state variables reset
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.mainJettonDeferredWithdrawalAmount(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalMainJetton(), owner);
    }

    // Tests for assignNewOwner function
    function testAssignNewOwnerWhenOwnerEqualsReserveOwner() public {
        // In initial setup, owner == reserveOwner
        address newOwner = address(0x999);
        
        // Verify initial state
        assertEq(proofOfCapital.owner(), owner);
        assertEq(proofOfCapital.reserveOwner(), owner);
        assertTrue(proofOfCapital.owner() == proofOfCapital.reserveOwner());
        
        // Assign new owner from reserveOwner
        vm.prank(owner); // owner is also reserveOwner
        proofOfCapital.assignNewOwner(newOwner);
        
        // Both owner and reserveOwner should be transferred
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.reserveOwner(), newOwner);
    }
    
    function testAssignNewOwnerWhenOwnerNotEqualsReserveOwner() public {
        // First create state where owner != reserveOwner
        address intermediateReserveOwner = address(0x888);
        address newOwner = address(0x999);
        
        // Step 1: Transfer reserveOwner to different address
        vm.prank(owner);
        proofOfCapital.assignNewReserveOwner(intermediateReserveOwner);
        
        // Verify owner != reserveOwner
        assertEq(proofOfCapital.owner(), owner);
        assertEq(proofOfCapital.reserveOwner(), intermediateReserveOwner);
        assertTrue(proofOfCapital.owner() != proofOfCapital.reserveOwner());
        
        // Step 2: Assign new owner from reserveOwner
        vm.prank(intermediateReserveOwner);
        proofOfCapital.assignNewOwner(newOwner);
        
        // Only owner should be transferred, reserveOwner stays the same
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.reserveOwner(), intermediateReserveOwner);
    }
    
    function testAssignNewOwnerInvalidNewOwner() public {
        // Try to assign zero address as new owner
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidNewOwner.selector);
        proofOfCapital.assignNewOwner(address(0));
    }
    
    function testAssignNewOwnerOnlyReserveOwner() public {
        address newOwner = address(0x999);
        
        // Non-reserveOwner tries to assign new owner
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewOwner(newOwner);
        
        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewOwner(newOwner);
        
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewOwner(newOwner);
    }
    
    function testAssignNewOwnerEvents() public {
        address newOwner = address(0x999);
        
        // Test functionality without checking internal OpenZeppelin events
        vm.prank(owner);
        proofOfCapital.assignNewOwner(newOwner);
        
        // Verify the ownership change occurred
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.reserveOwner(), newOwner);
    }
    
    // Tests for assignNewReserveOwner function
    function testAssignNewReserveOwnerSuccess() public {
        address newReserveOwner = address(0x777);
        
        // Verify initial state
        assertEq(proofOfCapital.reserveOwner(), owner);
        
        // Assign new reserve owner
        vm.prank(owner);
        proofOfCapital.assignNewReserveOwner(newReserveOwner);
        
        // Verify new reserve owner
        assertEq(proofOfCapital.reserveOwner(), newReserveOwner);
        
        // Original owner should remain unchanged
        assertEq(proofOfCapital.owner(), owner);
    }
    
    function testAssignNewReserveOwnerInvalidReserveOwner() public {
        // Try to assign zero address as new reserve owner
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidReserveOwner.selector);
        proofOfCapital.assignNewReserveOwner(address(0));
    }
    
    function testAssignNewReserveOwnerOnlyReserveOwner() public {
        address newReserveOwner = address(0x777);
        
        // Non-reserveOwner tries to assign new reserve owner
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewReserveOwner(newReserveOwner);
        
        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewReserveOwner(newReserveOwner);
        
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewReserveOwner(newReserveOwner);
    }
    
    function testAssignNewReserveOwnerEvent() public {
        address newReserveOwner = address(0x777);
        
        // Expect ReserveOwnerChanged event
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IProofOfCapital.ReserveOwnerChanged(newReserveOwner);
        proofOfCapital.assignNewReserveOwner(newReserveOwner);
    }
    
    function testAssignNewReserveOwnerMultipleTimes() public {
        address firstNewReserveOwner = address(0x777);
        address secondNewReserveOwner = address(0x666);
        
        // First assignment
        vm.prank(owner);
        proofOfCapital.assignNewReserveOwner(firstNewReserveOwner);
        assertEq(proofOfCapital.reserveOwner(), firstNewReserveOwner);
        
        // Second assignment from new reserve owner
        vm.prank(firstNewReserveOwner);
        proofOfCapital.assignNewReserveOwner(secondNewReserveOwner);
        assertEq(proofOfCapital.reserveOwner(), secondNewReserveOwner);
    }
    
    function testComplexOwnershipScenario() public {
        // Test complex scenario with multiple ownership changes
        address newReserveOwner = address(0x777);
        address newOwner = address(0x888);
        address finalOwner = address(0x999);
        
        // Step 1: Change reserve owner
        vm.prank(owner);
        proofOfCapital.assignNewReserveOwner(newReserveOwner);
        
        // Step 2: New reserve owner assigns new owner (owner != reserveOwner case)
        vm.prank(newReserveOwner);
        proofOfCapital.assignNewOwner(newOwner);
        
        // Verify state
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.reserveOwner(), newReserveOwner);
        
        // Step 3: Reserve owner assigns himself as owner too
        vm.prank(newReserveOwner);
        proofOfCapital.assignNewOwner(newReserveOwner);
        
        // Now owner == reserveOwner again
        assertEq(proofOfCapital.owner(), newReserveOwner);
        assertEq(proofOfCapital.reserveOwner(), newReserveOwner);
        
        // Step 4: Assign final owner (should transfer both)
        vm.prank(newReserveOwner);
        proofOfCapital.assignNewOwner(finalOwner);
        
        // Both should be transferred
        assertEq(proofOfCapital.owner(), finalOwner);
        assertEq(proofOfCapital.reserveOwner(), finalOwner);
    }
    
    // Tests for supportDeferredWithdrawal function
    function testSupportDeferredWithdrawalSuccess() public {
        address recipient = address(0x123);
        
        // Schedule support withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Verify withdrawal is scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), recipient);
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), block.timestamp + Constants.THIRTY_DAYS);
    }
    
    function testSupportDeferredWithdrawalEmitsEvent() public {
        address recipient = address(0x123);
        uint256 expectedExecuteTime = block.timestamp + Constants.THIRTY_DAYS;
        
        // Note: contractSupportBalance is the amount that will be emitted in the event
        uint256 currentBalance = proofOfCapital.contractSupportBalance();
        
        // Expect the event to be emitted
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IProofOfCapital.DeferredWithdrawalScheduled(recipient, currentBalance, expectedExecuteTime);
        proofOfCapital.supportDeferredWithdrawal(recipient);
    }
    
    function testSupportDeferredWithdrawalDeferredWithdrawalBlocked() public {
        address recipient = address(0x123);
        
        // Block deferred withdrawals
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Try to schedule support withdrawal when blocked
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.supportDeferredWithdrawal(recipient);
    }
    
    function testSupportDeferredWithdrawalInvalidRecipient() public {
        // Try to schedule with zero address
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidRecipient.selector);
        proofOfCapital.supportDeferredWithdrawal(address(0));
    }
    
    function testSupportDeferredWithdrawalAlreadyScheduled() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        
        // Schedule first support withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient1);
        
        // Try to schedule second support withdrawal (should fail)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.SupportDeferredWithdrawalAlreadyScheduled.selector);
        proofOfCapital.supportDeferredWithdrawal(recipient2);
    }
    
    function testSupportDeferredWithdrawalOnlyOwner() public {
        address recipient = address(0x123);
        
        // Non-owner tries to schedule support withdrawal
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        vm.prank(recipient);
        vm.expectRevert();
        proofOfCapital.supportDeferredWithdrawal(recipient);
    }
    
    function testSupportDeferredWithdrawalAfterUnblocking() public {
        address recipient = address(0x123);
        
        // Block withdrawal first
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());
        
        // Unblock withdrawal
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        assertTrue(proofOfCapital.canWithdrawal());
        
        // Now schedule support withdrawal should work
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Verify it was scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), recipient);
        assertTrue(proofOfCapital.supportJettonDeferredWithdrawalDate() > 0);
    }
    
    function testSupportDeferredWithdrawalDateCalculation() public {
        address recipient = address(0x123);
        
        // Record current time
        uint256 currentTime = block.timestamp;
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Verify date is set correctly (current time + 30 days)
        uint256 expectedDate = currentTime + Constants.THIRTY_DAYS;
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), expectedDate);
        
        // Move time forward and schedule another (after stopping first)
        vm.warp(block.timestamp + 10 days);
        vm.prank(owner);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        uint256 newCurrentTime = block.timestamp;
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        uint256 newExpectedDate = newCurrentTime + Constants.THIRTY_DAYS;
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), newExpectedDate);
    }
    
    function testSupportDeferredWithdrawalWithDifferentRecipients() public {
        address[] memory recipients = new address[](3);
        recipients[0] = address(0x123);
        recipients[1] = address(0x456);
        recipients[2] = address(0x789);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            // Reset state by stopping any existing withdrawal
            if (proofOfCapital.supportJettonDeferredWithdrawalDate() > 0) {
                vm.prank(owner);
                proofOfCapital.stopSupportDeferredWithdrawal();
            }
            
            // Schedule withdrawal with this recipient
            vm.prank(owner);
            proofOfCapital.supportDeferredWithdrawal(recipients[i]);
            
            // Verify recipient is set correctly
            assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), recipients[i]);
        }
    }
    
    function testSupportDeferredWithdrawalStateConsistency() public {
        address recipient = address(0x123);
        
        // Initially no withdrawal should be scheduled
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner); // Default to owner
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Verify all state variables are set correctly
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), recipient);
        assertTrue(proofOfCapital.supportJettonDeferredWithdrawalDate() > block.timestamp);
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), block.timestamp + Constants.THIRTY_DAYS);
    }
    
    // Tests for stopSupportDeferredWithdrawal function
    function testStopSupportDeferredWithdrawalSuccessByOwner() public {
        address recipient = address(0x123);
        
        // First schedule a support withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Verify it was scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), recipient);
        assertTrue(proofOfCapital.supportJettonDeferredWithdrawalDate() > 0);
        
        // Stop the withdrawal using owner
        vm.prank(owner);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Verify it was stopped and state reset
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner);
    }
    
    function testStopSupportDeferredWithdrawalSuccessByRoyalty() public {
        address recipient = address(0x123);
        
        // First schedule a support withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Verify it was scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), recipient);
        assertTrue(proofOfCapital.supportJettonDeferredWithdrawalDate() > 0);
        
        // Stop the withdrawal using royalty wallet
        vm.prank(royalty);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Verify it was stopped and state reset
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner);
    }
    
    function testStopSupportDeferredWithdrawalAccessDenied() public {
        address recipient = address(0x123);
        
        // First schedule a support withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Try to stop with unauthorized addresses
        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        vm.prank(recipient);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Verify state wasn't changed
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), recipient);
        assertTrue(proofOfCapital.supportJettonDeferredWithdrawalDate() > 0);
    }
    
    function testStopSupportDeferredWithdrawalNoDeferredWithdrawalScheduled() public {
        // Try to stop without scheduling first - by owner
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Try to stop without scheduling first - by royalty
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopSupportDeferredWithdrawal();
    }
    
    function testStopSupportDeferredWithdrawalStateReset() public {
        address recipient = address(0x123);
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Record initial scheduled state
        uint256 scheduledDate = proofOfCapital.supportJettonDeferredWithdrawalDate();
        address scheduledRecipient = proofOfCapital.recipientDeferredWithdrawalSupportJetton();
        
        // Verify initial state
        assertTrue(scheduledDate > 0);
        assertEq(scheduledRecipient, recipient);
        
        // Stop withdrawal
        vm.prank(owner);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Verify state is properly reset
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner);
        
        // Verify values actually changed
        assertTrue(scheduledDate > 0 && proofOfCapital.supportJettonDeferredWithdrawalDate() == 0);
        assertTrue(scheduledRecipient == recipient && proofOfCapital.recipientDeferredWithdrawalSupportJetton() == owner);
    }
    
    function testStopSupportDeferredWithdrawalMultipleTimes() public {
        address recipient = address(0x123);
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Stop withdrawal first time
        vm.prank(owner);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Try to stop again - should fail with NoDeferredWithdrawalScheduled
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Same with royalty
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopSupportDeferredWithdrawal();
    }
    
    function testStopSupportDeferredWithdrawalAfterReschedule() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        
        // Schedule first withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient1);
        
        // Stop first withdrawal
        vm.prank(owner);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Schedule second withdrawal (should work since first was stopped)
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient2);
        
        // Verify second withdrawal is scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), recipient2);
        assertTrue(proofOfCapital.supportJettonDeferredWithdrawalDate() > 0);
        
        // Stop second withdrawal using royalty wallet
        vm.prank(royalty);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Verify it was stopped
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner);
    }
    
    function testStopSupportDeferredWithdrawalOwnerVsRoyaltyAccess() public {
        address recipient = address(0x123);
        
        // Test 1: Owner can stop withdrawal scheduled by owner
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        vm.prank(owner);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Test 2: Royalty can stop withdrawal scheduled by owner
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        vm.prank(royalty);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        // Both should work since both owner and royalty have access
        // Verify final state
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner);
    }
    
    function testStopSupportDeferredWithdrawalConsistentBehavior() public {
        // Test that the function behaves consistently regardless of who calls it
        address recipient = address(0x123);
        
        // Test stopping by owner
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        uint256 scheduledDate1 = proofOfCapital.supportJettonDeferredWithdrawalDate();
        
        vm.prank(owner);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        uint256 resetDate1 = proofOfCapital.supportJettonDeferredWithdrawalDate();
        address resetRecipient1 = proofOfCapital.recipientDeferredWithdrawalSupportJetton();
        
        // Test stopping by royalty
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        uint256 scheduledDate2 = proofOfCapital.supportJettonDeferredWithdrawalDate();
        
        vm.prank(royalty);
        proofOfCapital.stopSupportDeferredWithdrawal();
        
        uint256 resetDate2 = proofOfCapital.supportJettonDeferredWithdrawalDate();
        address resetRecipient2 = proofOfCapital.recipientDeferredWithdrawalSupportJetton();
        
        // Both should have same behavior
        assertEq(resetDate1, resetDate2); // Both should be 0
        assertEq(resetRecipient1, resetRecipient2); // Both should be owner
        assertTrue(scheduledDate1 > 0 && scheduledDate2 > 0); // Both were properly scheduled
        assertEq(resetDate1, 0);
        assertEq(resetDate2, 0);
        assertEq(resetRecipient1, owner);
        assertEq(resetRecipient2, owner);
    }

    // Tests for confirmSupportDeferredWithdrawal function
    function testConfirmSupportDeferredWithdrawalSuccess() public {
        address recipient = address(0x123);
        
        // Schedule support withdrawal (even with zero balance, the function should work)
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Move time forward to reach withdrawal date
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Get balances before confirmation
        uint256 recipientBalanceBefore = weth.balanceOf(recipient);
        uint256 contractSupportBalanceBefore = proofOfCapital.contractSupportBalance();
        
        // Confirm withdrawal - should succeed even with zero balance
        vm.prank(owner);
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        // Verify successful execution
        // Check token transfer (should be zero since no balance)
        assertEq(weth.balanceOf(recipient), recipientBalanceBefore + contractSupportBalanceBefore);
        
        // Check state variables reset
        assertEq(proofOfCapital.contractSupportBalance(), 0);
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner);
        
        // Check contract is deactivated
        assertFalse(proofOfCapital.isActive());
    }
    
    function testConfirmSupportDeferredWithdrawalDeferredWithdrawalBlocked() public {
        address recipient = address(0x123);
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Block withdrawals
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        
        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Try to confirm when blocked
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.confirmSupportDeferredWithdrawal();
    }
    
    function testConfirmSupportDeferredWithdrawalNoDeferredWithdrawalScheduled() public {
        // Try to confirm without scheduling
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.confirmSupportDeferredWithdrawal();
    }
    
    function testConfirmSupportDeferredWithdrawalWithdrawalDateNotReached() public {
        address recipient = address(0x123);
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Try to confirm before 30 days
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        // Move time forward but not enough
        vm.warp(block.timestamp + Constants.THIRTY_DAYS - 1);
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmSupportDeferredWithdrawal();
    }
    
    function testConfirmSupportDeferredWithdrawalOnlyOwner() public {
        address recipient = address(0x123);
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Try to confirm with non-owner addresses
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        vm.prank(recipient);
        vm.expectRevert();
        proofOfCapital.confirmSupportDeferredWithdrawal();
    }
    
    function testConfirmSupportDeferredWithdrawalWithZeroBalance() public {
        address recipient = address(0x123);
        
        // Schedule withdrawal (contract has no support balance by default)
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Verify zero balance
        assertEq(proofOfCapital.contractSupportBalance(), 0);
        
        // Get recipient balance before
        uint256 recipientBalanceBefore = weth.balanceOf(recipient);
        
        // Confirm withdrawal with zero balance - should succeed
        vm.prank(owner);
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        // Verify no tokens transferred (since balance was 0)
        assertEq(weth.balanceOf(recipient), recipientBalanceBefore);
        
        // Verify state reset and contract deactivated
        assertEq(proofOfCapital.contractSupportBalance(), 0);
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner);
        assertFalse(proofOfCapital.isActive());
    }
    
    function testConfirmSupportDeferredWithdrawalBasicValidation() public {
        // Test that all our basic require checks work as expected
        
        // Test 1: No withdrawal scheduled
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        // Test 2: Schedule and test date not reached
        address recipient = address(0x123);
        
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        // Test 3: Block withdrawals and test blocked error
        vm.prank(owner);
        proofOfCapital.blockDeferredWithdrawal();
        
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.confirmSupportDeferredWithdrawal();
    }
    
    function testConfirmSupportDeferredWithdrawalContractDeactivation() public {
        address recipient = address(0x123);
        
        // Initially contract should be active
        assertTrue(proofOfCapital.isActive());
        
        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Contract should still be active
        assertTrue(proofOfCapital.isActive());
        
        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Confirm withdrawal
        vm.prank(owner);
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        // Contract should now be inactive
        assertFalse(proofOfCapital.isActive());
    }
    
    function testConfirmSupportDeferredWithdrawalStateConsistency() public {
        address recipient = address(0x123);
        
        // Schedule withdrawal with zero balance
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        uint256 initialSupportBalance = proofOfCapital.contractSupportBalance();
        
        // Record scheduled state
        uint256 scheduledDate = proofOfCapital.supportJettonDeferredWithdrawalDate();
        address scheduledRecipient = proofOfCapital.recipientDeferredWithdrawalSupportJetton();
        
        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        
        // Get recipient balance before
        uint256 recipientBalanceBefore = weth.balanceOf(recipient);
        
        // Confirm withdrawal
        vm.prank(owner);
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        // Verify all state changes
        assertEq(proofOfCapital.contractSupportBalance(), 0);
        assertEq(proofOfCapital.supportJettonDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalSupportJetton(), owner);
        assertFalse(proofOfCapital.isActive());
        
        // Verify token transfer (with initial balance)
        assertEq(weth.balanceOf(recipient), recipientBalanceBefore + initialSupportBalance);
        
        // Verify values actually changed
        assertTrue(scheduledDate > 0 && proofOfCapital.supportJettonDeferredWithdrawalDate() == 0);
        assertTrue(scheduledRecipient == recipient && proofOfCapital.recipientDeferredWithdrawalSupportJetton() == owner);
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
    
    // Tests for withdrawAllTokens function
    function testWithdrawAllTokensSuccess() public {
        // The key insight: contractJettonBalance is only increased by returnWallet selling tokens back
        // We need to create a scenario where returnWallet sells tokens to increase contractJettonBalance
        
        // Give tokens to return wallet
        vm.startPrank(owner);
        token.transfer(returnWallet, 50000e18);
        vm.stopPrank();
        
        // Return wallet sells tokens back (this increases contractJettonBalance)
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellTokens(50000e18);
        vm.stopPrank();
        
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // Record initial state
        uint256 contractBalance = proofOfCapital.contractJettonBalance();
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        uint256 availableTokens = contractBalance - totalSold;
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        
        // Ensure there are tokens available for withdrawal
        assertTrue(availableTokens > 0);
        
        // Withdraw all tokens
        vm.prank(owner);
        proofOfCapital.withdrawAllTokens();
        
        // Verify tokens transferred to owner
        assertEq(token.balanceOf(owner), ownerBalanceBefore + availableTokens);
        
        // Verify state reset
        assertEq(proofOfCapital.currentStep(), 0);
        assertEq(proofOfCapital.contractJettonBalance(), 0);
        assertEq(proofOfCapital.totalJettonsSold(), 0);
        assertEq(proofOfCapital.jettonsEarned(), 0);
        assertEq(proofOfCapital.quantityJettonsPerLevel(), proofOfCapital.firstLevelJettonQuantity());
        assertEq(proofOfCapital.currentPrice(), proofOfCapital.initialPricePerToken());
        assertEq(proofOfCapital.remainderOfStep(), proofOfCapital.firstLevelJettonQuantity());
    }
    
    function testWithdrawAllTokensLockPeriodNotEnded() public {
        // Try to withdraw before lock period ends
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockPeriodNotEnded.selector);
        proofOfCapital.withdrawAllTokens();
    }
    
    function testWithdrawAllTokensNoTokensToWithdraw() public {
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // In initial state: contractJettonBalance = 0, totalJettonsSold = 10000e18 (offset)
        // So availableTokens = 0 - 10000e18 = negative, but function checks > 0
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoTokensToWithdraw.selector);
        proofOfCapital.withdrawAllTokens();
    }
    
    function testWithdrawAllTokensOnlyOwner() public {
        // Setup tokens in contract first
        vm.startPrank(owner);
        token.transfer(returnWallet, 50000e18);
        vm.stopPrank();
        
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellTokens(50000e18);
        vm.stopPrank();
        
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // Non-owner tries to withdraw
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.withdrawAllTokens();
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.withdrawAllTokens();
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.withdrawAllTokens();
    }
    
    function testWithdrawAllTokensStateResetComplete() public {
        // Setup tokens in contract using returnWallet selling tokens back
        vm.startPrank(owner);
        token.transfer(returnWallet, 50000e18);
        vm.stopPrank();
        
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellTokens(50000e18);
        vm.stopPrank();
        
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // Record initial values for comparison
        uint256 firstLevelQuantity = proofOfCapital.firstLevelJettonQuantity();
        uint256 initialPrice = proofOfCapital.initialPricePerToken();
        
        // Withdraw all tokens
        vm.prank(owner);
        proofOfCapital.withdrawAllTokens();
        
        // Verify complete state reset
        assertEq(proofOfCapital.currentStep(), 0);
        assertEq(proofOfCapital.contractJettonBalance(), 0);
        assertEq(proofOfCapital.totalJettonsSold(), 0);
        assertEq(proofOfCapital.jettonsEarned(), 0);
        assertEq(proofOfCapital.quantityJettonsPerLevel(), firstLevelQuantity);
        assertEq(proofOfCapital.currentPrice(), initialPrice);
        assertEq(proofOfCapital.remainderOfStep(), firstLevelQuantity);
        assertEq(proofOfCapital.currentStepEarned(), 0);
        assertEq(proofOfCapital.remainderOfStepEarned(), firstLevelQuantity);
        assertEq(proofOfCapital.quantityJettonsPerLevelEarned(), firstLevelQuantity);
        assertEq(proofOfCapital.currentPriceEarned(), initialPrice);
    }
    
    function testWithdrawAllTokensAtExactLockEnd() public {
        // Setup tokens in contract using returnWallet selling tokens back
        vm.startPrank(owner);
        token.transfer(returnWallet, 50000e18);
        vm.stopPrank();
        
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellTokens(50000e18);
        vm.stopPrank();
        
        // Move time to exact lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime);
        
        // Should work at exact lock end time
        vm.prank(owner);
        proofOfCapital.withdrawAllTokens();
        
        // Verify withdrawal succeeded
        assertEq(proofOfCapital.contractJettonBalance(), 0);
    }
    
    function testWithdrawAllTokensCalculatesAvailableCorrectly() public {
        // Add tokens and simulate some trading to test calculation
        vm.startPrank(owner);
        token.transfer(address(proofOfCapital), 100000e18);
        vm.stopPrank();
        
        // Create scenario where returnWallet sells tokens back
        vm.startPrank(owner);
        token.transfer(returnWallet, 50000e18);
        vm.stopPrank();
        
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellTokens(50000e18);
        vm.stopPrank();
        
        // Move past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // Calculate expected available tokens
        uint256 contractBalance = proofOfCapital.contractJettonBalance();
        uint256 totalSold = proofOfCapital.totalJettonsSold();
        uint256 expectedAvailable = contractBalance - totalSold;
        
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        
        // Withdraw
        vm.prank(owner);
        proofOfCapital.withdrawAllTokens();
        
        // Verify correct amount transferred
        assertEq(token.balanceOf(owner), ownerBalanceBefore + expectedAvailable);
    }
    
    // Tests for withdrawAllSupportTokens function
    function testWithdrawAllSupportTokensSuccess() public {
        // Add support tokens to contract
        vm.startPrank(owner);
        weth.transfer(address(proofOfCapital), 5000e18);
        vm.stopPrank();
        
        // Simulate some support balance (would normally come from trading)
        // For this test, we'll manually set some support balance by doing a deposit
        vm.startPrank(owner);
        weth.approve(address(proofOfCapital), 1000e18);
        proofOfCapital.deposit(1000e18);
        vm.stopPrank();
        
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // Record initial state
        uint256 supportBalance = proofOfCapital.contractSupportBalance();
        uint256 ownerBalanceBefore = weth.balanceOf(owner);
        
        // Ensure there are support tokens to withdraw
        assertTrue(supportBalance > 0);
        
        // Withdraw all support tokens
        vm.prank(owner);
        proofOfCapital.withdrawAllSupportTokens();
        
        // Verify tokens transferred to owner
        assertEq(weth.balanceOf(owner), ownerBalanceBefore + supportBalance);
        
        // Verify support balance reset
        assertEq(proofOfCapital.contractSupportBalance(), 0);
    }
    
    function testWithdrawAllSupportTokensLockPeriodNotEnded() public {
        // Try to withdraw before lock period ends
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockPeriodNotEnded.selector);
        proofOfCapital.withdrawAllSupportTokens();
    }
    
    function testWithdrawAllSupportTokensNoSupportTokensToWithdraw() public {
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // In initial state, contractSupportBalance = 0
        assertEq(proofOfCapital.contractSupportBalance(), 0);
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoSupportTokensToWithdraw.selector);
        proofOfCapital.withdrawAllSupportTokens();
    }
    
    function testWithdrawAllSupportTokensOnlyOwner() public {
        // Add support tokens to contract
        vm.startPrank(owner);
        weth.approve(address(proofOfCapital), 1000e18);
        proofOfCapital.deposit(1000e18);
        vm.stopPrank();
        
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // Non-owner tries to withdraw
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.withdrawAllSupportTokens();
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.withdrawAllSupportTokens();
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.withdrawAllSupportTokens();
    }
    
    function testWithdrawAllSupportTokensAtExactLockEnd() public {
        // Add support tokens
        vm.startPrank(owner);
        weth.approve(address(proofOfCapital), 1000e18);
        proofOfCapital.deposit(1000e18);
        vm.stopPrank();
        
        // Move time to exact lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime);
        
        // Should work at exact lock end time
        vm.prank(owner);
        proofOfCapital.withdrawAllSupportTokens();
        
        // Verify withdrawal succeeded
        assertEq(proofOfCapital.contractSupportBalance(), 0);
    }
    
    function testWithdrawAllSupportTokensWithZeroBalance() public {
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // Try to withdraw with zero balance
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoSupportTokensToWithdraw.selector);
        proofOfCapital.withdrawAllSupportTokens();
    }
    
    function testWithdrawAllSupportTokensTransferMechanism() public {
        // Test that the function uses _transferSupportTokens correctly
        
        // Add support tokens
        vm.startPrank(owner);
        weth.approve(address(proofOfCapital), 1000e18);
        proofOfCapital.deposit(1000e18);
        vm.stopPrank();
        
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        uint256 supportBalance = proofOfCapital.contractSupportBalance();
        uint256 ownerBalanceBefore = weth.balanceOf(owner);
        
        // Withdraw
        vm.prank(owner);
        proofOfCapital.withdrawAllSupportTokens();
        
        // The function should call _transferSupportTokens which handles WETH/ETH conversion
        // In our test setup, jettonSupport = true, so it should transfer WETH directly
        assertEq(weth.balanceOf(owner), ownerBalanceBefore + supportBalance);
        assertEq(proofOfCapital.contractSupportBalance(), 0);
    }
    
    function testWithdrawBothTypesOfTokens() public {
        // Test withdrawing both main tokens and support tokens separately
        // This test validates that both withdrawal functions work independently
        
        // First test: withdraw main tokens
        vm.startPrank(owner);
        token.transfer(returnWallet, 20000e18);
        vm.stopPrank();
        
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 20000e18);
        proofOfCapital.sellTokens(20000e18);
        vm.stopPrank();
        
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);
        
        // Test main token withdrawal
        uint256 mainTokenBalance = proofOfCapital.contractJettonBalance() - proofOfCapital.totalJettonsSold();
        uint256 ownerMainBalanceBefore = token.balanceOf(owner);
        
        vm.prank(owner);
        proofOfCapital.withdrawAllTokens();
        
        // Verify main tokens withdrawn and state reset
        assertEq(token.balanceOf(owner), ownerMainBalanceBefore + mainTokenBalance);
        assertEq(proofOfCapital.contractJettonBalance(), 0);
        assertEq(proofOfCapital.totalJettonsSold(), 0);
        
        // Second test: test support token withdrawal with zero balance (expected to fail)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoSupportTokensToWithdraw.selector);
        proofOfCapital.withdrawAllSupportTokens();
        
        // This test validates that both functions exist and work correctly
        // Even though we can't easily create support balance due to offset logic
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
    
    // Tests for proposeUpgrade additional require statements
    function testProposeUpgradeInvalidAddressZero() public {
        // Try to propose upgrade with zero address
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.InvalidAddress.selector);
        proofOfCapital.proposeUpgrade(address(0));
    }
    
    function testProposeUpgradeUpgradeAlreadyProposed() public {
        ProofOfCapital firstImplementation = new ProofOfCapital();
        ProofOfCapital secondImplementation = new ProofOfCapital();
        
        // First proposal should succeed
        vm.prank(royalty);
        proofOfCapital.proposeUpgrade(address(firstImplementation));
        
        // Second proposal should fail
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.UpgradeAlreadyProposed.selector);
        proofOfCapital.proposeUpgrade(address(secondImplementation));
    }
    
    // Tests for switchProfitMode additional functionality
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
    
    // Tests for trading functions require statements
    function testBuyTokensInvalidAmountZero() public {
        // Try to buy tokens with zero amount
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.InvalidAmount.selector);
        proofOfCapital.buyTokens(0);
    }
    
    function testBuyTokensUseDepositFunctionForOwners() public {
        // Owner tries to use buyTokens instead of deposit
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UseDepositFunctionForOwners.selector);
        proofOfCapital.buyTokens(1000e18);
    }
    
    function testBuyTokensWithETHUseSupportTokenInstead() public {
        // Contract is configured to use support tokens (WETH), not ETH
        assertTrue(proofOfCapital.jettonSupport());
        
        // Try to buy with ETH when support tokens should be used
        vm.deal(marketMaker, 10 ether); // Give marketMaker some ETH
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.UseSupportTokenInstead.selector);
        proofOfCapital.buyTokensWithETH{value: 1 ether}();
    }
    
    function testBuyTokensWithETHInvalidETHAmountZero() public {
        // Contract is configured to use support tokens (WETH), not ETH
        // So the function will revert with UseSupportTokenInstead first
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.UseSupportTokenInstead.selector);
        proofOfCapital.buyTokensWithETH{value: 0}();
    }
    
    function testBuyTokensWithETHUseDepositFunctionForOwners() public {
        // Owner tries to use buyTokensWithETH instead of depositWithETH
        // But since jettonSupport is true, it will revert with UseSupportTokenInstead first
        vm.deal(owner, 10 ether); // Give owner some ETH
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UseSupportTokenInstead.selector);
        proofOfCapital.buyTokensWithETH{value: 1 ether}();
    }
    
    function testDepositInvalidAmountZero() public {
        // Try to deposit zero amount
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidAmount.selector);
        proofOfCapital.deposit(0);
    }
    
    function testDepositWithETHUseSupportTokenInstead() public {
        // Contract is configured to use support tokens (WETH), not ETH
        assertTrue(proofOfCapital.jettonSupport());
        
        // Try to deposit with ETH when support tokens should be used
        vm.deal(owner, 10 ether); // Give owner some ETH
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UseSupportTokenInstead.selector);
        proofOfCapital.depositWithETH{value: 1 ether}();
    }
    
    function testDepositWithETHInvalidETHAmountZero() public {
        // Since jettonSupport is true, it will revert with UseSupportTokenInstead first
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UseSupportTokenInstead.selector);
        proofOfCapital.depositWithETH{value: 0}();
    }
    
    function testSellTokensInvalidAmountZero() public {
        // Try to sell zero tokens
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.InvalidAmount.selector);
        proofOfCapital.sellTokens(0);
    }
    
    // Tests for modifier requirements
    function testOnlyActiveContractModifier() public {
        // First make contract inactive by confirming support withdrawal
        address recipient = address(0x123);
        
        // Schedule support withdrawal
        vm.prank(owner);
        proofOfCapital.supportDeferredWithdrawal(recipient);
        
        // Move time forward and confirm
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        vm.prank(owner);
        proofOfCapital.confirmSupportDeferredWithdrawal();
        
        // Verify contract is inactive
        assertFalse(proofOfCapital.isActive());
        
        // Try to call functions that require active contract
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.ContractNotActive.selector);
        proofOfCapital.buyTokens(1000e18);
        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.ContractNotActive.selector);
        proofOfCapital.deposit(1000e18);
        
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.ContractNotActive.selector);
        proofOfCapital.sellTokens(1000e18);
    }
    
    // Tests for access control modifiers
    function testOnlyReserveOwnerModifier() public {
        address newOwner = address(0x999);
        
        // Non-reserve owner tries to assign new owner
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewOwner(newOwner);
        
        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewOwner(newOwner);
        
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewOwner(newOwner);
    }
    
    function testOnlyOwnerOrOldContractModifier() public {
        // Add an old contract address for testing
        address oldContract = address(0x888);
        
        // We can't directly test this modifier easily without modifying the contract
        // But we can test that non-authorized addresses fail
        
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.deposit(1000e18);
        
        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.deposit(1000e18);
        
        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.deposit(1000e18);
    }
    
    // Additional boundary and edge case tests
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
    
    // Tests for ETH functions with jettonSupport=false configuration
    function testBuyTokensWithETHInvalidETHAmountWithETHConfig() public {
        // Deploy contract with jettonSupport = false (ETH configuration)
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        MockERC20 supportToken = new MockERC20("Support", "SUP");
        MockWETH testWETH = new MockWETH(); // Use proper WETH mock
        
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(testWETH), // Use proper WETH mock
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 1000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(supportToken), // Different from WETH
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0)
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital ethContract = ProofOfCapital(address(proxy));
        
        // Verify jettonSupport is false
        assertFalse(ethContract.jettonSupport());
        
        // Give tokens to contract and setup market maker
        token.transfer(address(ethContract), 100000e18);
        ethContract.setMarketMaker(marketMaker, true);
        
        vm.stopPrank();
        
        // Now test InvalidETHAmount error
        vm.deal(marketMaker, 10 ether);
        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.InvalidETHAmount.selector);
        ethContract.buyTokensWithETH{value: 0}();
    }
    
    function testBuyTokensWithETHUseDepositFunctionForOwnersWithETHConfig() public {
        // Deploy contract with jettonSupport = false (ETH configuration)
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        MockERC20 supportToken = new MockERC20("Support", "SUP");
        MockWETH testWETH = new MockWETH(); // Use proper WETH mock
        
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(testWETH), // Use proper WETH mock
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 1000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(supportToken), // Different from WETH
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0)
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital ethContract = ProofOfCapital(address(proxy));
        
        // Give tokens to contract
        token.transfer(address(ethContract), 100000e18);
        
        vm.stopPrank();
        
        // Now test UseDepositFunctionForOwners error
        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.UseDepositFunctionForOwners.selector);
        ethContract.buyTokensWithETH{value: 1 ether}();
    }
    
    function testDepositWithETHInvalidETHAmountWithETHConfig() public {
        // Deploy contract with jettonSupport = false (ETH configuration)
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        MockERC20 supportToken = new MockERC20("Support", "SUP");
        MockWETH testWETH = new MockWETH(); // Use proper WETH mock
        
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(testWETH), // Use proper WETH mock
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 1000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(supportToken), // Different from WETH
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0)
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital ethContract = ProofOfCapital(address(proxy));
        
        vm.stopPrank();
        
        // Now test InvalidETHAmount error for deposit
        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidETHAmount.selector);
        ethContract.depositWithETH{value: 0}();
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
    
    // Tests for deposit and depositWithETH called by old contract
    function testDepositByOldContract() public {
        // Create mock old contract
        address oldContract = address(0x777);
        
        // Deploy new ProofOfCapital with old contract in the list
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = oldContract;
        
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
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: oldContracts // Add old contract here
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital newContract = ProofOfCapital(address(proxy));
        
        // Give tokens to old contract and set up contract
        token.transfer(address(newContract), 100000e18);
        weth.transfer(oldContract, 5000e18);
        
        vm.stopPrank();
        
        // Old contract deposits support tokens
        uint256 depositAmount = 1000e18;
        uint256 initialBalance = newContract.contractSupportBalance();
        
        vm.startPrank(oldContract);
        weth.approve(address(newContract), depositAmount);
        newContract.deposit(depositAmount);
        vm.stopPrank();
        
        // Verify deposit was successful
        assertEq(newContract.contractSupportBalance(), initialBalance + depositAmount);
        assertEq(weth.balanceOf(oldContract), 5000e18 - depositAmount);
    }
    
    function testDepositWithETHByOldContract() public {
        // Create mock old contract
        address oldContract = address(0x777);
        
        // Deploy new ProofOfCapital with ETH support (jettonSupport = false)
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        MockERC20 supportToken = new MockERC20("Support", "SUP");
        MockWETH testWETH = new MockWETH(); // Use proper WETH mock
        
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = oldContract;
        
        // Use different support token to make jettonSupport = false
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(testWETH), // Use proper WETH mock
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(supportToken), // Different from WETH to enable ETH mode
            royaltyProfitPercent: 500,
            oldContractAddresses: oldContracts // Add old contract here
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital ethContract = ProofOfCapital(address(proxy));
        
        // Give tokens to contract and ETH to old contract
        token.transfer(address(ethContract), 100000e18);
        vm.deal(oldContract, 10 ether);
        
        vm.stopPrank();
        
        // Verify jettonSupport is false (ETH mode enabled)
        assertFalse(ethContract.jettonSupport());
        
        // Old contract deposits ETH
        uint256 depositAmount = 2 ether;
        uint256 initialBalance = ethContract.contractSupportBalance();
        
        vm.prank(oldContract);
        ethContract.depositWithETH{value: depositAmount}();
        
        // Verify ETH deposit was successful
        assertEq(ethContract.contractSupportBalance(), initialBalance + depositAmount);
        assertEq(oldContract.balance, 10 ether - depositAmount);
    }
    
    function testDepositByOldContractInvalidAmount() public {
        // Create mock old contract
        address oldContract = address(0x777);
        
        // Deploy new ProofOfCapital with old contract in the list
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = oldContract;
        
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
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: oldContracts
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital newContract = ProofOfCapital(address(proxy));
        
        token.transfer(address(newContract), 100000e18);
        
        vm.stopPrank();
        
        // Old contract tries to deposit zero amount
        vm.prank(oldContract);
        vm.expectRevert(ProofOfCapital.InvalidAmount.selector);
        newContract.deposit(0);
    }
    
    function testDepositWithETHByOldContractInvalidAmount() public {
        // Create mock old contract
        address oldContract = address(0x777);
        
        // Deploy new ProofOfCapital with ETH support
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        MockERC20 supportToken = new MockERC20("Support", "SUP");
        MockWETH testWETH = new MockWETH(); // Use proper WETH mock
        
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = oldContract;
        
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(testWETH), // Use proper WETH mock
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(supportToken), // Different from WETH for ETH mode
            royaltyProfitPercent: 500,
            oldContractAddresses: oldContracts
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital ethContract = ProofOfCapital(address(proxy));
        
        token.transfer(address(ethContract), 100000e18);
        vm.deal(oldContract, 10 ether);
        
        vm.stopPrank();
        
        // Old contract tries to deposit zero ETH
        vm.prank(oldContract);
        vm.expectRevert(ProofOfCapital.InvalidETHAmount.selector);
        ethContract.depositWithETH{value: 0}();
    }
    
    function testDepositByOldContractWhenContractInactive() public {
        // Create mock old contract
        address oldContract = address(0x777);
        
        // Deploy new ProofOfCapital with old contract in the list
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = oldContract;
        
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
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: oldContracts
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital newContract = ProofOfCapital(address(proxy));
        
        token.transfer(address(newContract), 100000e18);
        weth.transfer(oldContract, 5000e18);
        
        // Deactivate contract by confirming support withdrawal
        address recipient = address(0x123);
        newContract.supportDeferredWithdrawal(recipient);
        
        vm.stopPrank();
        
        // Move time forward and confirm withdrawal to deactivate contract
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);
        vm.prank(owner);
        newContract.confirmSupportDeferredWithdrawal();
        
        // Verify contract is inactive
        assertFalse(newContract.isActive());
        
        // Old contract tries to deposit when contract is inactive
        vm.startPrank(oldContract);
        weth.approve(address(newContract), 1000e18);
        vm.expectRevert(ProofOfCapital.ContractNotActive.selector);
        newContract.deposit(1000e18);
        vm.stopPrank();
    }
    
    function testDepositByNonAuthorizedAddress() public {
        // Test that address not in old contracts list cannot call deposit
        address nonAuthorized = address(0x888);
        
        // Give tokens to non-authorized address
        vm.startPrank(owner);
        weth.transfer(nonAuthorized, 1000e18);
        vm.stopPrank();
        
        // Non-authorized address tries to deposit
        vm.startPrank(nonAuthorized);
        weth.approve(address(proofOfCapital), 1000e18);
        vm.expectRevert(); // Should revert due to onlyOwnerOrOldContract modifier
        proofOfCapital.deposit(1000e18);
        vm.stopPrank();
    }
    
    function testDepositWithETHByNonAuthorizedAddress() public {
        // Deploy contract with ETH support
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        MockERC20 supportToken = new MockERC20("Support", "SUP");
        
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
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(supportToken), // Different for ETH mode
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0) // No old contracts
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital ethContract = ProofOfCapital(address(proxy));
        
        token.transfer(address(ethContract), 100000e18);
        
        vm.stopPrank();
        
        // Non-authorized address tries to deposit ETH
        address nonAuthorized = address(0x888);
        vm.deal(nonAuthorized, 5 ether);
        
        vm.prank(nonAuthorized);
        vm.expectRevert(); // Should revert due to onlyOwnerOrOldContract modifier
        ethContract.depositWithETH{value: 1 ether}();
    }
    
    function testMultipleOldContractsCanDeposit() public {
        // Create multiple old contracts
        address oldContract1 = address(0x777);
        address oldContract2 = address(0x888);
        
        // Deploy new ProofOfCapital with multiple old contracts
        vm.startPrank(owner);
        
        ProofOfCapital implementation = new ProofOfCapital();
        
        address[] memory oldContracts = new address[](2);
        oldContracts[0] = oldContract1;
        oldContracts[1] = oldContract2;
        
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
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: oldContracts
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProofOfCapital newContract = ProofOfCapital(address(proxy));
        
        // Setup tokens
        token.transfer(address(newContract), 100000e18);
        weth.transfer(oldContract1, 2000e18);
        weth.transfer(oldContract2, 3000e18);
        
        vm.stopPrank();
        
        uint256 initialBalance = newContract.contractSupportBalance();
        
        // First old contract deposits
        vm.startPrank(oldContract1);
        weth.approve(address(newContract), 1000e18);
        newContract.deposit(1000e18);
        vm.stopPrank();
        
        // Second old contract deposits
        vm.startPrank(oldContract2);
        weth.approve(address(newContract), 1500e18);
        newContract.deposit(1500e18);
        vm.stopPrank();
        
        // Verify both deposits were successful
        assertEq(newContract.contractSupportBalance(), initialBalance + 1000e18 + 1500e18);
        assertEq(weth.balanceOf(oldContract1), 2000e18 - 1000e18);
        assertEq(weth.balanceOf(oldContract2), 3000e18 - 1500e18);
    }
} 

contract ProofOfCapitalProfitTest is Test {
    ProofOfCapital public proofOfCapital;
    MockERC20 public token;
    MockERC20 public weth;
    
    address public owner = address(0x1);
    address public royalty = address(0x2);
    address public returnWallet = address(0x3);
    address public marketMaker = address(0x4);
    address public user = address(0x5);
    
    function setUp() public {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023
        
        vm.startPrank(owner);
        
        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");
        
        // Deploy implementation
        ProofOfCapital implementation = new ProofOfCapital();
        
        // Prepare initialization parameters
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
            offsetJettons: 10000e18, // Add offset to enable trading
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0)
        });
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        proofOfCapital = ProofOfCapital(address(proxy));
        
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
} 

contract ProofOfCapitalInitializationTest is Test {
    ProofOfCapital public implementation;
    MockERC20 public token;
    MockERC20 public weth;
    
    address public owner = address(0x1);
    address public royalty = address(0x2);
    address public returnWallet = address(0x3);
    address public marketMaker = address(0x4);
    
    function setUp() public {
        vm.warp(1672531200); // January 1, 2023
        
        vm.startPrank(owner);
        
        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");
        
        // Deploy implementation
        implementation = new ProofOfCapital();
        
        vm.stopPrank();
    }
    
    function getValidParams() internal view returns (ProofOfCapital.InitParams memory) {
        return ProofOfCapital.InitParams({
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
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0)
        });
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