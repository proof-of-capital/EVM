// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM
pragma solidity 0.8.29;

import "../utils/BaseTest.sol";
import "../mocks/MockWETH.sol";

contract ProofOfCapitalProfitTest is BaseTest {
    address public user = address(0x5);

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Setup tokens for users and add market maker permissions
        token.transfer(address(proofOfCapital), 500000e18);
        token.transfer(returnWallet, 50000e18);
        weth.transfer(user, 100000e18);
        weth.transfer(marketMaker, 100000e18);

        // Enable market maker for user to allow trading
        proofOfCapital.setMarketMaker(user, true);

        vm.stopPrank();

        // Approve tokens
        vm.prank(user);
        weth.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(marketMaker);
        weth.approve(address(proofOfCapital), type(uint256).max);

        vm.prank(returnWallet);
        token.approve(address(proofOfCapital), type(uint256).max);
    }

    function testGetProfitOnRequestWhenProfitModeNotActive() public {
        // Disable profit on request mode
        vm.prank(owner);
        proofOfCapital.switchProfitMode(false);

        // Try to get profit when mode is not active (without any trading)
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.ProfitModeNotActive.selector);
        proofOfCapital.getProfitOnRequest();
    }

    function testGetProfitOnRequestWithNoProfitAvailable() public {
        // Try to get profit when there's no profit
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.getProfitOnRequest();

        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.getProfitOnRequest();
    }

    function testGetProfitOnRequestUnauthorized() public {
        // Unauthorized user tries to get profit (without any trading)
        vm.prank(user);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.getProfitOnRequest();
    }

    function testGetProfitOnRequestOwnerSimple() public {
        // Enable profit on request mode (should be enabled by default)
        assertTrue(proofOfCapital.profitInTime());

        // Manually set owner profit balance for testing
        // We'll use the deposit function to simulate profit accumulation
        vm.prank(owner);
        weth.transfer(address(proofOfCapital), 1000e18);

        // Manually set profit balance using internal state
        // Since we can't directly modify internal balance, we'll test error case

        // Owner requests profit when no profit available
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.getProfitOnRequest();
    }

    function testGetProfitOnRequestRoyaltySimple() public {
        // Royalty requests profit when no profit available
        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.NoProfitAvailable.selector);
        proofOfCapital.getProfitOnRequest();
    }

    function testGetProfitOnRequestOwnerSuccess() public {
        // Ensure profit accumulation mode is enabled (should be default)
        assertTrue(proofOfCapital.profitInTime(), "Profit accumulation mode should be enabled");

        // Create support balance first to enable token purchases
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(15000e18); // Уменьшаем количество

        // User buys tokens to generate profit that gets accumulated
        uint256 purchaseAmount = 2000e18; // Уменьшаем количество
        vm.prank(user);
        proofOfCapital.buyTokens(purchaseAmount);

        // Verify that owner has accumulated some profit
        uint256 ownerProfitBefore = proofOfCapital.ownerSupportBalance();
        assertTrue(ownerProfitBefore > 0, "Owner should have accumulated profit");

        // Record owner's WETH balance before requesting profit
        uint256 ownerWETHBefore = weth.balanceOf(owner);

        // Owner requests accumulated profit
        vm.prank(owner);
        proofOfCapital.getProfitOnRequest();

        // Verify profit was transferred and balance reset
        assertEq(proofOfCapital.ownerSupportBalance(), 0, "Owner profit balance should be reset to 0");
        assertEq(weth.balanceOf(owner), ownerWETHBefore + ownerProfitBefore, "Owner should receive profit in WETH");
    }

    function testGetProfitOnRequestRoyaltySuccess() public {
        // Ensure profit accumulation mode is enabled (should be default)
        assertTrue(proofOfCapital.profitInTime(), "Profit accumulation mode should be enabled");

        // Create support balance first to enable token purchases
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(15000e18); // Уменьшаем количество

        // User buys tokens to generate profit that gets accumulated
        uint256 purchaseAmount = 2000e18; // Уменьшаем количество
        vm.prank(user);
        proofOfCapital.buyTokens(purchaseAmount);

        // Verify that royalty has accumulated some profit
        uint256 royaltyProfitBefore = proofOfCapital.royaltySupportBalance();
        assertTrue(royaltyProfitBefore > 0, "Royalty should have accumulated profit");

        // Record royalty's WETH balance before requesting profit
        uint256 royaltyWETHBefore = weth.balanceOf(royalty);

        // Royalty wallet requests accumulated profit
        vm.prank(royalty);
        proofOfCapital.getProfitOnRequest();

        // Verify profit was transferred and balance reset
        assertEq(proofOfCapital.royaltySupportBalance(), 0, "Royalty profit balance should be reset to 0");
        assertEq(
            weth.balanceOf(royalty), royaltyWETHBefore + royaltyProfitBefore, "Royalty should receive profit in WETH"
        );
    }

    function testGetProfitOnRequestBothOwnerAndRoyalty() public {
        // Ensure profit accumulation mode is enabled
        assertTrue(proofOfCapital.profitInTime(), "Profit accumulation mode should be enabled");

        // Create support balance first
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(15000e18); // Уменьшаем количество

        // Multiple purchases to accumulate significant profit
        uint256 purchaseAmount = 1500e18; // Уменьшаем количество

        vm.prank(user);
        proofOfCapital.buyTokens(purchaseAmount);

        vm.prank(marketMaker);
        proofOfCapital.buyTokens(purchaseAmount);

        // Record balances before profit withdrawal
        uint256 ownerProfitBefore = proofOfCapital.ownerSupportBalance();
        uint256 royaltyProfitBefore = proofOfCapital.royaltySupportBalance();
        uint256 ownerWETHBefore = weth.balanceOf(owner);
        uint256 royaltyWETHBefore = weth.balanceOf(royalty);

        // Verify both have profit
        assertTrue(ownerProfitBefore > 0, "Owner should have profit");
        assertTrue(royaltyProfitBefore > 0, "Royalty should have profit");

        // Owner requests profit first
        vm.prank(owner);
        proofOfCapital.getProfitOnRequest();

        // Verify owner's profit was transferred
        assertEq(proofOfCapital.ownerSupportBalance(), 0, "Owner profit should be reset");
        assertEq(weth.balanceOf(owner), ownerWETHBefore + ownerProfitBefore, "Owner should receive profit");

        // Royalty's profit should remain unchanged
        assertEq(proofOfCapital.royaltySupportBalance(), royaltyProfitBefore, "Royalty profit should remain");

        // Royalty requests profit
        vm.prank(royalty);
        proofOfCapital.getProfitOnRequest();

        // Verify royalty's profit was transferred
        assertEq(proofOfCapital.royaltySupportBalance(), 0, "Royalty profit should be reset");
        assertEq(weth.balanceOf(royalty), royaltyWETHBefore + royaltyProfitBefore, "Royalty should receive profit");
    }

    function testGetProfitOnRequestMultipleTimesOwner() public {
        // Test that owner can request profit multiple times as it accumulates

        // Setup
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(15000e18); // Уменьшаем количество

        // First round of profit accumulation
        vm.prank(user);
        proofOfCapital.buyTokens(1000e18); // Уменьшаем количество

        uint256 firstProfitAmount = proofOfCapital.ownerSupportBalance();
        assertTrue(firstProfitAmount > 0, "Should have first profit");

        // Owner requests first profit
        vm.prank(owner);
        proofOfCapital.getProfitOnRequest();

        assertEq(proofOfCapital.ownerSupportBalance(), 0, "Profit should be reset after first request");

        // Second round of profit accumulation
        vm.prank(marketMaker);
        proofOfCapital.buyTokens(1000e18); // Уменьшаем количество

        uint256 secondProfitAmount = proofOfCapital.ownerSupportBalance();
        assertTrue(secondProfitAmount > 0, "Should have second profit");

        // Owner requests second profit
        uint256 ownerWETHBefore = weth.balanceOf(owner);
        vm.prank(owner);
        proofOfCapital.getProfitOnRequest();

        assertEq(proofOfCapital.ownerSupportBalance(), 0, "Profit should be reset after second request");
        assertEq(weth.balanceOf(owner), ownerWETHBefore + secondProfitAmount, "Should receive second profit");
    }

    function testGetProfitOnRequestWithProfitPercentageChange() public {
        // Test profit withdrawal after changing profit percentage distribution

        // Setup
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(15000e18); // Уменьшаем количество

        // Generate some profit with default 50/50 split
        vm.prank(user);
        proofOfCapital.buyTokens(1000e18); // Уменьшаем количество

        uint256 initialOwnerProfit = proofOfCapital.ownerSupportBalance();
        uint256 initialRoyaltyProfit = proofOfCapital.royaltySupportBalance();

        // Verify roughly equal split (50/50)
        assertTrue(initialOwnerProfit > 0, "Owner should have profit");
        assertTrue(initialRoyaltyProfit > 0, "Royalty should have profit");

        // Owner increases royalty percentage to 60%
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(600);

        // Generate more profit with new 40/60 split
        vm.prank(marketMaker);
        proofOfCapital.buyTokens(1000e18); // Уменьшаем количество

        // Request all accumulated profit
        uint256 totalOwnerProfit = proofOfCapital.ownerSupportBalance();
        uint256 totalRoyaltyProfit = proofOfCapital.royaltySupportBalance();

        uint256 ownerWETHBefore = weth.balanceOf(owner);
        uint256 royaltyWETHBefore = weth.balanceOf(royalty);

        // Both request their profits
        vm.prank(owner);
        proofOfCapital.getProfitOnRequest();

        vm.prank(royalty);
        proofOfCapital.getProfitOnRequest();

        // Verify transfers
        assertEq(weth.balanceOf(owner), ownerWETHBefore + totalOwnerProfit, "Owner should receive total profit");
        assertEq(weth.balanceOf(royalty), royaltyWETHBefore + totalRoyaltyProfit, "Royalty should receive total profit");
        assertEq(proofOfCapital.ownerSupportBalance(), 0, "Owner balance should be reset");
        assertEq(proofOfCapital.royaltySupportBalance(), 0, "Royalty balance should be reset");
    }

    // Tests for changeProfitPercentage function
    function testChangeProfitPercentageOwnerIncrease() public {
        // Owner can only increase royalty percentage (from 500 to higher)
        uint256 newPercentage = 600; // 60%
        uint256 initialRoyaltyPercent = proofOfCapital.royaltyProfitPercent(); // Should be 500
        uint256 initialCreatorPercent = proofOfCapital.creatorProfitPercent(); // Should be 500

        // Verify initial state
        assertEq(initialRoyaltyPercent, 500);
        assertEq(initialCreatorPercent, 500);

        // Owner increases royalty percentage
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(newPercentage);

        // Verify changes
        assertEq(proofOfCapital.royaltyProfitPercent(), newPercentage);
        assertEq(proofOfCapital.creatorProfitPercent(), Constants.PERCENTAGE_DIVISOR - newPercentage);
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
        assertEq(proofOfCapital.creatorProfitPercent(), Constants.PERCENTAGE_DIVISOR - newPercentage);
    }

    function testChangeProfitPercentageAccessDenied() public {
        uint256 newPercentage = 600;

        // Unauthorized users try to change profit percentage
        vm.prank(returnWallet);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);

        vm.prank(marketMaker);
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);

        vm.prank(address(0x999));
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);

        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyProfitPercent(), 500);
    }

    function testChangeProfitPercentageInvalidPercentageZero() public {
        // Try to set percentage to 0
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(0);

        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(0);
    }

    function testChangeProfitPercentageInvalidPercentageExceedsMax() public {
        // Try to set percentage above PERCENTAGE_DIVISOR (1000)
        uint256 invalidPercentage = Constants.PERCENTAGE_DIVISOR + 1;

        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(invalidPercentage);

        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.InvalidPercentage.selector);
        proofOfCapital.changeProfitPercentage(invalidPercentage);
    }

    function testChangeProfitPercentageOwnerCannotDecrease() public {
        // Owner tries to decrease royalty percentage (from 500 to lower)
        uint256 lowerPercentage = 400; // 40%

        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.CannotDecreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(lowerPercentage);

        // Verify state wasn't changed
        assertEq(proofOfCapital.royaltyProfitPercent(), 500);
    }

    function testChangeProfitPercentageRoyaltyCannotIncrease() public {
        // Royalty wallet tries to increase royalty percentage (from 500 to higher)
        uint256 higherPercentage = 600; // 60%

        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.CannotIncreaseRoyalty.selector);
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
        assertEq(proofOfCapital.creatorProfitPercent(), Constants.PERCENTAGE_DIVISOR - 1);

        // Test with boundary value PERCENTAGE_DIVISOR (maximum valid)
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(Constants.PERCENTAGE_DIVISOR);
        assertEq(proofOfCapital.royaltyProfitPercent(), Constants.PERCENTAGE_DIVISOR);
        assertEq(proofOfCapital.creatorProfitPercent(), 0);
    }

    function testChangeProfitPercentageOwnerEqualToCurrent() public {
        // Owner tries to set the same percentage (not allowed - must be greater)
        uint256 currentPercentage = proofOfCapital.royaltyProfitPercent(); // 500

        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.CannotDecreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(currentPercentage);
    }

    function testChangeProfitPercentageRoyaltyEqualToCurrent() public {
        // Royalty tries to set the same percentage (not allowed - must be less)
        uint256 currentPercentage = proofOfCapital.royaltyProfitPercent(); // 500

        vm.prank(royalty);
        vm.expectRevert(ProofOfCapital.CannotIncreaseRoyalty.selector);
        proofOfCapital.changeProfitPercentage(currentPercentage);
    }

    function testChangeProfitPercentageSequentialChanges() public {
        // Test sequential changes: owner increases, then royalty decreases

        // Step 1: Owner increases from 500 to 700
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(700);
        assertEq(proofOfCapital.royaltyProfitPercent(), 700);
        assertEq(proofOfCapital.creatorProfitPercent(), 300);

        // Step 2: Royalty decreases from 700 to 600
        vm.prank(royalty);
        proofOfCapital.changeProfitPercentage(600);
        assertEq(proofOfCapital.royaltyProfitPercent(), 600);
        assertEq(proofOfCapital.creatorProfitPercent(), 400);

        // Step 3: Owner increases from 600 to 800
        vm.prank(owner);
        proofOfCapital.changeProfitPercentage(800);
        assertEq(proofOfCapital.royaltyProfitPercent(), 800);
        assertEq(proofOfCapital.creatorProfitPercent(), 200);
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
            uint256 creatorPercent = proofOfCapital.creatorProfitPercent();

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
        vm.expectRevert(ProofOfCapital.AccessDenied.selector);
        proofOfCapital.changeProfitPercentage(newPercentage);

        // New royalty wallet should have access
        vm.prank(newRoyaltyWallet);
        proofOfCapital.changeProfitPercentage(newPercentage);
        assertEq(proofOfCapital.royaltyProfitPercent(), newPercentage);
    }

    // Test for TradingNotAllowedOnlyMarketMakers require in _handleTokenPurchaseCommon
    function testBuyTokensTradingNotAllowedOnlyMarketMakers() public {
        // Create a regular user (not market maker, not owner)
        address regularUser = address(0x777);

        // Give WETH tokens to regular user
        vm.prank(owner);
        weth.transfer(regularUser, 10000e18);

        vm.prank(regularUser);
        weth.approve(address(proofOfCapital), type(uint256).max);

        // Verify user is not a market maker
        assertFalse(proofOfCapital.marketMakerAddresses(regularUser), "Regular user should not be market maker");

        // Create support balance first to enable token purchases
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(15000e18);

        // Test scenario: Outside of any trading access period (no control day, no deferred withdrawals)
        // Verify we're not in trading access period
        assertFalse(_checkTradingAccessHelper(), "Should not have trading access");

        // Regular user (non-market maker) tries to buy tokens without trading access
        vm.prank(regularUser);
        vm.expectRevert(ProofOfCapital.TradingNotAllowedOnlyMarketMakers.selector);
        proofOfCapital.buyTokens(1000e18);
    }

    function testBuyTokensWithETHTradingNotAllowedOnlyMarketMakers() public {
        // Test the same scenario with buyTokensWithETH for ETH-based contracts

        // Deploy ETH-based contract (tokenSupport = false)
        vm.startPrank(owner);

        // Deploy mock WETH
        MockWETH mockWETH = new MockWETH();

        ProofOfCapital.InitParams memory ethParams = ProofOfCapital.InitParams({
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
            offsetTokens: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            tokenSupportAddress: address(0x999), // Different from wethAddress to make tokenSupport = false
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0)
        });

        ProofOfCapital ethContract = deployWithParams(ethParams);

        // Setup tokens and balances - reduce amounts
        token.transfer(address(ethContract), 200000e18); // Reduced from 500000e18
        token.transfer(returnWallet, 20000e18); // Reduced from 50000e18

        vm.stopPrank();

        // Approve tokens for return wallet
        vm.prank(returnWallet);
        token.approve(address(ethContract), type(uint256).max);

        // Create support balance - reduce amount
        vm.prank(returnWallet);
        ethContract.sellTokens(10000e18); // Reduced from 15000e18

        // Create regular user (not market maker)
        address regularUser = address(0x888);
        vm.deal(regularUser, 10 ether);

        // Verify user is not a market maker
        assertFalse(ethContract.marketMakerAddresses(regularUser), "Regular user should not be market maker");

        // Regular user tries to buy tokens with ETH without trading access
        vm.prank(regularUser);
        vm.expectRevert(ProofOfCapital.TradingNotAllowedOnlyMarketMakers.selector);
        ethContract.buyTokensWithETH{value: 1 ether}();
    }

    function testBuyTokensMarketMakerCanTradeWithoutTradingAccess() public {
        // Test that market makers can trade even without general trading access

        // Create a market maker user
        address marketMakerUser = address(0x999);

        // Give WETH tokens to market maker
        vm.prank(owner);
        weth.transfer(marketMakerUser, 10000e18);

        vm.prank(marketMakerUser);
        weth.approve(address(proofOfCapital), type(uint256).max);

        // Set user as market maker
        vm.prank(owner);
        proofOfCapital.setMarketMaker(marketMakerUser, true);

        // Verify user is a market maker
        assertTrue(proofOfCapital.marketMakerAddresses(marketMakerUser), "User should be market maker");

        // Create support balance first to enable token purchases
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(15000e18);

        // Verify we're not in trading access period
        assertFalse(_checkTradingAccessHelper(), "Should not have trading access");

        // Market maker should be able to buy tokens even without general trading access
        uint256 initialTokenBalance = token.balanceOf(marketMakerUser);

        vm.prank(marketMakerUser);
        proofOfCapital.buyTokens(1000e18); // Should not revert

        // Verify tokens were purchased
        assertTrue(token.balanceOf(marketMakerUser) > initialTokenBalance, "Market maker should receive tokens");
    }

    function testBuyTokensWithTradingAccess() public {
        // Test that regular users can trade when they have trading access

        // Create a regular user (not market maker)
        address regularUser = address(0x777);

        // Give WETH tokens to regular user
        vm.prank(owner);
        weth.transfer(regularUser, 10000e18);

        vm.prank(regularUser);
        weth.approve(address(proofOfCapital), type(uint256).max);

        // Verify user is not a market maker
        assertFalse(proofOfCapital.marketMakerAddresses(regularUser), "Regular user should not be market maker");

        // Create support balance first to enable token purchases
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(15000e18);

        // Activate trading access by scheduling deferred withdrawal
        vm.prank(owner);
        proofOfCapital.tokenDeferredWithdrawal(owner, 1000e18);

        // Verify we now have trading access
        assertTrue(_checkTradingAccessHelper(), "Should have trading access");

        // Regular user should now be able to buy tokens
        uint256 initialTokenBalance = token.balanceOf(regularUser);

        vm.prank(regularUser);
        proofOfCapital.buyTokens(1000e18); // Should not revert

        // Verify tokens were purchased
        assertTrue(token.balanceOf(regularUser) > initialTokenBalance, "Regular user should receive tokens");
    }

    // Helper function to check trading access (mimics _checkTradingAccess logic)
    function _checkTradingAccessHelper() internal view returns (bool) {
        // Check control day
        bool controlDayAccess = (
            block.timestamp > Constants.THIRTY_DAYS + proofOfCapital.controlDay()
                && block.timestamp < proofOfCapital.controlPeriod() + proofOfCapital.controlDay() + Constants.THIRTY_DAYS
        );

        // Check deferred withdrawals
        bool deferredWithdrawalAccess = (proofOfCapital.mainTokenDeferredWithdrawalDate() > 0)
            || (proofOfCapital.supportTokenDeferredWithdrawalDate() > 0);

        return controlDayAccess || deferredWithdrawalAccess;
    }
}
