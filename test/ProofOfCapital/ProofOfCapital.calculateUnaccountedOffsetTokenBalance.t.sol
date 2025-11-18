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

// This is the third version of the contract. It introduces the following features: the ability to choose any jetton as support, build support with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.
pragma solidity 0.8.29;

import "../utils/BaseTest.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract ProofOfCapitalCalculateUnaccountedOffsetTokenBalanceTest is BaseTest {
    using stdStorage for StdStorage;

    StdStorage private _stdStore;

    address public nonOwner = address(0x5);
    address public user = address(0x6);

    function setUp() public override {
        super.setUp();

        // Setup: Create unaccountedOffsetTokenBalance by depositing tokens when totalTokensSold == offsetTokens
        uint256 offsetTokens = proofOfCapital.offsetTokens();

        // Set totalTokensSold to equal offsetTokens
        uint256 slotTotalSold = _stdStore.target(address(proofOfCapital)).sig("totalTokensSold()").find();
        vm.store(address(proofOfCapital), bytes32(slotTotalSold), bytes32(offsetTokens));

        // Set tokensEarned to a value less than offsetTokens to allow deposit
        uint256 tokensEarned = offsetTokens / 2;
        uint256 slotTokensEarned = _stdStore.target(address(proofOfCapital)).sig("tokensEarned()").find();
        vm.store(address(proofOfCapital), bytes32(slotTokensEarned), bytes32(tokensEarned));

        // Deposit tokens to create unaccountedOffsetTokenBalance
        uint256 depositAmount = 5000e18;
        require((offsetTokens - tokensEarned) >= depositAmount, "Test setup: insufficient offset capacity");

        vm.startPrank(owner);
        token.transfer(address(proofOfCapital), depositAmount);
        token.approve(address(proofOfCapital), depositAmount);
        proofOfCapital.depositTokens(depositAmount);
        vm.stopPrank();

        // Verify unaccountedOffsetTokenBalance was created
        assertGt(proofOfCapital.unaccountedOffsetTokenBalance(), 0, "unaccountedOffsetTokenBalance should be set");
    }

    /**
     * @dev Test successful calculation when trading access is available
     * Tests the branch where _checkTradingAccess() returns true
     */
    function testCalculateUnaccountedOffsetTokenBalance_Success_WithTradingAccess() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffsetTokenBalance();
        uint256 initialOffsetTokens = proofOfCapital.offsetTokens();
        uint256 initialTotalTokensSold = proofOfCapital.totalTokensSold();
        uint256 initialOffsetStep = proofOfCapital.offsetStep();
        uint256 amount = 1000e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient unaccounted balance");

        // Setup trading access by manipulating controlDay to be in the past
        // This makes _checkTradingAccess() return true
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetTokenBalanceProcessed(amount);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(amount);

        assertEq(
            proofOfCapital.unaccountedOffsetTokenBalance(),
            initialUnaccountedBalance - amount,
            "unaccountedOffsetTokenBalance should decrease by amount"
        );
        assertEq(proofOfCapital.offsetTokens(), initialOffsetTokens - amount, "offsetTokens should decrease by amount");
        assertEq(
            proofOfCapital.totalTokensSold(),
            initialTotalTokensSold - amount,
            "totalTokensSold should decrease by amount"
        );
        // offsetStep should decrease or stay the same (going backwards)
        assertLe(proofOfCapital.offsetStep(), initialOffsetStep, "offsetStep should decrease or stay the same");
    }

    /**
     * @dev Test successful calculation when trading access is not available but unlock window is active
     * Tests the branch where _checkTradingAccess() returns false and _checkUnlockWindow() returns true
     */
    function testCalculateUnaccountedOffsetTokenBalance_Success_WithUnlockWindow() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffsetTokenBalance();
        uint256 amount = 1000e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient unaccounted balance");

        // Setup: No trading access, but unlock window is active
        // Set controlDay to be in the past beyond controlPeriod
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        uint256 pastControlDay = block.timestamp - Constants.MIN_CONTROL_PERIOD - 1 days;
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(pastControlDay));

        // Ensure we're not in trading access window
        // Set lockEndTime far in the future and no deferred withdrawals
        uint256 slotLockEndTime = _stdStore.target(address(proofOfCapital)).sig("lockEndTime()").find();
        vm.store(address(proofOfCapital), bytes32(slotLockEndTime), bytes32(block.timestamp + 365 days));

        // Clear deferred withdrawal dates to ensure no trading access
        uint256 slotMainDeferred =
            _stdStore.target(address(proofOfCapital)).sig("mainTokenDeferredWithdrawalDate()").find();
        vm.store(address(proofOfCapital), bytes32(slotMainDeferred), bytes32(0));
        uint256 slotSupportDeferred =
            _stdStore.target(address(proofOfCapital)).sig("supportTokenDeferredWithdrawalDate()").find();
        vm.store(address(proofOfCapital), bytes32(slotSupportDeferred), bytes32(0));

        uint256 controlDayBefore = proofOfCapital.controlDay();

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetTokenBalanceProcessed(amount);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(amount);

        assertEq(
            proofOfCapital.unaccountedOffsetTokenBalance(),
            initialUnaccountedBalance - amount,
            "unaccountedOffsetTokenBalance should decrease by amount"
        );
        // controlDay should be increased by THIRTY_DAYS
        assertEq(
            proofOfCapital.controlDay(),
            controlDayBefore + Constants.THIRTY_DAYS,
            "controlDay should be increased by THIRTY_DAYS"
        );
    }

    /**
     * @dev Test successful calculation when trading access is not available and unlock window is not active
     * Tests the branch where _checkTradingAccess() returns false and _checkUnlockWindow() returns false
     */
    function testCalculateUnaccountedOffsetTokenBalance_Success_WithoutUnlockWindow() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffsetTokenBalance();
        uint256 amount = 1000e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient unaccounted balance");

        // Setup: No trading access, no unlock window
        // Set controlDay to be recent (within controlPeriod, so unlock window is not active)
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        uint256 recentControlDay = block.timestamp - Constants.MIN_CONTROL_PERIOD / 2;
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(recentControlDay));

        // Ensure we're not in trading access window
        uint256 slotLockEndTime = _stdStore.target(address(proofOfCapital)).sig("lockEndTime()").find();
        vm.store(address(proofOfCapital), bytes32(slotLockEndTime), bytes32(block.timestamp + 365 days));

        // Clear deferred withdrawal dates
        uint256 slotMainDeferred =
            _stdStore.target(address(proofOfCapital)).sig("mainTokenDeferredWithdrawalDate()").find();
        vm.store(address(proofOfCapital), bytes32(slotMainDeferred), bytes32(0));
        uint256 slotSupportDeferred =
            _stdStore.target(address(proofOfCapital)).sig("supportTokenDeferredWithdrawalDate()").find();
        vm.store(address(proofOfCapital), bytes32(slotSupportDeferred), bytes32(0));

        uint256 controlDayBefore = proofOfCapital.controlDay();

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetTokenBalanceProcessed(amount);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(amount);

        assertEq(
            proofOfCapital.unaccountedOffsetTokenBalance(),
            initialUnaccountedBalance - amount,
            "unaccountedOffsetTokenBalance should decrease by amount"
        );
        // controlDay should NOT be increased (unlock window not active)
        assertEq(
            proofOfCapital.controlDay(),
            controlDayBefore,
            "controlDay should not change when unlock window is not active"
        );
    }

    /**
     * @dev Test error: InsufficientUnaccountedOffsetTokenBalance when amount exceeds balance
     */
    function testCalculateUnaccountedOffsetTokenBalance_Reverts_WhenAmountExceedsBalance() public {
        uint256 currentBalance = proofOfCapital.unaccountedOffsetTokenBalance();
        uint256 excessiveAmount = currentBalance + 1;

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.expectRevert(ProofOfCapital.InsufficientUnaccountedOffsetTokenBalance.selector);
        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(excessiveAmount);
    }

    /**
     * @dev Test that non-owner cannot call when trading access is not available
     * Note: When trading access is available, anyone can call, but when it's not, only owner can
     */
    function testCalculateUnaccountedOffsetTokenBalance_Reverts_WhenNonOwnerCallsWithoutTradingAccess() public {
        uint256 amount = 1000e18;

        // Setup: No trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        uint256 futureControlDay = block.timestamp + 1 days;
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(futureControlDay));

        uint256 slotLockEndTime = _stdStore.target(address(proofOfCapital)).sig("lockEndTime()").find();
        vm.store(address(proofOfCapital), bytes32(slotLockEndTime), bytes32(block.timestamp + 365 days));

        // Clear deferred withdrawal dates
        uint256 slotMainDeferred =
            _stdStore.target(address(proofOfCapital)).sig("mainTokenDeferredWithdrawalDate()").find();
        vm.store(address(proofOfCapital), bytes32(slotMainDeferred), bytes32(0));
        uint256 slotSupportDeferred =
            _stdStore.target(address(proofOfCapital)).sig("supportTokenDeferredWithdrawalDate()").find();
        vm.store(address(proofOfCapital), bytes32(slotSupportDeferred), bytes32(0));

        // Non-owner should not be able to call
        vm.expectRevert();
        vm.prank(nonOwner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(amount);
    }

    /**
     * @dev Test that anyone can call when trading access is available
     */
    function testCalculateUnaccountedOffsetTokenBalance_Success_WhenNonOwnerCallsWithTradingAccess() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffsetTokenBalance();
        uint256 amount = 1000e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient unaccounted balance");

        // Setup trading access by ensuring lockEndTime is within 60 days
        // This makes _checkTradingAccess() return true via lockEndTime < block.timestamp + Constants.SIXTY_DAYS
        uint256 slotLockEndTime = _stdStore.target(address(proofOfCapital)).sig("lockEndTime()").find();
        uint256 nearLockEndTime = block.timestamp + Constants.SIXTY_DAYS - 1 days;
        vm.store(address(proofOfCapital), bytes32(slotLockEndTime), bytes32(nearLockEndTime));

        // Also set controlDay to be in the past to ensure _checkControlDay() returns true
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        // Non-owner should be able to call when trading access is available
        vm.prank(nonOwner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(amount);

        assertEq(
            proofOfCapital.unaccountedOffsetTokenBalance(),
            initialUnaccountedBalance - amount,
            "unaccountedOffsetTokenBalance should decrease by amount"
        );
    }

    /**
     * @dev Test that _calculateChangeOffsetToken is called correctly and updates state
     */
    function testCalculateUnaccountedOffsetTokenBalance_UpdatesOffsetState() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffsetTokenBalance();
        uint256 initialOffsetStep = proofOfCapital.offsetStep();
        uint256 initialOffsetTokens = proofOfCapital.offsetTokens();
        uint256 initialTotalTokensSold = proofOfCapital.totalTokensSold();

        uint256 amount = 1000e18;
        require(initialUnaccountedBalance >= amount, "Test setup: insufficient balance");

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(amount);

        // Verify that offset state was updated by _calculateChangeOffsetToken
        // offsetStep should decrease or stay the same (going backwards)
        assertLe(proofOfCapital.offsetStep(), initialOffsetStep, "offsetStep should decrease or stay the same");

        // offsetTokens should decrease
        assertEq(proofOfCapital.offsetTokens(), initialOffsetTokens - amount, "offsetTokens should decrease by amount");

        // totalTokensSold should decrease
        assertEq(
            proofOfCapital.totalTokensSold(),
            initialTotalTokensSold - amount,
            "totalTokensSold should decrease by amount"
        );

        // currentStep, currentPrice, quantityTokensPerLevel should be updated to match offset values
        assertEq(proofOfCapital.currentStep(), proofOfCapital.offsetStep(), "currentStep should match offsetStep");
        assertEq(proofOfCapital.currentPrice(), proofOfCapital.offsetPrice(), "currentPrice should match offsetPrice");
        assertEq(
            proofOfCapital.quantityTokensPerLevel(),
            proofOfCapital.sizeOffsetStep(),
            "quantityTokensPerLevel should match sizeOffsetStep"
        );
        assertEq(
            proofOfCapital.remainderOfStep(),
            proofOfCapital.remainderOffsetTokens(),
            "remainderOfStep should match remainderOffsetTokens"
        );
    }

    /**
     * @dev Test event emission
     */
    function testCalculateUnaccountedOffsetTokenBalance_EmitsEvent() public {
        uint256 amount = 1000e18;
        uint256 initialBalance = proofOfCapital.unaccountedOffsetTokenBalance();
        require(initialBalance >= amount, "Test setup: insufficient balance");

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetTokenBalanceProcessed(amount);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(amount);
    }

    /**
     * @dev Test that function reverts when unaccountedOffsetTokenBalance is zero
     */
    function testCalculateUnaccountedOffsetTokenBalance_Reverts_WhenBalanceIsZero() public {
        // Create a contract with zero unaccountedOffsetTokenBalance
        // We'll set it directly via storage manipulation
        uint256 slotUnaccounted =
            _stdStore.target(address(proofOfCapital)).sig("unaccountedOffsetTokenBalance()").find();
        vm.store(address(proofOfCapital), bytes32(slotUnaccounted), bytes32(0));

        assertEq(proofOfCapital.unaccountedOffsetTokenBalance(), 0, "Balance should be zero");

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        // Try to process - should revert
        vm.expectRevert(ProofOfCapital.InsufficientUnaccountedOffsetTokenBalance.selector);
        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetTokenBalance(1);
    }

    // Helper event declaration for testing
    event UnaccountedOffsetTokenBalanceProcessed(uint256 amount);
}

