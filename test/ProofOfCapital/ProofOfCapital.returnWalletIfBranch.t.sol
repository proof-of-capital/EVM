// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import "../utils/BaseTest.sol";
import "forge-std/StdStorage.sol";

/**
 * Test to explicitly hit the `if (effectiveAmount > offsetAmount)` branch inside
 * `_handleReturnWalletSale` (lines ~810-830 of ProofOfCapital).
 *
 * Strategy (see README in user prompt):
 *   1) Keep offsetTokens > tokensEarned (true right after deployment).
 *   2) Artificially bump `totalTokensSold` so that `totalTokensSold - tokensEarned` exceeds
 *      the remaining offset.
 *   3) Let `returnWallet` sell an amount larger than the remaining offset.
 *   4) Use StdStorage cheat-codes to patch contract storage where necessary, so the invariant
 *      checks inside the function pass without touching complex price logic.
 */
contract ProofOfCapitalReturnWalletIfBranchTest is BaseTest {
    using stdStorage for StdStorage;

    StdStorage private _stdstore;

    uint256 private constant _OFFSET_TOKENS = 10_000 ether; // mirrors value from BaseTest
    uint256 private constant _SELL_AMOUNT = 11_000 ether; // > _OFFSET_TOKENS
    uint256 private constant _NEW_TOTAL_SOLD = 12_000 ether; // > _OFFSET_TOKENS & >= _SELL_AMOUNT
    uint256 private constant _SUPPORT_LIQ = 1_000_000 ether; // huge support balance to avoid reverts

    function testReturnWalletIfBranchExecution() public {
        /**
         *
         * 1. Prepare state: give PoC plenty of support tokens & book-keeping *
         *
         */
        // Transfer WETH (support token) to contract so it can pay the buy-back
        vm.startPrank(owner);
        weth.transfer(address(proofOfCapital), _SUPPORT_LIQ);
        vm.stopPrank();

        // Update internal accounting variable `contractSupportBalance` to match the transfer
        uint256 supportBalSlot = _stdstore.target(address(proofOfCapital)).sig("contractSupportBalance()").find();
        vm.store(address(proofOfCapital), bytes32(supportBalSlot), bytes32(uint256(_SUPPORT_LIQ)));

        /**
         *
         * 2. Artificially increase totalTokensSold so offset is not enough   *
         *
         */
        uint256 totalSoldSlot = _stdstore.target(address(proofOfCapital)).sig("totalTokensSold()").find();
        vm.store(address(proofOfCapital), bytes32(totalSoldSlot), bytes32(uint256(_NEW_TOTAL_SOLD)));

        /**
         *
         * 3. Fund returnWallet with launch tokens & approve the contract     *
         *
         */
        vm.startPrank(owner);
        token.transfer(returnWallet, _SELL_AMOUNT);
        vm.stopPrank();

        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), type(uint256).max);
        vm.stopPrank();

        /**
         *
         * 4. Capture state before the sale                                   *
         *
         */
        uint256 supportBefore = proofOfCapital.contractSupportBalance();
        uint256 tokensEarnedBefore = proofOfCapital.tokensEarned();

        /**
         *
         * 5. Perform the sale with amount > remaining offset                *
         *
         */
        vm.prank(returnWallet);
        proofOfCapital.sellTokens(_SELL_AMOUNT);

        /**
         *
         * 6. Assertions – we expect the IF-branch to have executed:          *
         *      - support balance decreased (supportAmountToPay > 0)          *
         *      - tokensEarned == effectiveAmount (== _SELL_AMOUNT)           *
         *
         */
        uint256 supportAfter = proofOfCapital.contractSupportBalance();
        uint256 tokensEarnedAfter = proofOfCapital.tokensEarned();

        assertLt(supportAfter, supportBefore, "Support balance should decrease - indicates branch taken");
        assertEq(tokensEarnedAfter, tokensEarnedBefore + _SELL_AMOUNT, "tokensEarned should increase by sell amount");
    }
}
