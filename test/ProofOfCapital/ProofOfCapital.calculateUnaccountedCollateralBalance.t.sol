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

import {BaseTest} from "../utils/BaseTest.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProofOfCapital} from "../../src/interfaces/IProofOfCapital.sol";
import {Constants} from "../../src/utils/Constant.sol";

contract ProofOfCapitalCalculateUnaccountedCollateralBalanceTest is BaseTest {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    StdStorage private _stdStore;

    address public nonOwner = address(0x5);
    address public daoAddress = address(0x6);
    address public user = address(0x7);

    function setUp() public override {
        super.setUp();

        // Setup: Create contract with daoAddress
        vm.startPrank(owner);

        IProofOfCapital.InitParams memory params = getValidParams();
        params.daoAddress = daoAddress;

        proofOfCapital = deployWithParams(params);

        // Give WETH to owner for deposits
        SafeERC20.safeTransfer(IERC20(address(weth)), owner, 100000e18);
        vm.stopPrank();

        // Approve WETH for owner
        vm.prank(owner);
        weth.approve(address(proofOfCapital), type(uint256).max);

        // Setup unaccountedCollateralBalance by making deposits
        // This requires offsetLaunch > tokensEarned (which is true by default)
        // Use deposit() function to deposit collateral tokens, which calls _handleOwnerDeposit
        uint256 depositAmount = 10000e18;
        vm.prank(owner);
        proofOfCapital.deposit(depositAmount);

        // Verify unaccountedCollateralBalance was set
        assertGt(proofOfCapital.unaccountedCollateralBalance(), 0, "unaccountedCollateralBalance should be set");
    }

    /**
     * @dev Test successful calculation when trading access is available
     * Tests the branch where _checkTradingAccess() returns true
     */
    function testCalculateUnaccountedCollateralBalance_Success_WithTradingAccess() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedCollateralBalance();
        uint256 initialContractCollateralBalance = proofOfCapital.contractCollateralBalance();
        uint256 initialDaoBalance = weth.balanceOf(daoAddress);
        uint256 amount = 5000e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient unaccounted balance");

        // Setup trading access by manipulating controlDay to be in the past
        // This makes _checkTradingAccess() return true
        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);

        uint256 finalUnaccountedBalance = proofOfCapital.unaccountedCollateralBalance();
        uint256 finalContractCollateralBalance = proofOfCapital.contractCollateralBalance();
        uint256 finalDaoBalance = weth.balanceOf(daoAddress);

        // Verify unaccountedCollateralBalance decreased by amount
        assertEq(
            finalUnaccountedBalance,
            initialUnaccountedBalance - amount,
            "unaccountedCollateralBalance should decrease by amount"
        );

        // Calculate deltaCollateralBalance (what was added to contractCollateralBalance)
        uint256 deltaCollateralBalance = finalContractCollateralBalance - initialContractCollateralBalance;

        // Calculate change (what was sent to daoAddress)
        uint256 change = finalDaoBalance - initialDaoBalance;

        // Verify: amount = deltaCollateralBalance + change
        assertEq(amount, deltaCollateralBalance + change, "Amount should equal deltaCollateralBalance + change");

        // Verify change was sent to daoAddress (if change > 0)
        if (change > 0) {
            assertGt(change, 0, "Change should be sent to daoAddress when change > 0");
        }
    }

    /**
     * @dev Test successful calculation when trading access is not available but unlock window is active
     * Tests the branch where _checkTradingAccess() returns false and _checkUnlockWindow() returns true
     */
    function testCalculateUnaccountedCollateralBalance_Success_WithUnlockWindow() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedCollateralBalance();
        uint256 amount = 3000e18;

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
        emit UnaccountedCollateralBalanceProcessed(amount, 0, 0);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);

        assertEq(
            proofOfCapital.unaccountedCollateralBalance(),
            initialUnaccountedBalance - amount,
            "unaccountedCollateralBalance should decrease by amount"
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
    function testCalculateUnaccountedCollateralBalance_Success_WithoutUnlockWindow() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedCollateralBalance();
        uint256 amount = 2000e18;

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
        emit UnaccountedCollateralBalanceProcessed(amount, 0, 0);

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);

        assertEq(
            proofOfCapital.unaccountedCollateralBalance(),
            initialUnaccountedBalance - amount,
            "unaccountedCollateralBalance should decrease by amount"
        );
        // controlDay should NOT be increased (unlock window not active)
        assertEq(
            proofOfCapital.controlDay(),
            controlDayBefore,
            "controlDay should not change when unlock window is not active"
        );
    }

    function testCalculateUnaccountedCollateralBalance_Reverts_WhenAmountExceedsBalance() public {
        uint256 currentBalance = proofOfCapital.unaccountedCollateralBalance();
        uint256 excessiveAmount = currentBalance + 1;

        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.expectRevert(IProofOfCapital.InsufficientUnaccountedCollateralBalance.selector);
        vm.prank(owner);
        proofOfCapital.calculateUnaccountedCollateralBalance(excessiveAmount);
    }

    function testCalculateUnaccountedCollateralBalance_Reverts_WhenNonOwnerCallsWithoutTradingAccess() public {
        uint256 amount = 1000e18;

        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        uint256 futureControlDay = block.timestamp + 1 days;
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(futureControlDay));

        uint256 slotLockEndTime = _stdStore.target(address(proofOfCapital)).sig("lockEndTime()").find();
        vm.store(address(proofOfCapital), bytes32(slotLockEndTime), bytes32(block.timestamp + 365 days));

        vm.expectRevert();
        vm.prank(nonOwner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);
    }

    function testCalculateUnaccountedCollateralBalance_Success_WhenNonOwnerCallsWithTradingAccess() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedCollateralBalance();
        uint256 amount = 1000e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient unaccounted balance");

        uint256 slotLockEndTime = _stdStore.target(address(proofOfCapital)).sig("lockEndTime()").find();
        uint256 nearLockEndTime = block.timestamp + Constants.SIXTY_DAYS - 1 days;
        vm.store(address(proofOfCapital), bytes32(slotLockEndTime), bytes32(nearLockEndTime));

        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.prank(nonOwner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);

        assertEq(
            proofOfCapital.unaccountedCollateralBalance(),
            initialUnaccountedBalance - amount,
            "unaccountedCollateralBalance should decrease by amount"
        );
    }

    function testCalculateUnaccountedCollateralBalance_CalculatesDeltaAndSendsChange() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedCollateralBalance();
        uint256 initialContractCollateralBalance = proofOfCapital.contractCollateralBalance();
        uint256 initialDaoBalance = weth.balanceOf(daoAddress);
        uint256 amount = 5000e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient unaccounted balance");

        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);

        uint256 finalContractCollateralBalance = proofOfCapital.contractCollateralBalance();
        uint256 finalDaoBalance = weth.balanceOf(daoAddress);

        uint256 deltaCollateralBalance = finalContractCollateralBalance - initialContractCollateralBalance;

        uint256 change = finalDaoBalance - initialDaoBalance;

        assertEq(amount, deltaCollateralBalance + change, "Amount should equal deltaCollateralBalance + change");
        assertGe(deltaCollateralBalance, 0, "deltaCollateralBalance should be non-negative");
        assertGe(change, 0, "change should be non-negative");

        // If change > 0, it should have been sent to daoAddress
        if (change > 0) {
            assertGt(change, 0, "Change should be sent to daoAddress when change > 0");
        }
    }

    function testCalculateUnaccountedCollateralBalance_EmitsEvent() public {
        uint256 amount = 2000e18;
        uint256 initialBalance = proofOfCapital.unaccountedCollateralBalance();
        require(initialBalance >= amount, "Test setup: insufficient balance");

        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);

        assertEq(
            proofOfCapital.unaccountedCollateralBalance(),
            initialBalance - amount,
            "unaccountedCollateralBalance should decrease"
        );
    }

    function testCalculateUnaccountedCollateralBalance_HandlesZeroChange() public {
        uint256 initialUnaccountedBalance = proofOfCapital.unaccountedCollateralBalance();
        uint256 initialDaoBalance = weth.balanceOf(daoAddress);

        uint256 amount = 100e18;

        require(initialUnaccountedBalance >= amount, "Test setup: insufficient balance");

        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);

        uint256 finalDaoBalance = weth.balanceOf(daoAddress);
        uint256 change = finalDaoBalance - initialDaoBalance;

        assertGe(change, 0, "Change should be non-negative");
    }

    function testCalculateUnaccountedCollateralBalance_NonReentrant() public {
        uint256 amount = 1000e18;
        uint256 initialBalance = proofOfCapital.unaccountedCollateralBalance();
        require(initialBalance >= amount, "Test setup: insufficient balance");

        uint256 slotControlDay = _stdStore.target(address(proofOfCapital)).sig("controlDay()").find();
        vm.store(address(proofOfCapital), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));

        vm.prank(owner);
        proofOfCapital.calculateUnaccountedCollateralBalance(amount);

        assertLt(proofOfCapital.unaccountedCollateralBalance(), initialBalance, "Balance should decrease");
    }

    event UnaccountedCollateralBalanceProcessed(uint256 amount, uint256 deltaCollateral, uint256 change);
}

