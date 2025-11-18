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
import "../mocks/MockWETH.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract ProofOfCapitalDepositWithETHTest is BaseTest {
    using stdStorage for StdStorage;

    StdStorage private _stdStore;
    MockWETH public mockWETH;
    ProofOfCapital public ethContract;

    function setUp() public override {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023

        vm.startPrank(owner);

        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        mockWETH = new MockWETH(); // Use MockWETH instead of MockERC20

        // Create params for ETH-based contract (tokenSupport = false)
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
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
            offsetTokens: 10000e18, // Set offset to test _handleOwnerDeposit logic
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            tokenSupportAddress: address(0x999), // Different from wethAddress to make tokenSupport = false
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0) // Will default to owner
        });

        ethContract = deployWithParams(params);

        // Give owner ETH for testing (enough for large deposits)
        vm.deal(owner, 200 ether);

        vm.stopPrank();
    }

    /**
     * @dev Test that _wrapETH correctly wraps ETH to WETH
     * Tests line 681: _wrapETH(msg.value);
     */
    function test_WrapETH_WrapsETHToWETH() public {
        uint256 depositAmount = 5 ether;
        uint256 initialWETHBalance = IERC20(address(mockWETH)).balanceOf(address(ethContract));

        vm.prank(owner);
        ethContract.depositWithETH{value: depositAmount}();

        uint256 finalWETHBalance = IERC20(address(mockWETH)).balanceOf(address(ethContract));

        // Verify that WETH balance increased by depositAmount
        assertEq(finalWETHBalance, initialWETHBalance + depositAmount, "WETH balance should increase by deposit amount");
    }

    /**
     * @dev Test that _wrapETH correctly wraps ETH to WETH with multiple deposits
     * Tests line 681: _wrapETH(msg.value);
     */
    function test_WrapETH_MultipleDeposits() public {
        uint256 firstDeposit = 2 ether;
        uint256 secondDeposit = 3 ether;
        uint256 totalDeposit = firstDeposit + secondDeposit;

        vm.startPrank(owner);
        ethContract.depositWithETH{value: firstDeposit}();
        ethContract.depositWithETH{value: secondDeposit}();
        vm.stopPrank();

        uint256 finalWETHBalance = IERC20(address(mockWETH)).balanceOf(address(ethContract));

        // Verify that WETH balance equals total deposits
        assertEq(finalWETHBalance, totalDeposit, "WETH balance should equal total deposits");
    }

    /**
     * @dev Test that _handleOwnerDeposit increases unaccountedCollateralBalance when offsetTokens > tokensEarned
     * Tests line 682: _handleOwnerDeposit(msg.value);
     */
    function test_HandleOwnerDeposit_IncreasesUnaccountedCollateralBalance_WhenOffsetTokensGreaterThanTokensEarned()
        public
    {
        // Ensure offsetTokens > tokensEarned (this is the case by default in setUp)
        assertGt(
            ethContract.offsetTokens(), ethContract.tokensEarned(), "offsetTokens should be greater than tokensEarned"
        );

        uint256 depositAmount = 5 ether;
        uint256 initialUnaccountedBalance = ethContract.unaccountedCollateralBalance();

        vm.prank(owner);
        ethContract.depositWithETH{value: depositAmount}();

        uint256 finalUnaccountedBalance = ethContract.unaccountedCollateralBalance();

        // Verify that unaccountedCollateralBalance increased by depositAmount
        assertEq(
            finalUnaccountedBalance,
            initialUnaccountedBalance + depositAmount,
            "unaccountedCollateralBalance should increase by deposit amount"
        );
    }

    /**
     * @dev Test that _handleOwnerDeposit does not increase unaccountedCollateralBalance when offsetTokens <= tokensEarned
     * Tests line 682: _handleOwnerDeposit(msg.value);
     */
    function test_HandleOwnerDeposit_DoesNotIncreaseUnaccountedCollateralBalance_WhenOffsetTokensLessThanOrEqualTokensEarned()
        public
    {
        // Set tokensEarned to be greater than or equal to offsetTokens
        // We need to manipulate the state to make tokensEarned >= offsetTokens

        // First, let's get the current offsetTokens value
        uint256 offsetTokensValue = ethContract.offsetTokens();

        // Use storage manipulation to set tokensEarned >= offsetTokens
        // This is a test scenario where offset is already earned
        uint256 slotTokensEarned = _stdStore.target(address(ethContract)).sig("tokensEarned()").find();
        vm.store(address(ethContract), bytes32(slotTokensEarned), bytes32(offsetTokensValue));

        // Verify the condition
        assertGe(ethContract.tokensEarned(), ethContract.offsetTokens(), "tokensEarned should be >= offsetTokens");

        uint256 depositAmount = 5 ether;
        uint256 initialUnaccountedBalance = ethContract.unaccountedCollateralBalance();

        vm.prank(owner);
        ethContract.depositWithETH{value: depositAmount}();

        uint256 finalUnaccountedBalance = ethContract.unaccountedCollateralBalance();

        // Verify that unaccountedCollateralBalance did not change
        assertEq(
            finalUnaccountedBalance,
            initialUnaccountedBalance,
            "unaccountedCollateralBalance should not change when offsetTokens <= tokensEarned"
        );
    }

    /**
     * @dev Test that both _wrapETH and _handleOwnerDeposit work together correctly
     * Tests lines 681-682: _wrapETH(msg.value); _handleOwnerDeposit(msg.value);
     */
    function test_WrapETHAndHandleOwnerDeposit_WorkTogether() public {
        uint256 depositAmount = 10 ether;
        uint256 initialWETHBalance = IERC20(address(mockWETH)).balanceOf(address(ethContract));
        uint256 initialUnaccountedBalance = ethContract.unaccountedCollateralBalance();

        vm.prank(owner);
        ethContract.depositWithETH{value: depositAmount}();

        uint256 finalWETHBalance = IERC20(address(mockWETH)).balanceOf(address(ethContract));
        uint256 finalUnaccountedBalance = ethContract.unaccountedCollateralBalance();

        // Verify both operations worked correctly
        assertEq(finalWETHBalance, initialWETHBalance + depositAmount, "WETH balance should increase by deposit amount");

        // Only check unaccountedCollateralBalance if offsetTokens > tokensEarned
        if (ethContract.offsetTokens() > ethContract.tokensEarned()) {
            assertEq(
                finalUnaccountedBalance,
                initialUnaccountedBalance + depositAmount,
                "unaccountedCollateralBalance should increase by deposit amount"
            );
        }
    }

    /**
     * @dev Test that _wrapETH correctly handles different ETH amounts
     * Tests line 681: _wrapETH(msg.value);
     */
    function test_WrapETH_HandlesDifferentAmounts() public {
        uint256 smallAmount = 1 wei;
        uint256 mediumAmount = 1 ether;
        uint256 largeAmount = 100 ether;

        vm.startPrank(owner);

        // Test small amount
        ethContract.depositWithETH{value: smallAmount}();
        assertEq(
            IERC20(address(mockWETH)).balanceOf(address(ethContract)),
            smallAmount,
            "Small amount should be wrapped correctly"
        );

        // Test medium amount
        ethContract.depositWithETH{value: mediumAmount}();
        assertEq(
            IERC20(address(mockWETH)).balanceOf(address(ethContract)),
            smallAmount + mediumAmount,
            "Medium amount should be wrapped correctly"
        );

        // Test large amount
        ethContract.depositWithETH{value: largeAmount}();
        assertEq(
            IERC20(address(mockWETH)).balanceOf(address(ethContract)),
            smallAmount + mediumAmount + largeAmount,
            "Large amount should be wrapped correctly"
        );

        vm.stopPrank();
    }

    /**
     * @dev Test that _handleOwnerDeposit correctly accumulates multiple deposits
     * Tests line 682: _handleOwnerDeposit(msg.value);
     */
    function test_HandleOwnerDeposit_AccumulatesMultipleDeposits() public {
        // Ensure offsetTokens > tokensEarned
        assertGt(
            ethContract.offsetTokens(), ethContract.tokensEarned(), "offsetTokens should be greater than tokensEarned"
        );

        uint256 firstDeposit = 2 ether;
        uint256 secondDeposit = 3 ether;
        uint256 thirdDeposit = 5 ether;
        uint256 totalDeposit = firstDeposit + secondDeposit + thirdDeposit;

        uint256 initialUnaccountedBalance = ethContract.unaccountedCollateralBalance();

        vm.startPrank(owner);
        ethContract.depositWithETH{value: firstDeposit}();
        ethContract.depositWithETH{value: secondDeposit}();
        ethContract.depositWithETH{value: thirdDeposit}();
        vm.stopPrank();

        uint256 finalUnaccountedBalance = ethContract.unaccountedCollateralBalance();

        // Verify that unaccountedCollateralBalance accumulated all deposits
        assertEq(
            finalUnaccountedBalance,
            initialUnaccountedBalance + totalDeposit,
            "unaccountedCollateralBalance should accumulate all deposits"
        );
    }
}

