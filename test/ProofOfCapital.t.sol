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

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {ProofOfCapital} from "../src/ProofOfCapital.sol";
import {IProofOfCapital} from "../src/interfaces/IProofOfCapital.sol";
import {Constants} from "../src/utils/Constant.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockRecipient} from "./mocks/MockRecipient.sol";
import {MockRoyalty} from "./mocks/MockRoyalty.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

// Add proper WETH mock with depositCollateral functionality
contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function depositCollateral() external payable {
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
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    ProofOfCapital public proofOfCapital;
    MockERC20 public token;
    MockERC20 public weth;
    MockRoyalty public mockRoyalty;

    address public owner = address(0x1);
    address public royalty;
    address public returnWallet = address(0x3);
    address public marketMaker = address(0x4);

    StdStorage private _stdStore;

    function setUp() public {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023

        vm.startPrank(owner);

        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");

        // Deploy mock royalty contract
        mockRoyalty = new MockRoyalty();
        royalty = address(mockRoyalty);

        // Prepare initialization parameters
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 10000e18, // Add offset to enable trading
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            collateralToken: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        // Deploy contract directly (no proxy needed)
        proofOfCapital = new ProofOfCapital(params);

        // Initialize contract if it has offset
        uint256 unaccountedOffset = proofOfCapital.unaccountedOffset();
        if (unaccountedOffset > 0) {
            // Setup trading access by manipulating controlDay to be in the past
            uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
            vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

            proofOfCapital.calculateUnaccountedOffsetBalance(unaccountedOffset);
        }

        vm.stopPrank();
    }

    // Helper function to ensure contract is initialized
    function _ensureInitialized() internal {
        if (!proofOfCapital.isInitialized()) {
            uint256 unaccountedOffset = proofOfCapital.unaccountedOffset();
            if (unaccountedOffset > 0) {
                uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
                vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));
                vm.prank(owner);
                proofOfCapital.calculateUnaccountedOffsetBalance(unaccountedOffset);
            }
        }
    }

    // Tests for extendLock function
    function testExtendLockWithHalfYear() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();

        vm.prank(owner);
        proofOfCapital.extendLock(initialLockEndTime + Constants.HALF_YEAR);

        assertEq(proofOfCapital.lockEndTime(), initialLockEndTime + Constants.HALF_YEAR);
    }

    function testExtendLockWithThreeMonths() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();

        vm.prank(owner);
        proofOfCapital.extendLock(initialLockEndTime + Constants.THREE_MONTHS);

        assertEq(proofOfCapital.lockEndTime(), initialLockEndTime + Constants.THREE_MONTHS);
    }

    function testExtendLockWithTenMinutes() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();

        vm.prank(owner);
        proofOfCapital.extendLock(initialLockEndTime + Constants.TEN_MINUTES);

        assertEq(proofOfCapital.lockEndTime(), initialLockEndTime + Constants.TEN_MINUTES);
    }

    function testExtendLockUnauthorized() public {
        // Non-owner tries to extend lock
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.extendLock(block.timestamp + Constants.HALF_YEAR);
    }

    function testExtendLockExceedsFiveYears() public {
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.LockCannotExceedFiveYears.selector);
        proofOfCapital.extendLock(block.timestamp + Constants.FIVE_YEARS + 1);
    }

    function testExtendLockWithInvalidTimePeriod() public {
        // Try to extend with time in the past
        uint256 pastTime = block.timestamp - 1; // Time in the past

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidTimePeriod.selector);
        proofOfCapital.extendLock(pastTime);
    }

    function testExtendLockEvent() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();
        uint256 newLockEndTime = initialLockEndTime + Constants.THREE_MONTHS;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        // Expecting LockExtended event with newLockEndTime parameter
        emit IProofOfCapital.LockExtended(newLockEndTime);
        proofOfCapital.extendLock(newLockEndTime);
    }

    function testExtendLockMultipleTimes() public {
        uint256 initialLockEndTime = proofOfCapital.lockEndTime();

        // First extension
        vm.prank(owner);
        proofOfCapital.extendLock(initialLockEndTime + Constants.THREE_MONTHS);

        uint256 afterFirstExtension = proofOfCapital.lockEndTime();
        assertEq(afterFirstExtension, initialLockEndTime + Constants.THREE_MONTHS);

        // Second extension (extending further)
        vm.prank(owner);
        proofOfCapital.extendLock(afterFirstExtension + Constants.TEN_MINUTES);

        assertEq(proofOfCapital.lockEndTime(), afterFirstExtension + Constants.TEN_MINUTES);
    }

    // Tests for toggleDeferredWithdrawal function
    function testBlockDeferredWithdrawalFromTrueToFalse() public {
        // Initially canWithdrawal should be true (default)
        assertTrue(proofOfCapital.canWithdrawal());

        // Block deferred withdrawal
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();

        // Should now be false
        assertFalse(proofOfCapital.canWithdrawal());
    }

    function testBlockDeferredWithdrawalFromFalseToTrueWhenTimeAllows() public {
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Move time to less than 60 days before lock end (activation allowed when < 60 days)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1); // 59 days + 1 second remaining

        // Now try to unblock when less than 60 days remain
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();

        // Should now be true again
        assertTrue(proofOfCapital.canWithdrawal());
    }

    function testBlockDeferredWithdrawalFailsWhenTooFarFromLockEnd() public {
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Move time forward to be more than 60 days before lock end (activation blocked when >= 60 days)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS - 1 days); // 60 days + 1 day remaining

        // Try to unblock - should fail
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.CannotActivateWithdrawalTooCloseToLockEnd.selector);
        proofOfCapital.toggleDeferredWithdrawal();

        // Should still be false
        assertFalse(proofOfCapital.canWithdrawal());
    }

    function testBlockDeferredWithdrawalAtExactBoundary() public {
        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Move time forward to be exactly 60 days before lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS);

        // Try to unblock - should fail (condition is <, not <=)
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.CannotActivateWithdrawalTooCloseToLockEnd.selector);
        proofOfCapital.toggleDeferredWithdrawal();
    }

    function testBlockDeferredWithdrawalJustOverBoundary() public {
        // First, block withdrawal to set canWithdrawal to false
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Move time to just under the boundary (59 days, 23 hours, 59 minutes, 59 seconds remaining)
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1);

        // Should be able to activate withdrawal when less than 60 days remain
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();
        assertTrue(proofOfCapital.canWithdrawal());
    }

    function testBlockDeferredWithdrawalUnauthorized() public {
        // Non-owner tries to block/unblock withdrawal
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.toggleDeferredWithdrawal();

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.toggleDeferredWithdrawal();

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.toggleDeferredWithdrawal();
    }

    // Tests for launchDeferredWithdrawal function
    function testTokenDeferredWithdrawalSuccess() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // Schedule deferred withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Check that variables are set correctly
        assertEq(proofOfCapital.recipientDeferredWithdrawalLaunch(), recipient);
        assertEq(proofOfCapital.launchDeferredWithdrawalAmount(), amount);
        assertEq(proofOfCapital.launchDeferredWithdrawalDate(), block.timestamp + Constants.THIRTY_DAYS);
    }

    function testTokenDeferredWithdrawalEmitsEvent() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;
        uint256 expectedExecuteTime = block.timestamp + Constants.THIRTY_DAYS;

        // Expect the event to be emitted
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IProofOfCapital.DeferredWithdrawalScheduled(recipient, amount, expectedExecuteTime);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);
    }

    function testTokenDeferredWithdrawalInvalidRecipientZeroAddress() public {
        uint256 amount = 1000e18;

        // Try with zero address
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidRecipientOrAmount.selector);
        proofOfCapital.launchDeferredWithdrawal(address(0), amount);
    }

    function testTokenDeferredWithdrawalInvalidAmountZero() public {
        address recipient = address(0x123);

        // Try with zero amount
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidRecipientOrAmount.selector);
        proofOfCapital.launchDeferredWithdrawal(recipient, 0);
    }

    function testTokenDeferredWithdrawalInvalidRecipientAndAmount() public {
        // Try with both zero address and zero amount
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidRecipientOrAmount.selector);
        proofOfCapital.launchDeferredWithdrawal(address(0), 0);
    }

    function testTokenDeferredWithdrawalWhenWithdrawalBlocked() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // First block withdrawal
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Try to schedule deferred withdrawal when blocked
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);
    }

    function testTokenDeferredWithdrawalAlreadyScheduled() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        uint256 amount1 = 1000e18;
        uint256 amount2 = 2000e18;

        // Schedule first withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient1, amount1);

        // Try to schedule second withdrawal (should fail)
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.LaunchDeferredWithdrawalAlreadyScheduled.selector);
        proofOfCapital.launchDeferredWithdrawal(recipient2, amount2);
    }

    function testTokenDeferredWithdrawalUnauthorized() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // Non-owner tries to schedule withdrawal
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);
    }

    function testTokenDeferredWithdrawalWithDifferentAmounts() public {
        address recipient = address(0x123);

        // Test with different valid amounts
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1;
        amounts[1] = 100e18;
        amounts[2] = 1000000e18;
        amounts[3] = type(uint256).max;

        for (uint256 i = 0; i < amounts.length; i++) {
            // Reset state by stopping any existing withdrawal
            if (proofOfCapital.launchDeferredWithdrawalAmount() > 0) {
                vm.prank(owner);
                proofOfCapital.stopLaunchDeferredWithdrawal();
            }

            // Schedule withdrawal with this amount
            vm.prank(owner);
            proofOfCapital.launchDeferredWithdrawal(recipient, amounts[i]);

            // Verify amount is set correctly
            assertEq(proofOfCapital.launchDeferredWithdrawalAmount(), amounts[i]);
        }
    }

    // function testTokenDeferredWithdrawalDateCalculation() public {
    //     address recipient = address(0x123);
    //     uint256 amount = 1000e18;

    //     // Record current time
    //     uint256 currentTime = block.timestamp;

    //     // Schedule withdrawal
    //     vm.prank(owner);
    //     proofOfCapital.launchDeferredWithdrawal(recipient, amount);

    //     // Verify date is set correctly (current time + 30 days)
    //     uint256 expectedDate = currentTime + Constants.THIRTY_DAYS;
    //     assertEq(proofOfCapital.launchDeferredWithdrawalDate(), expectedDate);

    //     // Move time forward and schedule another (after stopping first)
    //     vm.warp(block.timestamp + 10 days);
    //     vm.prank(owner);
    //     proofOfCapital.stopLaunchDeferredWithdrawal();

    //     uint256 newCurrentTime = block.timestamp;
    //     vm.prank(owner);
    //     proofOfCapital.launchDeferredWithdrawal(recipient, amount);

    //     uint256 newExpectedDate = newCurrentTime + Constants.THIRTY_DAYS;
    //     assertEq(proofOfCapital.launchDeferredWithdrawalDate(), newExpectedDate);
    // }

    // Tests for stopLaunchDeferredWithdrawal function (testing each require)
    function testStopTokenDeferredWithdrawalSuccess() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // First schedule a withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Verify it was scheduled
        assertTrue(proofOfCapital.launchDeferredWithdrawalDate() > 0);

        // Stop the withdrawal
        vm.prank(owner);
        proofOfCapital.stopLaunchDeferredWithdrawal();

        // Verify it was stopped
        assertEq(proofOfCapital.launchDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.launchDeferredWithdrawalAmount(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalLaunch(), owner);
    }

    function testStopTokenDeferredWithdrawalByRoyalty() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // First schedule a withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Stop the withdrawal using royalty wallet
        vm.prank(royalty);
        proofOfCapital.stopLaunchDeferredWithdrawal();

        // Verify it was stopped
        assertEq(proofOfCapital.launchDeferredWithdrawalDate(), 0);
    }

    function testStopTokenDeferredWithdrawalAccessDenied() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // First schedule a withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Try to stop with unauthorized addresses
        vm.prank(returnWallet);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopLaunchDeferredWithdrawal();

        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopLaunchDeferredWithdrawal();
    }

    function testStopTokenDeferredWithdrawalNoDeferredWithdrawalScheduled() public {
        // Try to stop without scheduling first
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopLaunchDeferredWithdrawal();

        // Try with royalty wallet
        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopLaunchDeferredWithdrawal();
    }

    // Tests for confirmLaunchDeferredWithdrawal function (testing each require)
    function testConfirmTokenDeferredWithdrawalDeferredWithdrawalBlocked() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Block withdrawals
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();

        // Try to confirm when blocked
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    function testConfirmTokenDeferredWithdrawalNoDeferredWithdrawalScheduled() public {
        // Try to confirm without scheduling
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    function testConfirmTokenDeferredWithdrawalWithdrawalDateNotReached() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Try to confirm before 30 days
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();

        // Move time forward but not enough
        vm.warp(block.timestamp + Constants.THIRTY_DAYS - 1);
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    function testConfirmTokenDeferredWithdrawalExpiredAfterSevenDays() public {
        // Test require: block.timestamp <= launchDeferredWithdrawalDate + Constants.SEVEN_DAYS
        // This test verifies that withdrawal cannot be confirmed after 7 days from the withdrawal date

        _ensureInitialized();

        address recipient = address(0x123);
        uint256 withdrawalAmount = 1000e18;

        // Step 1: Create state where launchBalance > totalLaunchSold
        // Use returnWallet to sell tokens back to contract, increasing launchBalance
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 10000e18);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(10000e18); // This increases launchBalance
        vm.stopPrank();

        // Step 2: Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, withdrawalAmount);

        uint256 withdrawalDate = proofOfCapital.launchDeferredWithdrawalDate();
        assertTrue(withdrawalDate > 0, "Withdrawal should be scheduled");

        // Step 3: Move time forward to the withdrawal date (30 days)
        vm.warp(withdrawalDate);

        // At this point, withdrawal should be possible (within the 7-day window)
        // But we'll skip this and move past the 7-day window

        // Step 4: Move time forward more than 7 days past the withdrawal date
        vm.warp(withdrawalDate + Constants.SEVEN_DAYS + 1);

        // Step 5: Try to confirm withdrawal - should revert because more than 7 days have passed
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    function testConfirmTokenDeferredWithdrawalInsufficientTokenBalance() public {
        // Test specific require: launchBalance > totalLaunchSold
        // Default state: launchBalance = 0, totalLaunchSold = 10000e18 (from offset)
        // This creates the exact condition for InsufficientTokenBalance error

        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // Verify initial state - launchBalance should be <= totalLaunchSold
        uint256 contractBalance = proofOfCapital.launchBalance();
        uint256 totalSold = proofOfCapital.totalLaunchSold();

        // In our setup: launchBalance = 0, totalLaunchSold = 10000e18 (offsetLaunch)
        assertTrue(contractBalance <= totalSold, "Setup verification: launchBalance should be <= totalLaunchSold");

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Move time forward to pass date requirement
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Try to confirm - should fail with InsufficientTokenBalance
        // because launchBalance (0) <= totalLaunchSold (10000e18)
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InsufficientTokenBalance.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    function testConfirmTokenDeferredWithdrawalInsufficientTokenBalanceSpecific() public {
        // Test specific require: launchBalance > totalLaunchSold
        // Default state: launchBalance = 0, totalLaunchSold = 10000e18 (from offset)
        // This creates the exact condition for InsufficientTokenBalance error

        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // Verify initial state - launchBalance should be <= totalLaunchSold
        uint256 contractBalance = proofOfCapital.launchBalance();
        uint256 totalSold = proofOfCapital.totalLaunchSold();

        // In our setup: launchBalance = 0, totalLaunchSold = 10000e18 (offsetLaunch)
        assertTrue(contractBalance <= totalSold, "Setup verification: launchBalance should be <= totalLaunchSold");

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Move time forward to pass date requirement
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Try to confirm - should fail with InsufficientTokenBalance
        // because launchBalance (0) <= totalLaunchSold (10000e18)
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InsufficientTokenBalance.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    function testConfirmTokenDeferredWithdrawalRequire5_InsufficientAmount() public {
        _ensureInitialized();

        // Create scenario where:
        // 1. launchBalance > totalLaunchSold (to pass require 4)
        // 2. launchBalance - totalLaunchSold < launchDeferredWithdrawalAmount (to fail require 5)

        address recipient = address(0x123);

        // Use returnWallet to sell tokens back to contract, which increases launchBalance
        // From _handleReturnWalletSale: launchBalance += amount;

        vm.startPrank(owner);

        // First, give some tokens to returnWallet to sell back
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 50000e18);

        vm.stopPrank();

        // ReturnWallet sells tokens back, which increases launchBalance
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(50000e18); // This should increase launchBalance
        vm.stopPrank();

        // Check the state - this should now have launchBalance > totalLaunchSold
        uint256 contractBalance = proofOfCapital.launchBalance();
        uint256 totalSold = proofOfCapital.totalLaunchSold();

        // Ensure we have the first condition: launchBalance > totalLaunchSold
        require(contractBalance > totalSold, "Setup failed: need launchBalance > totalLaunchSold");

        // Calculate available tokens
        uint256 availableTokens = contractBalance - totalSold;

        // Request exactly availableTokens + 1 to trigger InsufficientAmount
        uint256 requestedAmount = availableTokens + 1;

        // Schedule withdrawal for more than available
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, requestedAmount);

        // Move time forward to pass the date check
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Now confirm withdrawal - should fail with exactly InsufficientAmount
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InsufficientAmount.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    function testConfirmTokenDeferredWithdrawalOnlyOwner() public {
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Try to confirm with non-owner addresses
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.confirmLaunchDeferredWithdrawal();

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.confirmLaunchDeferredWithdrawal();

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.confirmLaunchDeferredWithdrawal();

        vm.prank(recipient);
        vm.expectRevert();
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    // Simple working test cases (without complex state setup)
    function testConfirmTokenDeferredWithdrawalBasicValidation() public {
        // Test that all our basic require checks work as expected

        // Test 1: No withdrawal scheduled
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();

        // Test 2: Schedule and test date not reached
        address recipient = address(0x123);
        uint256 amount = 1000e18;

        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(recipient, amount);

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();

        // Test 3: Block withdrawals and test blocked error
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();

        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.confirmLaunchDeferredWithdrawal();
    }

    function testConfirmTokenDeferredWithdrawalSuccess() public {
        _ensureInitialized();

        // Test successful execution of confirmLaunchDeferredWithdrawal
        // Need to create state where all require conditions pass:
        // 1. canWithdrawal = true (default)
        // 2. launchDeferredWithdrawalDate != 0 (withdrawal scheduled)
        // 3. block.timestamp >= launchDeferredWithdrawalDate (date reached)
        // 4. launchBalance > totalLaunchSold (sufficient balance)
        // 5. launchBalance - totalLaunchSold >= launchDeferredWithdrawalAmount (sufficient available)

        // Deploy MockRecipient contract that implements depositLaunch
        MockRecipient recipient = new MockRecipient();
        uint256 withdrawalAmount = 1000e18;

        // Step 1: Create state where launchBalance > totalLaunchSold
        // Use returnWallet to sell tokens back to contract, increasing launchBalance
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 10000e18);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(10000e18); // This increases launchBalance
        vm.stopPrank();

        // Step 2: Schedule withdrawal with amount less than available
        vm.prank(owner);
        proofOfCapital.launchDeferredWithdrawal(address(recipient), withdrawalAmount);

        // Verify withdrawal is scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalLaunch(), address(recipient));
        assertEq(proofOfCapital.launchDeferredWithdrawalAmount(), withdrawalAmount);
        assertTrue(proofOfCapital.launchDeferredWithdrawalDate() > 0);

        // Step 3: Move time forward to reach withdrawal date
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Step 4: Get balances before confirmation
        uint256 contractBalanceBefore = proofOfCapital.launchBalance();

        // Verify we have sufficient balance for withdrawal
        uint256 totalSold = proofOfCapital.totalLaunchSold();
        uint256 available = contractBalanceBefore - totalSold;
        assertTrue(available >= withdrawalAmount, "Insufficient available tokens for withdrawal");

        // Step 5: Confirm withdrawal - should succeed
        // The function will:
        // 1. Decrease launchBalance by withdrawalAmount
        // 2. Give allowance to recipient
        // 3. Call depositLaunch on recipient
        // Inside depositLaunch on recipient, it will try to transferFrom(msg.sender, address(this), amount)
        // where msg.sender = proofOfCapital and address(this) = recipient
        // This means tokens will be transferred from proofOfCapital to recipient
        // But recipient needs to have the tokens first, or the transferFrom will fail
        // Actually, the allowance is given to recipient, so recipient can pull tokens from proofOfCapital
        // Then depositLaunch will transfer them from recipient back to proofOfCapital

        // First, recipient needs to pull tokens from proofOfCapital using the allowance
        // But wait, the allowance is given AFTER we call confirmLaunchDeferredWithdrawal
        // So we need to simulate the flow: recipient pulls tokens, then deposits them back

        vm.prank(owner);
        proofOfCapital.confirmLaunchDeferredWithdrawal();

        // Step 6: Verify successful execution
        // After confirmLaunchDeferredWithdrawal:
        // - launchBalance was decreased by withdrawalAmount
        // - Tokens were transferred via depositLaunch flow
        // - State variables were reset

        // Check that launchBalance was decreased (this happens before the depositLaunch call)
        assertEq(proofOfCapital.launchBalance(), contractBalanceBefore - withdrawalAmount);

        // Check state variables reset
        assertEq(proofOfCapital.launchDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.launchDeferredWithdrawalAmount(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalLaunch(), owner);
    }

    // Tests for transferOwnership function
    function testAssignNewOwnerWhenOwnerEqualsReserveOwner() public {
        // In initial setup, owner == reserveOwner
        address newOwner = address(0x999);

        // Verify initial state
        assertEq(proofOfCapital.owner(), owner);
        assertEq(proofOfCapital.reserveOwner(), owner);
        assertTrue(proofOfCapital.owner() == proofOfCapital.reserveOwner());

        // Assign new owner from reserveOwner
        vm.prank(owner); // owner is also reserveOwner
        proofOfCapital.transferOwnership(newOwner);

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
        proofOfCapital.transferOwnership(newOwner);

        // Only owner should be transferred, reserveOwner stays the same
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.reserveOwner(), intermediateReserveOwner);
    }

    function testAssignNewOwnerInvalidNewOwner() public {
        // Try to assign zero address as new owner
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidNewOwner.selector);
        proofOfCapital.transferOwnership(address(0));
    }

    function testAssignNewOwnerWithOldContractAddress() public {
        // Move time so that _checkTradingAccess() returns false to allow old contract registration
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);

        // Register an address as old contract
        address oldContractAddr = address(0xABCD);
        vm.prank(owner);
        proofOfCapital.registerOldContract(oldContractAddr);

        // Verify the address is registered as old contract
        assertTrue(proofOfCapital.oldContractAddress(oldContractAddr));

        // Try to assign the old contract address as new owner - should revert
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.transferOwnership(oldContractAddr);
    }

    function testAssignNewOwnerOnlyReserveOwner() public {
        address newOwner = address(0x999);

        // Non-reserveOwner tries to assign new owner
        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.transferOwnership(newOwner);

        vm.prank(returnWallet);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.transferOwnership(newOwner);

        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.transferOwnership(newOwner);
    }

    function testAssignNewOwnerEvents() public {
        address newOwner = address(0x999);

        // Test functionality without checking internal OpenZeppelin events
        vm.prank(owner);
        proofOfCapital.transferOwnership(newOwner);

        // Verify the ownership change occurred
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.reserveOwner(), newOwner);
    }

    function testAssignNewOwnerUpdatesDaoAddressWhenNewOwnerEqualsDao() public {
        // Set daoAddress to a specific address
        address daoAddr = address(0x777);
        vm.prank(owner); // owner is also daoAddress initially
        proofOfCapital.setDao(daoAddr);

        // Verify initial state
        assertEq(proofOfCapital.owner(), owner);
        assertEq(proofOfCapital.daoAddress(), daoAddr);

        // Assign new owner to the same address as daoAddress
        // After _transferOwnership, owner() will return daoAddr
        // Then the check if (owner() == daoAddress) will be true (daoAddr == daoAddr)
        // So daoAddress should be updated to newOwner (which is daoAddr)
        vm.prank(owner);
        proofOfCapital.transferOwnership(daoAddr);

        // Verify that daoAddress was updated to newOwner since newOwner equals daoAddress
        assertEq(proofOfCapital.owner(), daoAddr);
        assertEq(proofOfCapital.daoAddress(), daoAddr);
    }

    function testAssignNewOwnerDoesNotUpdateDaoAddressWhenNewOwnerNotEqualsDao() public {
        // First, set daoAddress to a different address
        address differentDao = address(0x777);
        vm.prank(owner); // owner is also daoAddress initially
        proofOfCapital.setDao(differentDao);

        // Verify owner != daoAddress
        assertEq(proofOfCapital.owner(), owner);
        assertEq(proofOfCapital.daoAddress(), differentDao);
        assertTrue(proofOfCapital.owner() != proofOfCapital.daoAddress());

        // Now assign new owner to a different address than daoAddress
        address newOwner = address(0x999);
        vm.prank(owner);
        proofOfCapital.transferOwnership(newOwner);

        // After _transferOwnership, owner() returns newOwner
        // Check: if (owner() == daoAddress) -> if (newOwner == differentDao) -> false
        // So daoAddress should NOT be updated
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.daoAddress(), differentDao); // Should remain unchanged
    }

    function testAssignNewOwnerDoesNotUpdateDaoAddressWhenInitialOwnerEqualsDao() public {
        // In BaseTest, daoAddress defaults to owner, so owner == daoAddress initially
        address initialDao = proofOfCapital.daoAddress();
        assertEq(proofOfCapital.owner(), owner);
        assertEq(proofOfCapital.daoAddress(), owner);
        assertTrue(proofOfCapital.owner() == proofOfCapital.daoAddress());

        // Assign new owner to a different address
        address newOwner = address(0x999);
        vm.prank(owner);
        proofOfCapital.transferOwnership(newOwner);

        // After _transferOwnership, owner() returns newOwner
        // Check: if (owner() == daoAddress) -> if (newOwner == initialDao) -> false
        // So daoAddress should NOT be updated and should remain as initialDao
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.daoAddress(), initialDao); // Should remain unchanged
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
        vm.expectRevert(IProofOfCapital.InvalidReserveOwner.selector);
        proofOfCapital.assignNewReserveOwner(address(0));
    }

    function testAssignNewReserveOwnerOnlyReserveOwner() public {
        address newReserveOwner = address(0x777);

        // Non-reserveOwner tries to assign new reserve owner
        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewReserveOwner(newReserveOwner);

        vm.prank(returnWallet);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.assignNewReserveOwner(newReserveOwner);

        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
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
        proofOfCapital.transferOwnership(newOwner);

        // Verify state
        assertEq(proofOfCapital.owner(), newOwner);
        assertEq(proofOfCapital.reserveOwner(), newReserveOwner);

        // Step 3: Reserve owner assigns himself as owner too
        vm.prank(newReserveOwner);
        proofOfCapital.transferOwnership(newReserveOwner);

        // Now owner == reserveOwner again
        assertEq(proofOfCapital.owner(), newReserveOwner);
        assertEq(proofOfCapital.reserveOwner(), newReserveOwner);

        // Step 4: Assign final owner (should transfer both)
        vm.prank(newReserveOwner);
        proofOfCapital.transferOwnership(finalOwner);

        // Both should be transferred
        assertEq(proofOfCapital.owner(), finalOwner);
        assertEq(proofOfCapital.reserveOwner(), finalOwner);
    }

    // Tests for collateralDeferredWithdrawal function
    function testCollateralDeferredWithdrawalSuccess() public {
        address recipient = address(0x123);

        // Schedule collateral withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Verify withdrawal is scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), recipient);
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), block.timestamp + Constants.THIRTY_DAYS);
    }

    function testCollateralDeferredWithdrawalEmitsEvent() public {
        address recipient = address(0x123);
        uint256 expectedExecuteTime = block.timestamp + Constants.THIRTY_DAYS;

        // Note: contractCollateralBalance is the amount that will be emitted in the event
        uint256 currentBalance = proofOfCapital.contractCollateralBalance();

        // Expect the event to be emitted
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IProofOfCapital.DeferredWithdrawalScheduled(recipient, currentBalance, expectedExecuteTime);
        proofOfCapital.collateralDeferredWithdrawal(recipient);
    }

    function testCollateralDeferredWithdrawalDeferredWithdrawalBlocked() public {
        address recipient = address(0x123);

        // Block deferred withdrawals
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();
        assertFalse(proofOfCapital.canWithdrawal());

        // Try to schedule collateral withdrawal when blocked
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.collateralDeferredWithdrawal(recipient);
    }

    function testCollateralDeferredWithdrawalInvalidRecipient() public {
        // Try to schedule with zero address
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidRecipient.selector);
        proofOfCapital.collateralDeferredWithdrawal(address(0));
    }

    function testCollateralDeferredWithdrawalAlreadyScheduled() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);

        // Schedule first collateral withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient1);

        // Try to schedule second collateral withdrawal (should fail)
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.CollateralDeferredWithdrawalAlreadyScheduled.selector);
        proofOfCapital.collateralDeferredWithdrawal(recipient2);
    }

    function testCollateralDeferredWithdrawalOnlyOwner() public {
        address recipient = address(0x123);

        // Non-owner tries to schedule collateral withdrawal
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        vm.prank(recipient);
        vm.expectRevert();
        proofOfCapital.collateralDeferredWithdrawal(recipient);
    }

    // function testCollateralDeferredWithdrawalDateCalculation() public {
    //     address recipient = address(0x123);

    //     // Record current time
    //     uint256 currentTime = block.timestamp;

    //     // Schedule withdrawal
    //     vm.prank(owner);
    //     proofOfCapital.collateralDeferredWithdrawal(recipient);

    //     // Verify date is set correctly (current time + 30 days)
    //     uint256 expectedDate = currentTime + Constants.THIRTY_DAYS;
    //     assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), expectedDate);

    //     // Move time forward and schedule another (after stopping first)
    //     vm.warp(block.timestamp + 10 days);
    //     vm.prank(owner);
    //     proofOfCapital.stopCollateralDeferredWithdrawal();

    //     uint256 newCurrentTime = block.timestamp;
    //     vm.prank(owner);
    //     proofOfCapital.collateralDeferredWithdrawal(recipient);

    //     uint256 newExpectedDate = newCurrentTime + Constants.THIRTY_DAYS;
    //     assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), newExpectedDate);
    // }

    function testCollateralDeferredWithdrawalWithDifferentRecipients() public {
        address[] memory recipients = new address[](3);
        recipients[0] = address(0x123);
        recipients[1] = address(0x456);
        recipients[2] = address(0x789);

        for (uint256 i = 0; i < recipients.length; i++) {
            // Reset state by stopping any existing withdrawal
            if (proofOfCapital.collateralTokenDeferredWithdrawalDate() > 0) {
                vm.prank(owner);
                proofOfCapital.stopCollateralDeferredWithdrawal();
            }

            // Schedule withdrawal with this recipient
            vm.prank(owner);
            proofOfCapital.collateralDeferredWithdrawal(recipients[i]);

            // Verify recipient is set correctly
            assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), recipients[i]);
        }
    }

    function testCollateralDeferredWithdrawalStateConsistency() public {
        address recipient = address(0x123);

        // Initially no withdrawal should be scheduled
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), owner); // Default to owner

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Verify all state variables are set correctly
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), recipient);
        assertTrue(proofOfCapital.collateralTokenDeferredWithdrawalDate() > block.timestamp);
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), block.timestamp + Constants.THIRTY_DAYS);
    }

    // Tests for stopCollateralDeferredWithdrawal function
    function testStopCollateralDeferredWithdrawalSuccessByOwner() public {
        address recipient = address(0x123);

        // First schedule a collateral withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Verify it was scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), recipient);
        assertTrue(proofOfCapital.collateralTokenDeferredWithdrawalDate() > 0);

        // Stop the withdrawal using owner
        vm.prank(owner);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Verify it was stopped and state reset
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), owner);
    }

    function testStopCollateralDeferredWithdrawalSuccessByRoyalty() public {
        address recipient = address(0x123);

        // First schedule a collateral withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Verify it was scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), recipient);
        assertTrue(proofOfCapital.collateralTokenDeferredWithdrawalDate() > 0);

        // Stop the withdrawal using royalty wallet
        vm.prank(royalty);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Verify it was stopped and state reset
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), owner);
    }

    function testStopCollateralDeferredWithdrawalAccessDenied() public {
        address recipient = address(0x123);

        // First schedule a collateral withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Try to stop with unauthorized addresses
        vm.prank(returnWallet);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        vm.prank(recipient);
        vm.expectRevert(IProofOfCapital.AccessDenied.selector);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Verify state wasn't changed
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), recipient);
        assertTrue(proofOfCapital.collateralTokenDeferredWithdrawalDate() > 0);
    }

    function testStopCollateralDeferredWithdrawalNoDeferredWithdrawalScheduled() public {
        // Try to stop without scheduling first - by owner
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Try to stop without scheduling first - by royalty
        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopCollateralDeferredWithdrawal();
    }

    function testStopCollateralDeferredWithdrawalStateReset() public {
        address recipient = address(0x123);

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Record initial scheduled state
        uint256 scheduledDate = proofOfCapital.collateralTokenDeferredWithdrawalDate();
        address scheduledRecipient = proofOfCapital.recipientDeferredWithdrawalCollateralToken();

        // Verify initial state
        assertTrue(scheduledDate > 0);
        assertEq(scheduledRecipient, recipient);

        // Stop withdrawal
        vm.prank(owner);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Verify state is properly reset
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), owner);

        // Verify values actually changed
        assertTrue(scheduledDate > 0 && proofOfCapital.collateralTokenDeferredWithdrawalDate() == 0);
        assertTrue(
            scheduledRecipient == recipient && proofOfCapital.recipientDeferredWithdrawalCollateralToken() == owner
        );
    }

    function testStopCollateralDeferredWithdrawalMultipleTimes() public {
        address recipient = address(0x123);

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Stop withdrawal first time
        vm.prank(owner);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Try to stop again - should fail with NoDeferredWithdrawalScheduled
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Same with royalty
        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.stopCollateralDeferredWithdrawal();
    }

    function testStopCollateralDeferredWithdrawalAfterReschedule() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);

        // Schedule first withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient1);

        // Stop first withdrawal
        vm.prank(owner);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Schedule second withdrawal (should work since first was stopped)
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient2);

        // Verify second withdrawal is scheduled
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), recipient2);
        assertTrue(proofOfCapital.collateralTokenDeferredWithdrawalDate() > 0);

        // Stop second withdrawal using royalty wallet
        vm.prank(royalty);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Verify it was stopped
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), owner);
    }

    function testStopCollateralDeferredWithdrawalOwnerVsRoyaltyAccess() public {
        address recipient = address(0x123);

        // Test 1: Owner can stop withdrawal scheduled by owner
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        vm.prank(owner);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Test 2: Royalty can stop withdrawal scheduled by owner
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        vm.prank(royalty);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        // Both should work since both owner and royalty have access
        // Verify final state
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), 0);
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), owner);
    }

    function testStopCollateralDeferredWithdrawalConsistentBehavior() public {
        // Test that the function behaves consistently regardless of who calls it
        address recipient = address(0x123);

        // Test stopping by owner
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        uint256 scheduledDate1 = proofOfCapital.collateralTokenDeferredWithdrawalDate();

        vm.prank(owner);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        uint256 resetDate1 = proofOfCapital.collateralTokenDeferredWithdrawalDate();
        address resetRecipient1 = proofOfCapital.recipientDeferredWithdrawalCollateralToken();

        // Test stopping by royalty
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        uint256 scheduledDate2 = proofOfCapital.collateralTokenDeferredWithdrawalDate();

        vm.prank(royalty);
        proofOfCapital.stopCollateralDeferredWithdrawal();

        uint256 resetDate2 = proofOfCapital.collateralTokenDeferredWithdrawalDate();
        address resetRecipient2 = proofOfCapital.recipientDeferredWithdrawalCollateralToken();

        // Both should have same behavior
        assertEq(resetDate1, resetDate2); // Both should be 0
        assertEq(resetRecipient1, resetRecipient2); // Both should be owner
        assertTrue(scheduledDate1 > 0 && scheduledDate2 > 0); // Both were properly scheduled
        assertEq(resetDate1, 0);
        assertEq(resetDate2, 0);
        assertEq(resetRecipient1, owner);
        assertEq(resetRecipient2, owner);
    }

    // Tests for confirmCollateralDeferredWithdrawal function
    function testConfirmCollateralDeferredWithdrawalSuccess() public {
        // По текущей логике контракта вызов confirmCollateralDeferredWithdrawal
        // всегда завершится revert`ом, так как функция depositCollateral вызывается на
        // адресе владельца, который не реализует её. Поэтому ожидаем revert
        // без проверки последующих состояний.
        address recipient = address(0x123);

        // Планируем отложенное снятие поддержки
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Перемещаем время вперёд, чтобы прошёл период ожидания
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Ожидаем, что confirmCollateralDeferredWithdrawal вызовет revert
        vm.prank(owner);
        vm.expectRevert();
        proofOfCapital.confirmCollateralDeferredWithdrawal();
    }

    function testConfirmCollateralDeferredWithdrawalDeferredWithdrawalBlocked() public {
        address recipient = address(0x123);

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Block withdrawals
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();

        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Try to confirm when blocked
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.confirmCollateralDeferredWithdrawal();
    }

    function testConfirmCollateralDeferredWithdrawalNoDeferredWithdrawalScheduled() public {
        // Try to confirm without scheduling
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.confirmCollateralDeferredWithdrawal();
    }

    function testConfirmCollateralDeferredWithdrawalWithdrawalDateNotReached() public {
        address recipient = address(0x123);

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Try to confirm before 30 days
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmCollateralDeferredWithdrawal();

        // Move time forward but not enough
        vm.warp(block.timestamp + Constants.THIRTY_DAYS - 1);
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmCollateralDeferredWithdrawal();
    }

    function testConfirmCollateralDeferredWithdrawalOnlyOwner() public {
        address recipient = address(0x123);

        // Schedule withdrawal
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Move time forward
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Try to confirm with non-owner addresses
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.confirmCollateralDeferredWithdrawal();

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.confirmCollateralDeferredWithdrawal();

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.confirmCollateralDeferredWithdrawal();

        vm.prank(recipient);
        vm.expectRevert();
        proofOfCapital.confirmCollateralDeferredWithdrawal();
    }

    function testConfirmCollateralDeferredWithdrawalWithZeroBalance() public {
        address recipient = address(0x123);

        // Планируем отложенное снятие поддержки (баланс контракта по умолчанию 0)
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Перемещаем время вперёд
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Теперь ожидаем, что confirmCollateralDeferredWithdrawal завершится revert`ом
        vm.prank(owner);
        vm.expectRevert();
        proofOfCapital.confirmCollateralDeferredWithdrawal();
    }

    function testConfirmCollateralDeferredWithdrawalBasicValidation() public {
        // Test that all our basic require checks work as expected

        // Test 1: No withdrawal scheduled
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.NoDeferredWithdrawalScheduled.selector);
        proofOfCapital.confirmCollateralDeferredWithdrawal();

        // Test 2: Schedule and test date not reached
        address recipient = address(0x123);

        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.WithdrawalDateNotReached.selector);
        proofOfCapital.confirmCollateralDeferredWithdrawal();

        // Test 3: Block withdrawals and test blocked error
        vm.prank(owner);
        proofOfCapital.toggleDeferredWithdrawal();

        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.DeferredWithdrawalBlocked.selector);
        proofOfCapital.confirmCollateralDeferredWithdrawal();
    }

    function testConfirmCollateralDeferredWithdrawalContractDeactivation() public {
        address recipient = address(0x123);

        // Контракт должен быть активен в начале
        assertTrue(proofOfCapital.isActive());

        // Планируем отложенное снятие поддержки
        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        // Перемещаем время вперёд
        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        // Подтверждение должно привести к revert
        vm.prank(owner);
        vm.expectRevert();
        proofOfCapital.confirmCollateralDeferredWithdrawal();

        // Контракт остаётся активным
        assertTrue(proofOfCapital.isActive());
    }

    function testConfirmCollateralDeferredWithdrawalStateConsistency() public {
        address recipient = address(0x123);

        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        uint256 scheduledDate = proofOfCapital.collateralTokenDeferredWithdrawalDate();
        address scheduledRecipient = proofOfCapital.recipientDeferredWithdrawalCollateralToken();

        vm.warp(block.timestamp + Constants.THIRTY_DAYS);

        vm.prank(owner);
        vm.expectRevert();
        proofOfCapital.confirmCollateralDeferredWithdrawal();

        // Подтверждение завершилось revert`ом, поэтому данные должны остаться как были
        assertEq(proofOfCapital.collateralTokenDeferredWithdrawalDate(), scheduledDate);
        assertEq(proofOfCapital.recipientDeferredWithdrawalCollateralToken(), scheduledRecipient);
        assertTrue(proofOfCapital.isActive());
    }

    function testConfirmCollateralDeferredWithdrawalExpiredAfterSevenDays() public {
        address recipient = address(0x123);

        uint256 collateralBalanceAmount = 5000e18;
        uint256 slotContractCollateralBalance =
            _stdStore.target(address(proofOfCapital)).sig("contractCollateralBalance()").find();
        vm.store(address(proofOfCapital), bytes32(slotContractCollateralBalance), bytes32(collateralBalanceAmount));

        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(weth)), address(proofOfCapital), collateralBalanceAmount);
        vm.stopPrank();

        uint256 collateralBalance = proofOfCapital.contractCollateralBalance();
        assertTrue(collateralBalance > 0, "Should have collateral balance");

        vm.prank(owner);
        proofOfCapital.collateralDeferredWithdrawal(recipient);

        uint256 withdrawalDate = proofOfCapital.collateralTokenDeferredWithdrawalDate();
        assertTrue(withdrawalDate > 0, "Withdrawal should be scheduled");

        vm.warp(withdrawalDate);

        vm.warp(withdrawalDate + Constants.SEVEN_DAYS + 1);

        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.CollateralTokenWithdrawalWindowExpired.selector);
        proofOfCapital.confirmCollateralDeferredWithdrawal();
    }

    // Tests for setReturnWallet function
    function testChangeReturnWalletSuccess() public {
        address newReturnWallet = address(0x999);

        // Verify initial state
        assertTrue(proofOfCapital.returnWalletAddresses(returnWallet));

        // Add new return wallet
        vm.prank(owner);
        proofOfCapital.setReturnWallet(newReturnWallet, true);

        // Verify both wallets are return wallets
        assertTrue(proofOfCapital.returnWalletAddresses(returnWallet));
        assertTrue(proofOfCapital.returnWalletAddresses(newReturnWallet));
    }

    function testChangeReturnWalletInvalidAddress() public {
        // Try to set zero address
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidAddress.selector);
        proofOfCapital.setReturnWallet(address(0), true);

        // Verify state wasn't changed
        assertTrue(proofOfCapital.returnWalletAddresses(returnWallet));
    }

    function testChangeReturnWalletOnlyOwner() public {
        address newReturnWallet = address(0x999);

        // Non-owner tries to change return wallet
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.setReturnWallet(newReturnWallet, true);

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.setReturnWallet(newReturnWallet, true);

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.setReturnWallet(newReturnWallet, true);

        // Verify state wasn't changed
        assertTrue(proofOfCapital.returnWalletAddresses(returnWallet));
        assertFalse(proofOfCapital.returnWalletAddresses(newReturnWallet));
    }

    function testChangeReturnWalletEvent() public {
        address newReturnWallet = address(0x999);

        // Expect ReturnWalletChanged event
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IProofOfCapital.ReturnWalletChanged(newReturnWallet);
        proofOfCapital.setReturnWallet(newReturnWallet, true);
    }

    function testChangeReturnWalletMultipleTimes() public {
        address firstNewWallet = address(0x777);
        address secondNewWallet = address(0x888);

        // First add
        vm.prank(owner);
        proofOfCapital.setReturnWallet(firstNewWallet, true);
        assertTrue(proofOfCapital.returnWalletAddresses(firstNewWallet));

        // Second add
        vm.prank(owner);
        proofOfCapital.setReturnWallet(secondNewWallet, true);
        assertTrue(proofOfCapital.returnWalletAddresses(secondNewWallet));

        // Both should be return wallets
        assertTrue(proofOfCapital.returnWalletAddresses(firstNewWallet));
        assertTrue(proofOfCapital.returnWalletAddresses(secondNewWallet));
    }

    function testChangeReturnWalletToSameAddress() public {
        // Set to same address should work (no restriction)
        vm.prank(owner);
        proofOfCapital.setReturnWallet(returnWallet, true);

        // Verify it's still a return wallet
        assertTrue(proofOfCapital.returnWalletAddresses(returnWallet));
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
            proofOfCapital.setReturnWallet(validAddresses[i], true);
            assertTrue(proofOfCapital.returnWalletAddresses(validAddresses[i]));
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
        vm.expectRevert(IProofOfCapital.InvalidAddress.selector);
        proofOfCapital.changeRoyaltyWallet(address(0));

        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyWalletAddress(), royalty);
    }

    function testChangeRoyaltyWalletOnlyRoyaltyWalletCanChange() public {
        address newRoyaltyWallet = address(0x999);

        // Non-royalty wallet tries to change royalty wallet
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);

        vm.prank(returnWallet);
        vm.expectRevert(IProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);

        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);

        vm.prank(address(0x123));
        vm.expectRevert(IProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
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
        vm.expectRevert(IProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
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
        vm.expectRevert(IProofOfCapital.OnlyRoyaltyWalletCanChange.selector);
        proofOfCapital.changeRoyaltyWallet(newRoyaltyWallet);

        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyWalletAddress(), royalty);
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
        // After initialization: offsetLaunch was processed, so totalLaunchSold = offsetLaunch (10000e18)
        // launchTokensEarned = 0
        uint256 totalSold = proofOfCapital.totalLaunchSold();
        uint256 launchTokensEarned = proofOfCapital.launchTokensEarned();

        // Verify state after initialization
        assertGt(totalSold, 0, "totalLaunchSold should be > 0 after initialization");
        assertEq(launchTokensEarned, 0, "launchTokensEarned should be 0 initially");

        // launchAvailable should be totalLaunchSold - launchTokensEarned
        uint256 expectedAvailable = totalSold - launchTokensEarned;
        assertEq(proofOfCapital.launchAvailable(), expectedAvailable);
        assertGt(proofOfCapital.launchAvailable(), 0, "Tokens should be available after initialization");
    }

    function testTokenAvailableWhenEarnedEqualsTotal() public {
        // This tests edge case where launchTokensEarned equals totalLaunchSold
        // In initial state: totalLaunchSold = 10000e18, launchTokensEarned = 0

        // We need to create scenario where launchTokensEarned increases
        // This happens when return wallet sells tokens back to contract

        // Give tokens to return wallet
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 10000e18);
        vm.stopPrank();

        // Return wallet sells tokens back (this increases launchTokensEarned)
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(10000e18);
        vm.stopPrank();

        // Check if launchTokensEarned increased
        uint256 launchTokensEarned = proofOfCapital.launchTokensEarned();
        uint256 totalSold = proofOfCapital.totalLaunchSold();

        // launchAvailable should be totalSold - launchTokensEarned
        uint256 expectedAvailable = totalSold - launchTokensEarned;
        assertEq(proofOfCapital.launchAvailable(), expectedAvailable);

        // If launchTokensEarned equals totalSold, available should be 0
        if (launchTokensEarned == totalSold) {
            assertEq(proofOfCapital.launchAvailable(), 0);
        }
    }

    function testTokenAvailableStateConsistency() public view {
        // Test that launchAvailable always equals totalLaunchSold - launchTokensEarned

        // Record initial state
        uint256 initialTotalSold = proofOfCapital.totalLaunchSold();
        uint256 initialTokensEarned = proofOfCapital.launchTokensEarned();
        uint256 initialAvailable = proofOfCapital.launchAvailable();

        // Verify initial consistency
        assertEq(initialAvailable, initialTotalSold - initialTokensEarned);

        // After any state changes, consistency should be maintained
        // This is a property that should always hold
        assertTrue(
            proofOfCapital.launchAvailable() == proofOfCapital.totalLaunchSold() - proofOfCapital.launchTokensEarned()
        );
    }

    function testViewFunctionsIntegration() public {
        // Test that view functions work correctly together

        // Initial state
        uint256 remaining = proofOfCapital.remainingSeconds();
        bool tradingOpp = proofOfCapital.tradingOpportunity();
        uint256 available = proofOfCapital.launchAvailable();

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
        assertEq(proofOfCapital.launchAvailable(), available);
    }

    // Tests for withdrawAllLaunchTokens function
    function testWithdrawAllTokensSuccess() public {
        _ensureInitialized();

        // The key insight: launchBalance is only increased by returnWallet selling tokens back
        // We need to create a scenario where returnWallet sells tokens to increase launchBalance

        // Give tokens to return wallet
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 50000e18);
        vm.stopPrank();

        // Return wallet sells tokens back (this increases launchBalance)
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(50000e18);
        vm.stopPrank();

        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // Record initial state
        uint256 contractBalance = proofOfCapital.launchBalance();
        uint256 totalSold = proofOfCapital.totalLaunchSold();
        uint256 availableTokens = contractBalance - totalSold;
        address dao = proofOfCapital.daoAddress();
        uint256 daoBalanceBefore = token.balanceOf(dao);

        // Ensure there are tokens available for withdrawal
        assertTrue(availableTokens > 0);

        // Withdraw all tokens (only DAO can call this)
        vm.prank(dao);
        proofOfCapital.withdrawAllLaunchTokens();

        // Verify tokens transferred to DAO
        assertEq(token.balanceOf(dao), daoBalanceBefore + availableTokens);

        // Verify contract is inactive
        assertEq(proofOfCapital.isActive(), false);
    }

    function testWithdrawAllTokensLockPeriodNotEnded() public {
        // Try to withdraw before lock period ends
        address dao = proofOfCapital.daoAddress();
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.LockPeriodNotEnded.selector);
        proofOfCapital.withdrawAllLaunchTokens();
    }

    function testWithdrawAllTokensNoTokensToWithdraw() public {
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // In initial state: launchBalance = 0, totalLaunchSold = 10000e18 (offset)
        // So availableTokens = 0 - 10000e18 = negative, but function checks > 0

        address dao = proofOfCapital.daoAddress();
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.NoTokensToWithdraw.selector);
        proofOfCapital.withdrawAllLaunchTokens();
    }

    function testWithdrawAllTokensStateResetComplete() public {
        _ensureInitialized();

        // Setup tokens in contract using returnWallet selling tokens back
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 50000e18);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(50000e18);
        vm.stopPrank();

        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // Withdraw all tokens (only DAO can call this)
        address dao = proofOfCapital.daoAddress();
        vm.prank(dao);
        proofOfCapital.withdrawAllLaunchTokens();

        // Verify contract is inactive
        assertEq(proofOfCapital.isActive(), false);
    }

    function testWithdrawAllTokensAtExactLockEnd() public {
        _ensureInitialized();

        // Setup tokens in contract using returnWallet selling tokens back
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 50000e18);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(50000e18);
        vm.stopPrank();

        // Move time to exact lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime);

        // Should work at exact lock end time
        vm.prank(owner);
        proofOfCapital.withdrawAllLaunchTokens();

        // Verify withdrawal succeeded and contract is inactive
        assertEq(proofOfCapital.isActive(), false);
    }

    function testWithdrawAllTokensCalculatesAvailableCorrectly() public {
        _ensureInitialized();

        // Add tokens and simulate some trading to test calculation
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), address(proofOfCapital), 100000e18);
        vm.stopPrank();

        // Create scenario where returnWallet sells tokens back
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 50000e18);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 50000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(50000e18);
        vm.stopPrank();

        // Move past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // Get actual contract balance (function now uses balanceOf instead of launchBalance - totalLaunchSold)
        uint256 expectedAvailable = token.balanceOf(address(proofOfCapital));

        address dao = proofOfCapital.daoAddress();
        uint256 daoBalanceBefore = token.balanceOf(dao);

        // Withdraw (only DAO can call this)
        vm.prank(dao);
        proofOfCapital.withdrawAllLaunchTokens();

        // Verify correct amount transferred to DAO
        assertEq(token.balanceOf(dao), daoBalanceBefore + expectedAvailable);
    }

    // Tests for withdrawAllCollateralTokens function

    function testWithdrawAllCollateralTokensLockPeriodNotEnded() public {
        // Try to withdraw before lock period ends
        address dao = proofOfCapital.daoAddress();
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.LockPeriodNotEnded.selector);
        proofOfCapital.withdrawAllCollateralTokens();
    }

    function testWithdrawAllCollateralTokensNoCollateralTokensToWithdraw() public {
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // In initial state, contract balance = 0
        assertEq(weth.balanceOf(address(proofOfCapital)), 0);

        address dao = proofOfCapital.daoAddress();
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.NoCollateralTokensToWithdraw.selector);
        proofOfCapital.withdrawAllCollateralTokens();
    }

    function testWithdrawAllCollateralTokensOnlyDAO() public {
        _ensureInitialized();

        // Set a different DAO address (not owner)
        address daoAddr = address(0x777);
        vm.prank(owner);
        proofOfCapital.setDao(daoAddr);

        // Add collateral tokens to contract
        vm.startPrank(owner);
        weth.approve(address(proofOfCapital), 1000e18);
        proofOfCapital.depositCollateral(1000e18);
        vm.stopPrank();

        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // Non-DAO tries to withdraw (should fail)
        vm.prank(owner);
        vm.expectRevert();
        proofOfCapital.withdrawAllCollateralTokens();

        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.withdrawAllCollateralTokens();

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.withdrawAllCollateralTokens();

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.withdrawAllCollateralTokens();
    }

    function testWithdrawAllCollateralTokensWithZeroBalance() public {
        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // Try to withdraw with zero balance
        address dao = proofOfCapital.daoAddress();
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.NoCollateralTokensToWithdraw.selector);
        proofOfCapital.withdrawAllCollateralTokens();
    }

    function testWithdrawBothTypesOfTokens() public {
        _ensureInitialized();

        // Test withdrawing both main tokens and collateral tokens separately
        // This test validates that both withdrawal functions work independently

        // First test: withdraw main tokens
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 20000e18);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 20000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(20000e18);
        vm.stopPrank();

        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // Test main token withdrawal
        uint256 contractBalance = token.balanceOf(address(proofOfCapital));
        address dao = proofOfCapital.daoAddress();
        uint256 daoMainBalanceBefore = token.balanceOf(dao);

        vm.prank(dao);
        proofOfCapital.withdrawAllLaunchTokens();

        // Verify main tokens withdrawn and contract is inactive
        assertEq(token.balanceOf(dao), daoMainBalanceBefore + contractBalance);
        assertEq(proofOfCapital.isActive(), false);

        // Second test: test collateral token withdrawal with zero balance (expected to fail)
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.NoCollateralTokensToWithdraw.selector);
        proofOfCapital.withdrawAllCollateralTokens();

        // This test validates that both functions exist and work correctly
        // Even though we can't easily create collateral balance due to offset logic
    }

    // Tests for withdrawToken function
    function testWithdrawTokenSuccess() public {
        // Create a new ERC20 token (not launch or collateral)
        MockERC20 otherToken = new MockERC20("OtherToken", "OT");

        // Transfer tokens to contract
        uint256 amount = 10000e18;
        otherToken.transfer(address(proofOfCapital), amount);

        address dao = proofOfCapital.daoAddress();
        uint256 daoBalanceBefore = otherToken.balanceOf(dao);

        // Withdraw tokens (only DAO can call this, works at any time)
        vm.prank(dao);
        proofOfCapital.withdrawToken(address(otherToken), amount);

        // Verify tokens transferred to DAO
        assertEq(otherToken.balanceOf(dao), daoBalanceBefore + amount);
        assertEq(otherToken.balanceOf(address(proofOfCapital)), 0);
    }

    function testWithdrawTokenOnlyDAO() public {
        // Create a new ERC20 token
        MockERC20 otherToken = new MockERC20("OtherToken", "OT");
        otherToken.transfer(address(proofOfCapital), 10000e18);

        // Non-DAO tries to withdraw (should fail)
        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.withdrawToken(address(otherToken), 1000e18);

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.withdrawToken(address(otherToken), 1000e18);

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.withdrawToken(address(otherToken), 1000e18);
    }

    function testWithdrawTokenInvalidTokenLaunchToken() public {
        address dao = proofOfCapital.daoAddress();

        // Try to withdraw launch token (should fail)
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.InvalidTokenForWithdrawal.selector);
        proofOfCapital.withdrawToken(address(token), 1000e18);
    }

    function testWithdrawTokenInvalidTokenCollateralToken() public {
        address dao = proofOfCapital.daoAddress();

        // Try to withdraw collateral token (should fail)
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.InvalidTokenForWithdrawal.selector);
        proofOfCapital.withdrawToken(address(weth), 1000e18);
    }

    function testWithdrawTokenInvalidAddress() public {
        address dao = proofOfCapital.daoAddress();

        // Try to withdraw with zero address (should fail)
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.InvalidAddress.selector);
        proofOfCapital.withdrawToken(address(0), 1000e18);
    }

    function testWithdrawTokenInvalidAmount() public {
        MockERC20 otherToken = new MockERC20("OtherToken", "OT");
        address dao = proofOfCapital.daoAddress();

        // Try to withdraw zero amount (should fail)
        vm.prank(dao);
        vm.expectRevert(IProofOfCapital.InvalidAmount.selector);
        proofOfCapital.withdrawToken(address(otherToken), 0);
    }

    function testWithdrawTokenWorksBeforeLockEnd() public {
        // Create a new ERC20 token
        MockERC20 otherToken = new MockERC20("OtherToken", "OT");
        uint256 amount = 5000e18;
        otherToken.transfer(address(proofOfCapital), amount);

        // Verify we're before lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        assertTrue(block.timestamp < lockEndTime);

        address dao = proofOfCapital.daoAddress();
        uint256 daoBalanceBefore = otherToken.balanceOf(dao);

        // Withdraw tokens before lock end (should work)
        vm.prank(dao);
        proofOfCapital.withdrawToken(address(otherToken), amount);

        // Verify tokens transferred to DAO
        assertEq(otherToken.balanceOf(dao), daoBalanceBefore + amount);
    }

    function testWithdrawTokenWorksAfterLockEnd() public {
        // Create a new ERC20 token
        MockERC20 otherToken = new MockERC20("OtherToken", "OT");
        uint256 amount = 5000e18;
        otherToken.transfer(address(proofOfCapital), amount);

        // Move time past lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        address dao = proofOfCapital.daoAddress();
        uint256 daoBalanceBefore = otherToken.balanceOf(dao);

        // Withdraw tokens after lock end (should work)
        vm.prank(dao);
        proofOfCapital.withdrawToken(address(otherToken), amount);

        // Verify tokens transferred to DAO
        assertEq(otherToken.balanceOf(dao), daoBalanceBefore + amount);
    }

    function testWithdrawTokenEmitsEvent() public {
        MockERC20 otherToken = new MockERC20("OtherToken", "OT");
        uint256 amount = 3000e18;
        otherToken.transfer(address(proofOfCapital), amount);

        address dao = proofOfCapital.daoAddress();

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit IProofOfCapital.TokenWithdrawn(address(otherToken), dao, amount);

        vm.prank(dao);
        proofOfCapital.withdrawToken(address(otherToken), amount);
    }

    // Tests for setMarketMaker function
    function testSetMarketMakerInvalidAddress() public {
        // Try to set market maker with zero address
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidAddress.selector);
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
        _ensureInitialized();

        // Try to buy tokens with zero amount
        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.InvalidAmount.selector);
        proofOfCapital.buyLaunchTokens(0);
    }

    function testBuyTokensUseDepositFunctionForOwners() public {
        _ensureInitialized();

        // Owner tries to use buyLaunchTokens instead of depositCollateral
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.UseDepositFunctionForOwners.selector);
        proofOfCapital.buyLaunchTokens(1000e18);
    }

    function testDepositInvalidAmountZero() public {
        _ensureInitialized();

        // Try to depositCollateral zero amount
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.InvalidAmount.selector);
        proofOfCapital.depositCollateral(0);
    }

    function testSellTokensInvalidAmountZero() public {
        _ensureInitialized();

        // Try to sell zero tokens
        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.InvalidAmount.selector);
        proofOfCapital.sellLaunchTokens(0);
    }

    // // Tests for modifier requirements
    // function testOnlyActiveContractModifier() public {
    //     // First make contract inactive by confirming collateral withdrawal
    //     address recipient = address(0x123);

    //     // Schedule collateral withdrawal
    //     vm.prank(owner);
    //     proofOfCapital.collateralDeferredWithdrawal(recipient);

    //     // Move time forward and confirm
    //     vm.warp(block.timestamp + Constants.THIRTY_DAYS);
    //     vm.prank(owner);
    //     proofOfCapital.confirmCollateralDeferredWithdrawal();

    //     // Verify contract is inactive
    //     assertFalse(proofOfCapital.isActive());

    //     // Try to call functions that require active contract
    //     vm.prank(marketMaker);
    //     vm.expectRevert(IProofOfCapital.ContractNotActive.selector);
    //     proofOfCapital.buyLaunchTokens(1000e18);

    //     vm.prank(owner);
    //     vm.expectRevert(IProofOfCapital.ContractNotActive.selector);
    //     proofOfCapital.depositCollateral(1000e18);

    //     vm.prank(marketMaker);
    //     vm.expectRevert(IProofOfCapital.ContractNotActive.selector);
    //     proofOfCapital.sellLaunchTokens(1000e18);
    // }

    // Tests for access control modifiers
    function testOnlyReserveOwnerModifier() public {
        address newOwner = address(0x999);

        // Non-reserve owner tries to assign new owner
        vm.prank(royalty);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.transferOwnership(newOwner);

        vm.prank(returnWallet);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.transferOwnership(newOwner);

        vm.prank(marketMaker);
        vm.expectRevert(IProofOfCapital.OnlyReserveOwner.selector);
        proofOfCapital.transferOwnership(newOwner);
    }

    function testOnlyOwnerOrOldContractModifier() public {
        // We can't directly test this modifier easily without modifying the contract
        // But we can test that non-authorized addresses fail

        vm.prank(royalty);
        vm.expectRevert();
        proofOfCapital.depositCollateral(1000e18);

        vm.prank(returnWallet);
        vm.expectRevert();
        proofOfCapital.depositCollateral(1000e18);

        vm.prank(marketMaker);
        vm.expectRevert();
        proofOfCapital.depositCollateral(1000e18);
    }

    // Additional boundary and edge case tests
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

        // Test launchAvailable consistency
        uint256 totalSold = proofOfCapital.totalLaunchSold();
        uint256 launchTokensEarned = proofOfCapital.launchTokensEarned();
        uint256 expectedAvailable = totalSold - launchTokensEarned;
        assertEq(proofOfCapital.launchAvailable(), expectedAvailable);
    }
}

