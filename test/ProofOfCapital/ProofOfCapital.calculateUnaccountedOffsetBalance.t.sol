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
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract ProofOfCapitalCalculateUnaccountedOffsetBalanceTest is BaseTest {
    using stdStorage for StdStorage;

    StdStorage private _stdStore;

    address public nonOwner = address(0x5);
    address public user = address(0x6);

    function setUp() public override {
        super.setUp();

        // Ensure contract has unaccountedOffset set (from initialization with offsetLaunch > 0)
        assertGt(proofOfCapital.unaccountedOffset(), 0, "unaccountedOffset should be set");
        assertFalse(proofOfCapital.isInitialized(), "Contract should not be initialized initially");
    }

    /**
     * @dev Test successful calculation when trading access is available
     * Tests the branch where _checkTradingAccess() returns true
     */
    function testCalculateUnaccountedOffsetBalance_Success_WithTradingAccess() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffset();
        uint256 initialContractTokenBalance = proofOfCapital.launchBalance();
        uint256 initialTotalTokensSold = proofOfCapital.totalLaunchSold();
        uint256 initialOffsetStep = proofOfCapital.offsetStep();
        uint256 amount = 1000e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient unaccounted balance");

        // Setup trading access by manipulating controlDay to be in the past
        // This makes _checkTradingAccess() return true
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetBalanceProcessed(amount);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetBalance(amount);

        assertEq(
            proofOfCapital.unaccountedOffset(),
            initialUnaccountedBalance - amount,
            "unaccountedOffset should decrease by amount"
        );
        assertEq(
            proofOfCapital.launchBalance(),
            initialContractTokenBalance + amount,
            "launchBalance should increase by amount"
        );
        assertEq(
            proofOfCapital.totalLaunchSold(),
            initialTotalTokensSold + amount,
            "totalLaunchSold should increase by amount"
        );
        assertGe(proofOfCapital.offsetStep(), initialOffsetStep, "offsetStep should increase or stay the same");
    }

    /**
     * @dev Test successful calculation when trading access is not available but unlock window is active
     * Tests the branch where _checkTradingAccess() returns false and _checkUnlockWindow() returns true
     */
    function testCalculateUnaccountedOffsetBalance_Success_WithUnlockWindow() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffset();
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

        uint256 controlDayBefore = proofOfCapital.controlDay();

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetBalanceProcessed(amount);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetBalance(amount);

        assertEq(
            proofOfCapital.unaccountedOffset(),
            initialUnaccountedBalance - amount,
            "unaccountedOffset should decrease by amount"
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
    function testCalculateUnaccountedOffsetBalance_Success_WithoutUnlockWindow() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffset();
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

        uint256 controlDayBefore = proofOfCapital.controlDay();

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetBalanceProcessed(amount);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetBalance(amount);

        assertEq(
            proofOfCapital.unaccountedOffset(),
            initialUnaccountedBalance - amount,
            "unaccountedOffset should decrease by amount"
        );
        // controlDay should NOT be increased (unlock window not active)
        assertEq(
            proofOfCapital.controlDay(),
            controlDayBefore,
            "controlDay should not change when unlock window is not active"
        );
    }

    /**
     * @dev Test that function sets isInitialized to true when unaccountedOffset becomes zero
     */
    function testCalculateUnaccountedOffsetBalance_SetsInitialized_WhenBalanceBecomesZero() public {
        uint256 remainingBalance = proofOfCapital.unaccountedOffset();
        require(remainingBalance > 0, "Test setup: unaccountedOffset must be greater than 0");

        assertFalse(proofOfCapital.isInitialized(), "Contract should not be initialized before");

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetBalanceProcessed(remainingBalance);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetBalance(remainingBalance);

        assertEq(proofOfCapital.unaccountedOffset(), 0, "unaccountedOffset should be zero");
        assertTrue(proofOfCapital.isInitialized(), "Contract should be initialized when unaccountedOffset becomes zero");
    }

    /**
     * @dev Test error: UnaccountedOffsetBalanceNotSet when unaccountedOffset is zero
     */
    function testCalculateUnaccountedOffsetBalance_Reverts_ContractAlreadyInitialized() public {
        // Create a new contract with zero offsetLaunch to get zero unaccountedOffset
        IProofOfCapital.InitParams memory params = getValidParams();
        params.offsetLaunch = 0; // No offset tokens

        vm.startPrank(owner);
        ProofOfCapital newContract = new ProofOfCapital(params);
        vm.stopPrank();

        // New contract should have isInitialized = true and unaccountedOffset = 0
        assertTrue(newContract.isInitialized(), "Contract should be initialized when offsetLaunch is 0");
        assertEq(newContract.unaccountedOffset(), 0, "Balance should be zero");

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(newContract)).sig("controlDay()").find();
        vm.store(address(newContract), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        // Try to process - should revert with UnaccountedOffsetBalanceNotSet
        vm.expectRevert(IProofOfCapital.ContractAlreadyInitialized.selector);
        vm.prank(owner);
        newContract.calculateUnaccountedOffsetBalance(1000e18);
    }

    /**
     * @dev Test error: InsufficientUnaccountedOffsetBalance when amount exceeds balance
     */
    function testCalculateUnaccountedOffsetBalance_Reverts_WhenAmountExceedsBalance() public {
        uint256 currentBalance = proofOfCapital.unaccountedOffset();
        uint256 excessiveAmount = currentBalance + 1;

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.expectRevert(IProofOfCapital.InsufficientUnaccountedOffsetBalance.selector);
        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetBalance(excessiveAmount);
    }

    /**
     * @dev Test that non-owner cannot call when trading access is not available
     * Note: When trading access is available, anyone can call, but when it's not, only owner can
     */
    function testCalculateUnaccountedOffsetBalance_Reverts_WhenNonOwnerCallsWithoutTradingAccess() public {
        uint256 amount = 1000e18;

        // Setup: No trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        uint256 futureControlDay = block.timestamp + 1 days;
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(futureControlDay));

        uint256 slotLockEndTime = _stdStore.target(address(proofOfCapital)).sig("lockEndTime()").find();
        vm.store(address(proofOfCapital), bytes32(slotLockEndTime), bytes32(block.timestamp + 365 days));

        // Non-owner should not be able to call
        vm.expectRevert();
        vm.prank(nonOwner);
        proofOfCapital.calculateUnaccountedOffsetBalance(amount);
    }

    /**
     * @dev Test that _calculateOffset is called correctly and updates state
     */
    function testCalculateUnaccountedOffsetBalance_UpdatesOffsetState() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedOffset();
        uint256 initialOffsetStep = proofOfCapital.offsetStep();
        uint256 initialOffsetPrice = proofOfCapital.offsetPrice();
        uint256 initialRemainderOffsetTokens = proofOfCapital.remainderOfStepOffset();
        uint256 initialSizeOffsetStep = proofOfCapital.quantityTokensPerLevelOffset();
        uint256 initialCurrentStep = proofOfCapital.currentStep();
        uint256 initialCurrentPrice = proofOfCapital.currentPrice();
        uint256 initialQuantityTokensPerLevel = proofOfCapital.quantityTokensPerLevel();
        uint256 initialRemainderOfStep = proofOfCapital.remainderOfStep();

        uint256 amount = 1000e18;
        require(initialUnaccountedBalance >= amount, "Test setup: insufficient balance");

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetBalance(amount);

        // Verify that offset state was updated by _calculateOffset
        // offsetStep should increase or stay the same (depending on amount)
        assertGe(proofOfCapital.offsetStep(), initialOffsetStep, "offsetStep should increase or stay the same");

        // offsetPrice should increase or stay the same
        assertGe(proofOfCapital.offsetPrice(), initialOffsetPrice, "offsetPrice should increase or stay the same");

        // currentStep, currentPrice, quantityTokensPerLevel should be updated to match offset values
        assertEq(proofOfCapital.currentStep(), proofOfCapital.offsetStep(), "currentStep should match offsetStep");
        assertEq(proofOfCapital.currentPrice(), proofOfCapital.offsetPrice(), "currentPrice should match offsetPrice");
        assertEq(
            proofOfCapital.quantityTokensPerLevel(),
            proofOfCapital.quantityTokensPerLevelOffset(),
            "quantityTokensPerLevel should match quantityTokensPerLevelOffset"
        );
        assertEq(
            proofOfCapital.remainderOfStep(),
            proofOfCapital.remainderOfStepOffset(),
            "remainderOfStep should match remainderOfStepOffset"
        );
    }

    /**
     * @dev Test event emission
     */
    function testCalculateUnaccountedOffsetBalance_EmitsEvent() public {
        uint256 amount = 1000e18;
        uint256 initialBalance = proofOfCapital.unaccountedOffset();
        require(initialBalance >= amount, "Test setup: insufficient balance");

        // Setup trading access
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.expectEmit(true, false, false, false);
        emit UnaccountedOffsetBalanceProcessed(amount);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedOffsetBalance(amount);
    }

    // Helper event declaration for testing
    event UnaccountedOffsetBalanceProcessed(uint256 amount);
}

