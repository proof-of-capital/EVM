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

contract ProofOfCapitalOnlyActiveContractTest is BaseTest {
    using stdStorage for StdStorage;

    StdStorage private _stdStore;
    address public user = address(0x5);

    function setUp() public override {
        super.setUp();

        // Setup tokens for users
        vm.startPrank(owner);
        token.transfer(address(proofOfCapital), 500000e18);
        token.transfer(returnWallet, 50000e18);
        token.transfer(user, 50000e18);
        token.transfer(marketMaker, 50000e18);
        weth.transfer(user, 50000e18);
        weth.transfer(marketMaker, 50000e18);

        // Enable market maker for user to allow trading
        proofOfCapital.setMarketMaker(user, true);

        vm.stopPrank();

        // Approve tokens for all users
        vm.prank(user);
        token.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(returnWallet);
        token.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(marketMaker);
        token.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(user);
        weth.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(marketMaker);
        weth.approve(address(proofOfCapital), type(uint256).max);
    }

    // Test that onlyActiveContract modifier reverts with ContractNotActive error
    // This test verifies that the modifier on line 251-252 of ProofOfCapital.sol works correctly
    // by deactivating the contract through withdrawAllCollateralTokens and then testing functions
    function testOnlyActiveContractModifier() public {
        // Ensure contract is active initially
        assertTrue(proofOfCapital.isActive(), "Contract should be active initially");

        // Setup: Create collateral balance and move time to after lock end
        vm.startPrank(owner);
        weth.transfer(address(proofOfCapital), 10000e18);
        // Set contractCollateralBalance using storage manipulation
        uint256 slotCollateralBalance = _stdStore.target(address(proofOfCapital)).sig("contractCollateralBalance()").find();
        vm.store(address(proofOfCapital), bytes32(slotCollateralBalance), bytes32(uint256(10000e18)));
        vm.stopPrank();

        // Move time to after lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1 days);

        // Deactivate contract by withdrawing all collateral tokens
        vm.prank(owner); // owner is DAO by default
        proofOfCapital.withdrawAllCollateralTokens();

        // Verify contract is now inactive
        assertFalse(proofOfCapital.isActive(), "Contract should be deactivated");

        // Test that buyTokens reverts when contract is not active
        // Setup: Give user WETH and approve
        vm.startPrank(owner);
        weth.transfer(user, 1000e18);
        vm.stopPrank();

        vm.prank(user);
        weth.approve(address(proofOfCapital), 1000e18);

        // Try to buy tokens - should revert with ContractNotActive error
        // This tests the require(isActive, ContractNotActive()) on line 251
        vm.prank(user);
        vm.expectRevert(ProofOfCapital.ContractNotActive.selector);
        proofOfCapital.buyTokens(1000e18);
    }

    // Test that depositTokens reverts when contract is not active
    // This tests the onlyActiveContract modifier on depositTokens function
    function testDepositTokensContractNotActive() public {
        // Ensure contract is active initially
        assertTrue(proofOfCapital.isActive(), "Contract should be active initially");

        // Setup: Create collateral balance and move time to after lock end
        vm.startPrank(owner);
        weth.transfer(address(proofOfCapital), 10000e18);
        // Set contractCollateralBalance using storage manipulation
        uint256 slotCollateralBalance = _stdStore.target(address(proofOfCapital)).sig("contractCollateralBalance()").find();
        vm.store(address(proofOfCapital), bytes32(slotCollateralBalance), bytes32(uint256(10000e18)));
        vm.stopPrank();

        // Move time to after lock end
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime + 1 days);

        // Deactivate contract by withdrawing all collateral tokens
        vm.prank(owner); // owner is DAO by default
        proofOfCapital.withdrawAllCollateralTokens();

        // Verify contract is now inactive
        assertFalse(proofOfCapital.isActive(), "Contract should be deactivated");

        // Setup: Give owner tokens and approve
        vm.startPrank(owner);
        token.transfer(owner, 10000e18);
        token.approve(address(proofOfCapital), 1000e18);
        vm.stopPrank();

        // Try to deposit tokens - should revert with ContractNotActive error
        // This tests the require(isActive, ContractNotActive()) on line 251
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.ContractNotActive.selector);
        proofOfCapital.depositTokens(1000e18);
    }
}

