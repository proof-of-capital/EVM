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
import "forge-std/StdStorage.sol";

contract ProofOfCapitalConsoleLogTest is BaseTest {
    using stdStorage for StdStorage;
    StdStorage private _stdstore;

    address public user = address(0x5);

    function testHandleReturnWalletSaleConsoleLog() public {
        // when offsetTokens > tokensEarned and effectiveAmount > offsetAmount

        // Step 1: Owner deposits tokens to create contractTokenBalance
        vm.startPrank(owner);
        token.approve(address(proofOfCapital), 100000e18);
        proofOfCapital.depositTokens(50000e18); // This increases contractTokenBalance
        vm.stopPrank();

        // Now market maker can buy many tokens to create large totalTokensSold
        vm.startPrank(owner);
        weth.transfer(marketMaker, 10000e18);
        vm.stopPrank();

        vm.startPrank(marketMaker);
        weth.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.buyTokens(5000e18); // Buy many tokens to create large totalTokensSold
        vm.stopPrank();

        // Verify totalTokensSold increased
        uint256 totalTokensSoldAfterBuy = proofOfCapital.totalTokensSold();
        assertTrue(totalTokensSoldAfterBuy > 0, "Should have tokens sold after market maker purchase");

        // Step 2: Now returnWallet can sell tokens back, which will increase tokensEarned
        vm.startPrank(owner);
        token.transfer(returnWallet, 10000e18);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 10000e18);
        proofOfCapital.sellTokens(1000e18); // Return wallet sells tokens back
        vm.stopPrank();

        // Step 3: Verify tokensEarned increased
        uint256 tokensEarnedAfterSale = proofOfCapital.tokensEarned();
        assertTrue(tokensEarnedAfterSale > 0, "Should have tokens earned after return wallet sale");

        // Step 4: Set offsetTokens to be larger than tokensEarned and ensure tokensAvailableForReturnBuyback > 0
        uint256 currentTokensEarned = proofOfCapital.tokensEarned();
        uint256 currentTotalTokensSold = proofOfCapital.totalTokensSold();

        // Make sure totalTokensSold > tokensEarned so that tokensAvailableForReturnBuyback > 0
        if (currentTotalTokensSold <= currentTokensEarned) {
            // Increase totalTokensSold to make tokensAvailableForReturnBuyback > 0
            uint256 totalTokensSoldSlot = _stdstore.target(address(proofOfCapital)).sig("totalTokensSold()").find();
            vm.store(address(proofOfCapital), bytes32(totalTokensSoldSlot), bytes32(currentTokensEarned + 2000e18));
            currentTotalTokensSold = currentTokensEarned + 2000e18;
        }

        uint256 offsetSlot = _stdstore.target(address(proofOfCapital)).sig("offsetTokens()").find();
        vm.store(address(proofOfCapital), bytes32(offsetSlot), bytes32(currentTokensEarned + 5000e18)); // Set offsetTokens > tokensEarned

        // Re-read values after modification
        currentTokensEarned = proofOfCapital.tokensEarned();
        uint256 currentOffsetTokens = proofOfCapital.offsetTokens();
        currentTotalTokensSold = proofOfCapital.totalTokensSold();

        // Verify we have the right conditions for the test
        assertTrue(currentOffsetTokens > currentTokensEarned, "offsetTokens should be > tokensEarned");
        assertTrue(currentTotalTokensSold > currentTokensEarned, "totalTokensSold should be > tokensEarned");

        // Step 5: Create support balance to ensure contractSupportBalance > 0
        createSupportBalance(10000e18);

        // Step 6: Give returnWallet more tokens and try to sell again
        vm.startPrank(owner);
        token.transfer(returnWallet, 2000e18);
        vm.stopPrank();

        // Step 7: Ensure we have enough tokensAvailableForReturnBuyback before calling sellTokens
        uint256 finalTokensEarned = proofOfCapital.tokensEarned();
        uint256 finalTotalTokensSold = proofOfCapital.totalTokensSold();

        // If tokensAvailableForReturnBuyback is 0, we need to increase totalTokensSold
        if (finalTotalTokensSold <= finalTokensEarned) {
            uint256 totalTokensSoldSlot = _stdstore.target(address(proofOfCapital)).sig("totalTokensSold()").find();
            vm.store(address(proofOfCapital), bytes32(totalTokensSoldSlot), bytes32(finalTokensEarned + 3000e18));
        }

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), 2000e18);

        // when offsetTokens > tokensEarned and effectiveAmount > offsetAmount
        proofOfCapital.sellTokens(1500e18); // Sell amount that triggers the log

        vm.stopPrank();
    }
}
