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

contract ProofOfCapitalConsoleLogTest is BaseTest {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;
    StdStorage private _stdstore;

    address public user = address(0x5);

    function testHandleReturnWalletSaleConsoleLog() public {
        // when offsetLaunch > launchTokensEarned and effectiveAmount > offsetAmount

        // Step 1: Owner deposits tokens to create launchBalance
        vm.startPrank(owner);
        token.approve(address(proofOfCapital), 100000e18);
        proofOfCapital.depositLaunch(50000e18); // This increases launchBalance
        vm.stopPrank();

        // Now market maker can buy many tokens to create large totalLaunchSold
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(weth)), marketMaker, 10000e18);
        vm.stopPrank();

        vm.startPrank(marketMaker);
        weth.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.buyLaunchTokens(5000e18); // Buy many tokens to create large totalLaunchSold
        vm.stopPrank();

        // Verify totalLaunchSold increased
        uint256 totalTokensSoldAfterBuy = proofOfCapital.totalLaunchSold();
        assertTrue(totalTokensSoldAfterBuy > 0, "Should have tokens sold after market maker purchase");

        // Step 2: Now returnWallet can sell tokens back, which will increase launchTokensEarned
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 10000e18);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.sellLaunchTokensReturnWallet(1000e18); // Return wallet sells tokens back
        vm.stopPrank();

        // Step 3: Verify launchTokensEarned increased
        uint256 tokensEarnedAfterSale = proofOfCapital.launchTokensEarned();
        assertTrue(tokensEarnedAfterSale > 0, "Should have tokens earned after return wallet sale");

        // Step 4: Set offsetLaunch to be larger than launchTokensEarned and ensure tokensAvailableForReturnBuyback > 0
        uint256 currentTokensEarned = proofOfCapital.launchTokensEarned();
        uint256 currentTotalTokensSold = proofOfCapital.totalLaunchSold();

        // Make sure totalLaunchSold > launchTokensEarned so that tokensAvailableForReturnBuyback > 0
        if (currentTotalTokensSold <= currentTokensEarned) {
            // Increase totalLaunchSold to make tokensAvailableForReturnBuyback > 0
            uint256 totalTokensSoldSlot = _stdstore.target(address(proofOfCapital)).sig("totalLaunchSold()").find();
            vm.store(address(proofOfCapital), bytes32(totalTokensSoldSlot), bytes32(currentTokensEarned + 2000e18));
            currentTotalTokensSold = currentTokensEarned + 2000e18;
        }

        uint256 offsetSlot = _stdstore.target(address(proofOfCapital)).sig("offsetLaunch()").find();
        vm.store(address(proofOfCapital), bytes32(offsetSlot), bytes32(currentTokensEarned + 5000e18)); // Set offsetLaunch > launchTokensEarned

        // Re-read values after modification
        currentTokensEarned = proofOfCapital.launchTokensEarned();
        uint256 currentOffsetTokens = proofOfCapital.offsetLaunch();
        currentTotalTokensSold = proofOfCapital.totalLaunchSold();

        // Verify we have the right conditions for the test
        assertTrue(currentOffsetTokens > currentTokensEarned, "offsetLaunch should be > launchTokensEarned");
        assertTrue(currentTotalTokensSold > currentTokensEarned, "totalLaunchSold should be > launchTokensEarned");

        // Step 5: Create collateral balance to ensure contractCollateralBalance > 0
        createCollateralBalance(10000e18);

        // Step 6: Give returnWallet more tokens and try to sell again
        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), returnWallet, 2000e18);
        vm.stopPrank();

        // Step 7: Ensure we have enough tokensAvailableForReturnBuyback before calling sellLaunchTokens
        uint256 finalTokensEarned = proofOfCapital.launchTokensEarned();
        uint256 finalTotalTokensSold = proofOfCapital.totalLaunchSold();

        // If tokensAvailableForReturnBuyback is 0, we need to increase totalLaunchSold
        if (finalTotalTokensSold <= finalTokensEarned) {
            uint256 totalTokensSoldSlot = _stdstore.target(address(proofOfCapital)).sig("totalLaunchSold()").find();
            vm.store(address(proofOfCapital), bytes32(totalTokensSoldSlot), bytes32(finalTokensEarned + 3000e18));
        }

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 2000e18);

        // when offsetLaunch > launchTokensEarned and effectiveAmount > offsetAmount
        proofOfCapital.sellLaunchTokensReturnWallet(1500e18); // Sell amount that triggers the log

        vm.stopPrank();
    }
}
