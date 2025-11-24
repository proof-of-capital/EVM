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
import {IProofOfCapital} from "../../src/interfaces/IProofOfCapital.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProofOfCapitalWithdrawAllCollateralTokensTest is BaseTest {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    StdStorage private _stdStore;

    /**
     * @dev Test successful withdrawal of all collateral tokens
     * Tests lines 754-759: successful case where:
     * - withdrawnAmount = contractCollateralBalance
     * - contractCollateralBalance is set to 0
     * - isActive is set to false
     * - Collateral tokens are transferred to daoAddress
     * - AllCollateralTokensWithdrawn event is emitted
     */
    function testWithdrawAllCollateralTokensSuccess() public {
        // Step 1: Create contractCollateralBalance by directly setting it via storage manipulation
        // This is simpler and avoids complex setup requirements
        uint256 collateralBalanceAmount = 5000e18;
        uint256 slotContractCollateralBalance =
            _stdStore.target(address(proofOfCapital)).sig("contractCollateralBalance()").find();
        vm.store(address(proofOfCapital), bytes32(slotContractCollateralBalance), bytes32(collateralBalanceAmount));

        // Also transfer WETH to contract so it has tokens to transfer
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(weth)), address(proofOfCapital), collateralBalanceAmount);
        vm.stopPrank();

        // Step 2: Move time past lock end time
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1);

        // Step 3: Record initial state
        uint256 initialCollateralBalance = proofOfCapital.contractCollateralBalance();
        bool initialIsActive = proofOfCapital.isActive();
        address dao = proofOfCapital.daoAddress();
        uint256 daoBalanceBefore = weth.balanceOf(dao);

        // Verify preconditions
        assertTrue(initialCollateralBalance > 0, "Should have collateral balance");
        assertTrue(initialIsActive, "Contract should be active initially");
        assertEq(dao, owner, "DAO should be owner by default");

        // Step 4: Withdraw all collateral tokens (only DAO can call this)
        vm.expectEmit(true, false, false, true);
        emit IProofOfCapital.AllCollateralTokensWithdrawn(dao, initialCollateralBalance);

        vm.prank(dao);
        proofOfCapital.withdrawAllCollateralTokens();

        // Step 5: Verify state changes
        // Verify contractCollateralBalance is set to 0 (line 755)
        assertEq(
            proofOfCapital.contractCollateralBalance(), 0, "contractCollateralBalance should be zero after withdrawal"
        );

        // Verify isActive is set to false (line 756)
        assertFalse(proofOfCapital.isActive(), "isActive should be false after withdrawal");

        // Verify tokens were transferred to daoAddress (line 757)
        uint256 daoBalanceAfter = weth.balanceOf(dao);
        assertEq(
            daoBalanceAfter, daoBalanceBefore + initialCollateralBalance, "DAO should receive all collateral tokens"
        );

        // Verify withdrawnAmount equals initial collateral balance (line 754)
        // This is implicit in the transfer check above
    }
}