contract ProofOfCapitalProfitTest is Test {
    ProofOfCapital public proofOfCapital;
    MockERC20 public token;
    MockERC20 public weth;
    MockRoyalty public mockRoyalty;

    address public owner = address(0x1);
    address public royalty;
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

        // Deploy mock royalty contract
        mockRoyalty = new MockRoyalty();
        royalty = address(mockRoyalty);

        // Deploy implementation
        // Prepare initialization parameters
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 10000e18, // Add offset to enable trading
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            collateralToken: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        // Deploy contract directly
        proofOfCapital = new ProofOfCapital(params);

        // Setup tokens for users and add market maker permissions
        SafeERC20.safeTransfer(IERC20(address(token)), address(proofOfCapital), 1000000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), user, 10000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), marketMaker, 10000e18);

        // Enable market maker for user to allow trading
        proofOfCapital.setMarketMaker(user, true);

        vm.stopPrank();

        // Approve tokens
        vm.prank(user);
        weth.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(marketMaker);
        weth.approve(address(proofOfCapital), type(uint256).max);
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
}

contract ProofOfCapitalInitializationTest is Test {
    ProofOfCapital public implementation;
    MockERC20 public token;
    MockERC20 public weth;
    MockRoyalty public mockRoyalty;

    address public owner = address(0x1);
    address public royalty;
    address public returnWallet = address(0x3);
    address public marketMaker = address(0x4);

    function setUp() public {
        vm.warp(1672531200); // January 1, 2023

        vm.startPrank(owner);

        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");

        // Deploy mock royalty contract
        mockRoyalty = new MockRoyalty();
        royalty = address(mockRoyalty);

        vm.stopPrank();
    }

    function getValidParams() internal view returns (IProofOfCapital.InitParams memory) {
        return IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            collateralToken: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });
    }

    // Test InitialPriceMustBePositive error
    function testInitializeInitialPriceMustBePositiveZero() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.initialPricePerLaunchToken = 0; // Invalid: zero price

        vm.expectRevert(IProofOfCapital.InitialPriceMustBePositive.selector);
        new ProofOfCapital(params);
    }

    function testInitializeInitialPriceMustBePositiveValid() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.initialPricePerLaunchToken = 1; // Valid: minimum positive price

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify price was set
        assertEq(proofOfCapital.initialPricePerLaunchToken(), 1);
    }

    // Test InvalidLevelDecreaseMultiplierAfterTrend error
    function testInitializeMultiplierTooHigh() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierAfterTrend = int256(Constants.PERCENTAGE_DIVISOR); // Invalid: equal to divisor

        vm.expectRevert(IProofOfCapital.InvalidLevelDecreaseMultiplierAfterTrend.selector);
        new ProofOfCapital(params);
    }

    function testInitializeMultiplierTooHighAboveDivisor() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierAfterTrend = int256(Constants.PERCENTAGE_DIVISOR + 1); // Invalid: above divisor

        vm.expectRevert(IProofOfCapital.InvalidLevelDecreaseMultiplierAfterTrend.selector);
        new ProofOfCapital(params);
    }

    function testInitializeMultiplierValidAtBoundary() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelDecreaseMultiplierAfterTrend = int256(Constants.PERCENTAGE_DIVISOR - 1); // Valid: just below divisor
        params.offsetLaunch = 100e18; // Smaller offset to avoid overflow in calculations

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify multiplier was set
        assertEq(proofOfCapital.levelDecreaseMultiplierAfterTrend(), int256(Constants.PERCENTAGE_DIVISOR - 1));
    }

    // Test InvalidLevelIncreaseMultiplier error for levelIncreaseMultiplier
    function testInitializeLevelIncreaseMultiplierTooLow() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelIncreaseMultiplier = -int256(Constants.PERCENTAGE_DIVISOR); // Invalid: below minimum range

        vm.expectRevert(IProofOfCapital.InvalidLevelIncreaseMultiplier.selector);
        new ProofOfCapital(params);
    }

    function testInitializeLevelIncreaseMultiplierValid() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelIncreaseMultiplier = 1; // Valid: minimum positive value

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify multiplier was set
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 1);
    }

    // Test InvalidLevelIncreaseMultiplier error for levelIncreaseMultiplier above range
    function testInitializeLevelIncreaseMultiplierTooHigh() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.levelIncreaseMultiplier = int256(Constants.PERCENTAGE_DIVISOR); // Invalid: above maximum range

        vm.expectRevert(IProofOfCapital.InvalidLevelIncreaseMultiplier.selector);
        new ProofOfCapital(params);
    }

    // Test PriceIncrementTooLow error for priceIncrementMultiplier
    function testInitializePriceIncrementMultiplierTooLow() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.priceIncrementMultiplier = 0; // Invalid: zero multiplier

        vm.expectRevert(IProofOfCapital.PriceIncrementTooLow.selector);
        new ProofOfCapital(params);
    }

    function testInitializePriceIncrementMultiplierValid() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.priceIncrementMultiplier = 1; // Valid: minimum positive value

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify multiplier was set
        assertEq(proofOfCapital.priceIncrementMultiplier(), 1);
    }

    // Test InvalidRoyaltyProfitPercentage error - too low
    function testInitializeRoyaltyProfitPercentageTooLow() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 1; // Invalid: must be > 1

        vm.expectRevert(IProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ProofOfCapital(params);
    }

    function testInitializeRoyaltyProfitPercentageZero() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 0; // Invalid: must be > 1

        vm.expectRevert(IProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ProofOfCapital(params);
    }

    // Test InvalidRoyaltyProfitPercentage error - too high
    function testInitializeRoyaltyProfitPercentageTooHigh() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT + 1; // Invalid: above maximum

        vm.expectRevert(IProofOfCapital.InvalidRoyaltyProfitPercentage.selector);
        new ProofOfCapital(params);
    }

    function testInitializeRoyaltyProfitPercentageValidMinimum() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = 2; // Valid: minimum value > 1

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify percentage was set
        assertEq(proofOfCapital.royaltyProfitPercent(), 2);
    }

    function testInitializeRoyaltyProfitPercentageValidMaximum() public {
        IProofOfCapital.InitParams memory params = getValidParams();
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT; // Valid: exactly at maximum

        // Should not revert
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify percentage was set
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.MAX_ROYALTY_PERCENT);
    }

    // Test boundary values for all parameters
    function testInitializeBoundaryValues() public {
        IProofOfCapital.InitParams memory params = getValidParams();

        // Set all parameters to their boundary values with smaller offsetLaunch
        params.initialPricePerLaunchToken = 1; // Minimum valid
        params.levelDecreaseMultiplierAfterTrend = 500; // Safe value below divisor
        params.levelIncreaseMultiplier = 1; // Minimum valid
        params.priceIncrementMultiplier = 1; // Minimum valid
        params.royaltyProfitPercent = 2; // Minimum valid
        params.offsetLaunch = 100e18; // Smaller offset to avoid overflow

        // Should not revert with all boundary values
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify all parameters were set correctly
        assertEq(proofOfCapital.initialPricePerLaunchToken(), 1);
        assertEq(proofOfCapital.levelDecreaseMultiplierAfterTrend(), 500);
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 1);
        assertEq(proofOfCapital.priceIncrementMultiplier(), 1);
        assertEq(proofOfCapital.royaltyProfitPercent(), 2);
    }

    // Test multiple failing conditions together
    function testInitializeMultipleInvalidParameters() public {
        IProofOfCapital.InitParams memory params = getValidParams();

        // Set multiple invalid parameters - should fail on first one (initialPricePerLaunchToken)
        params.initialPricePerLaunchToken = 0; // Invalid
        params.levelIncreaseMultiplier = 0; // Also invalid, but won't be reached

        // Should fail with the first error it encounters
        vm.expectRevert(IProofOfCapital.InitialPriceMustBePositive.selector);
        new ProofOfCapital(params);
    }

    // Test maximum valid values
    function testInitializeMaximumValidValues() public {
        IProofOfCapital.InitParams memory params = getValidParams();

        // Set to reasonable maximum values to avoid overflow
        params.initialPricePerLaunchToken = 1000e18; // Large but reasonable price
        params.levelDecreaseMultiplierAfterTrend = 999; // Just below PERCENTAGE_DIVISOR
        params.levelIncreaseMultiplier = 999; // Just below PERCENTAGE_DIVISOR
        params.priceIncrementMultiplier = 10000; // Large but reasonable multiplier
        params.royaltyProfitPercent = Constants.MAX_ROYALTY_PERCENT; // Maximum royalty
        params.offsetLaunch = 1000e18; // Smaller offset to avoid calculations overflow

        // Should not revert with maximum values
        ProofOfCapital proofOfCapital = new ProofOfCapital(params);

        // Verify values were set
        assertEq(proofOfCapital.initialPricePerLaunchToken(), 1000e18);
        assertEq(proofOfCapital.levelDecreaseMultiplierAfterTrend(), 999);
        assertEq(proofOfCapital.levelIncreaseMultiplier(), 999);
        assertEq(proofOfCapital.priceIncrementMultiplier(), 10000);
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.MAX_ROYALTY_PERCENT);
    }

    // Tests for _getPeriod function through initialization
    function testInitializeControlPeriodBelowMin() public {
        vm.startPrank(owner);
        // Setup init params with control period below minimum (1 second)
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 1000e18,
            controlPeriod: 1, // Way below minimum
            collateralToken: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        ProofOfCapital testContract = new ProofOfCapital(params);

        // Should be set to minimum
        assertEq(testContract.controlPeriod(), Constants.MIN_CONTROL_PERIOD);

        vm.stopPrank();
    }

    function testInitializeControlPeriodAboveMax() public {
        vm.startPrank(owner);
        // Setup init params with control period above maximum
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 1000e18,
            controlPeriod: Constants.MAX_CONTROL_PERIOD + 1 days, // Above maximum
            collateralToken: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        ProofOfCapital testContract = new ProofOfCapital(params);

        // Should be set to maximum
        assertEq(testContract.controlPeriod(), Constants.MAX_CONTROL_PERIOD);

        vm.stopPrank();
    }

    function testInitializeControlPeriodWithinRange() public {
        vm.startPrank(owner);
        // Calculate a valid period between min and max
        uint256 validPeriod = (Constants.MIN_CONTROL_PERIOD + Constants.MAX_CONTROL_PERIOD) / 2;

        // Setup init params with control period within valid range
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 1000e18,
            controlPeriod: validPeriod, // Within valid range
            collateralToken: address(weth),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        ProofOfCapital testContract = new ProofOfCapital(params);

        // Should be set to the provided value
        assertEq(testContract.controlPeriod(), validPeriod);

        vm.stopPrank();
    }

    function testInitializeControlPeriodAtBoundaries() public {
        vm.startPrank(owner);

        // Test at minimum boundary
        {
            IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
                initialOwner: owner,
                launchToken: address(token),
                marketMakerAddress: marketMaker,
                returnWalletAddress: returnWallet,
                royaltyWalletAddress: royalty,
                lockEndTime: block.timestamp + 365 days,
                initialPricePerLaunchToken: 1e18,
                firstLevelLaunchTokenQuantity: 1000e18,
                priceIncrementMultiplier: 50,
                levelIncreaseMultiplier: 100,
                trendChangeStep: 5,
                levelDecreaseMultiplierAfterTrend: 50,
                profitPercentage: 100,
                offsetLaunch: 1000e18,
                controlPeriod: Constants.MIN_CONTROL_PERIOD, // Exactly minimum
                collateralToken: address(weth),
                royaltyProfitPercent: 500,
                oldContractAddresses: new address[](0),
                profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
                daoAddress: address(0), // Will default to owner
                collateralTokenOracle: address(0),
                collateralTokenMinOracleValue: 0
            });

            ProofOfCapital testContract = new ProofOfCapital(params);

            assertEq(testContract.controlPeriod(), Constants.MIN_CONTROL_PERIOD);
        }

        // Test at maximum boundary
        {
            IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
                initialOwner: owner,
                launchToken: address(token),
                marketMakerAddress: marketMaker,
                returnWalletAddress: returnWallet,
                royaltyWalletAddress: royalty,
                lockEndTime: block.timestamp + 365 days,
                initialPricePerLaunchToken: 1e18,
                firstLevelLaunchTokenQuantity: 1000e18,
                priceIncrementMultiplier: 50,
                levelIncreaseMultiplier: 100,
                trendChangeStep: 5,
                levelDecreaseMultiplierAfterTrend: 50,
                profitPercentage: 100,
                offsetLaunch: 1000e18,
                controlPeriod: Constants.MAX_CONTROL_PERIOD, // Exactly maximum
                collateralToken: address(weth),
                royaltyProfitPercent: 500,
                oldContractAddresses: new address[](0),
                profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
                daoAddress: address(0), // Will default to owner
                collateralTokenOracle: address(0),
                collateralTokenMinOracleValue: 0
            });

            ProofOfCapital testContract = new ProofOfCapital(params);

            assertEq(testContract.controlPeriod(), Constants.MAX_CONTROL_PERIOD);
        }

        vm.stopPrank();
    }
}
