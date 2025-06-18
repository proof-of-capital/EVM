// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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