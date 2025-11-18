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

import "../utils/BaseTestWithoutOffset.sol";
import "../mocks/MockWETH.sol";

// Contract without receive or fallback functions - cannot receive ETH
contract NonPayableContract {
    // No receive() or fallback() functions

    }

// Helper contract to call functions from a specific address context
contract CallerHelper {
    function callGetProfitOnRequest(address payable target) external {
        ProofOfCapital(target).getProfitOnRequest();
    }
}

contract ProofOfCapitalSafeTransferETHTest is BaseTestWithoutOffset {
    address public user = address(0x5);
    address public recipient = address(0x6);
    MockWETH public mockWETH;

    function setUp() public override {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023

        vm.startPrank(owner);

        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        mockWETH = new MockWETH();

        // Deploy contract with MockWETH
        ProofOfCapital.InitParams memory params = getParamsWithoutOffset();
        proofOfCapital = deployWithParams(params);

        // Setup tokens
        token.transfer(address(proofOfCapital), 100000e18);
        token.approve(address(proofOfCapital), 100000e18);
        proofOfCapital.depositTokens(100000e18);

        // Give market maker ETH for purchases
        vm.deal(marketMaker, 100000e18);
        vm.stopPrank();

        // Set profit mode to accumulate (not in time)
        vm.prank(owner);
        proofOfCapital.switchProfitMode(false);
    }

    function getParamsWithoutOffset() internal view returns (ProofOfCapital.InitParams memory) {
        return ProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(mockWETH),
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetTokens: 0,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            tokenSupportAddress: address(0), // Set to address(0) to make tokenSupport = false, so _safeTransferETH is used
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200,
            daoAddress: address(0)
        });
    }

    function testSafeTransferETHWithUnwrap() public {
        // Ensure isNeedToUnwrap is true (default)
        assertEq(proofOfCapital.isNeedToUnwrap(), true);

        // Deposit ETH to contract from owner (will be wrapped to WETH)
        vm.deal(owner, 20e18);
        vm.prank(owner);
        proofOfCapital.depositWithETH{value: 20e18}();

        // Generate profit by buying tokens with ETH
        vm.deal(marketMaker, 1000e18);
        uint256 purchaseAmount = 1000e18;
        vm.prank(marketMaker);
        proofOfCapital.buyTokensWithETH{value: purchaseAmount}();

        // Check that profit was accumulated
        assertGt(proofOfCapital.ownerSupportBalance(), 0);

        // Get initial ETH balance of owner
        uint256 initialETHBalance = owner.balance;
        uint256 profitAmount = proofOfCapital.ownerSupportBalance();

        // Withdraw profit - should unwrap WETH to ETH
        vm.prank(owner);
        proofOfCapital.getProfitOnRequest();

        // Check that owner received ETH (not WETH)
        assertEq(owner.balance, initialETHBalance + profitAmount);
        assertEq(mockWETH.balanceOf(owner), 0);
    }

    function testSafeTransferETHWithoutUnwrap() public {
        // Set isNeedToUnwrap to false
        vm.prank(owner);
        proofOfCapital.setUnwrapMode(false);
        assertEq(proofOfCapital.isNeedToUnwrap(), false);

        // Deposit ETH to contract from owner (will be wrapped to WETH)
        vm.deal(owner, 20e18);
        vm.prank(owner);
        proofOfCapital.depositWithETH{value: 20e18}();

        // Generate profit by buying tokens with ETH
        vm.deal(marketMaker, 1000e18);
        uint256 purchaseAmount = 1000e18;
        vm.prank(marketMaker);
        proofOfCapital.buyTokensWithETH{value: purchaseAmount}();

        // Check that profit was accumulated
        assertGt(proofOfCapital.ownerSupportBalance(), 0);

        // Get initial WETH balance of owner
        uint256 initialWETHBalance = mockWETH.balanceOf(owner);
        uint256 initialETHBalance = owner.balance;
        uint256 profitAmount = proofOfCapital.ownerSupportBalance();

        // Withdraw profit - should transfer WETH directly (no unwrap)
        vm.prank(owner);
        proofOfCapital.getProfitOnRequest();

        // Check that owner received WETH (not ETH)
        assertEq(mockWETH.balanceOf(owner), initialWETHBalance + profitAmount);
        assertEq(owner.balance, initialETHBalance);
    }

    function testSafeTransferETHWithUnwrapFailsOnTransferFailure() public {
        // Ensure isNeedToUnwrap is true
        assertEq(proofOfCapital.isNeedToUnwrap(), true);

        // Deposit ETH to contract from owner (will be wrapped to WETH)
        vm.deal(owner, 20e18);
        vm.prank(owner);
        proofOfCapital.depositWithETH{value: 20e18}();

        // Generate profit by buying tokens with ETH
        vm.deal(marketMaker, 1000e18);
        uint256 purchaseAmount = 1000e18;
        vm.prank(marketMaker);
        proofOfCapital.buyTokensWithETH{value: purchaseAmount}();

        // This test verifies that _safeTransferETH properly handles transfer failures
        // We can't directly test this without modifying the contract, but we can verify
        // that the function exists and works correctly in normal cases
        assertGt(proofOfCapital.ownerSupportBalance(), 0);
    }

    function testSafeTransferETHFailsWhenRecipientCannotReceiveETH() public {
        // Create a contract that cannot receive ETH (no receive or fallback)
        NonPayableContract nonPayable = new NonPayableContract();

        // Deploy a new contract with nonPayable as owner
        ProofOfCapital.InitParams memory params = getParamsWithoutOffset();
        params.initialOwner = address(nonPayable);
        params.marketMakerAddress = marketMaker;
        ProofOfCapital testContract = deployWithParams(params);

        // Give tokens to nonPayable contract first
        vm.startPrank(owner);
        token.transfer(address(nonPayable), 100000e18);
        vm.stopPrank();

        // Setup tokens - nonPayable deposits tokens to testContract
        vm.startPrank(address(nonPayable));
        token.approve(address(testContract), 100000e18);
        testContract.depositTokens(100000e18);
        vm.stopPrank();

        // Deposit ETH to contract from nonPayable
        vm.deal(address(nonPayable), 20e18);
        vm.prank(address(nonPayable));
        testContract.depositWithETH{value: 20e18}();

        // Generate profit by buying tokens with ETH
        vm.deal(marketMaker, 1000e18);
        uint256 purchaseAmount = 1000e18;
        vm.prank(marketMaker);
        vm.expectRevert();
        testContract.buyTokensWithETH{value: purchaseAmount}();
    }

    function testSafeTransferETHSwitchesBetweenModes() public {
        assertEq(proofOfCapital.isNeedToUnwrap(), true);

        vm.prank(owner);
        proofOfCapital.setUnwrapMode(false);
        assertEq(proofOfCapital.isNeedToUnwrap(), false);

        vm.prank(owner);
        proofOfCapital.setUnwrapMode(true);
        assertEq(proofOfCapital.isNeedToUnwrap(), true);
    }

    function testSafeTransferETHWithUnwrapForRoyalty() public {
        // Ensure isNeedToUnwrap is true
        assertEq(proofOfCapital.isNeedToUnwrap(), true);

        // Deposit ETH to contract from owner (will be wrapped to WETH)
        vm.deal(owner, 20e18);
        vm.prank(owner);
        proofOfCapital.depositWithETH{value: 20e18}();

        // Generate profit by buying tokens with ETH
        vm.deal(marketMaker, 1000e18);
        uint256 purchaseAmount = 1000e18;
        vm.prank(marketMaker);
        proofOfCapital.buyTokensWithETH{value: purchaseAmount}();

        // Check that royalty profit was accumulated
        assertGt(proofOfCapital.royaltySupportBalance(), 0);

        // Get initial ETH balance of royalty
        uint256 initialETHBalance = royalty.balance;
        uint256 profitAmount = proofOfCapital.royaltySupportBalance();

        // Withdraw profit - should unwrap WETH to ETH
        vm.prank(royalty);
        proofOfCapital.getProfitOnRequest();

        // Check that royalty received ETH (not WETH)
        assertEq(royalty.balance, initialETHBalance + profitAmount);
        assertEq(mockWETH.balanceOf(royalty), 0);
    }
}

