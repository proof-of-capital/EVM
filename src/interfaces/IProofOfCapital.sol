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

/**
 * @title IProofOfCapital
 * @dev Interface for Proof of Capital contract
 */
interface IProofOfCapital {
    // Events
    event LockExtended(uint256 additionalTime);
    event MarketMakerStatusChanged(address indexed marketMaker, bool isActive);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event TokensSold(address indexed seller, uint256 amount, uint256 payout);
    event DeferredWithdrawalScheduled(address indexed recipient, uint256 amount, uint256 executeTime);
    event ProfitModeChanged(bool profitInTime);
    event CommissionChanged(uint256 newCommission);
    event ReserveOwnerChanged(address indexed newReserveOwner);
    event RoyaltyWalletChanged(address indexed newRoyaltyWalletAddress);
    event ReturnWalletChanged(address indexed newReturnWalletAddress);
    event ProfitPercentageChanged(uint256 newRoyaltyProfitPercentage);
    event SupportDeferredWithdrawalConfirmed(address indexed recipient, uint256 amount);
    event AllTokensWithdrawn(address indexed owner, uint256 amount);
    event AllSupportTokensWithdrawn(address indexed owner, uint256 amount);
    event ProfitWithdrawn(address indexed recipient, uint256 amount, bool isOwner);

    // Management functions

    function extendLock(uint256 additionalTime) external;
    function blockDeferredWithdrawal() external;
    function assignNewOwner(address newOwner) external;
    function assignNewReserveOwner(address newReserveOwner) external;
    function switchProfitMode(bool flag) external;
    function changeReturnWallet(address newReturnWalletAddress) external;
    function changeRoyaltyWallet(address newRoyaltyWalletAddress) external;
    function changeProfitPercentage(uint256 newRoyaltyProfitPercentage) external;

    // Market maker management
    function setMarketMaker(address marketMakerAddress, bool isMarketMaker) external;

    // Trading functions
    function buyTokens(uint256 amount) external;
    function deposit(uint256 amount) external;
    function sellTokens(uint256 amount) external;

    // Deferred withdrawals
    function tokenDeferredWithdrawal(address recipientAddress, uint256 amount) external;
    function stopTokenDeferredWithdrawal() external;
    function confirmTokenDeferredWithdrawal() external;
    function supportDeferredWithdrawal(address recipientAddress) external;
    function stopSupportDeferredWithdrawal() external;
    function confirmSupportDeferredWithdrawal() external;

    // Withdrawal functions
    function withdrawAllTokens() external;
    function withdrawAllSupportTokens() external;
    function getProfitOnRequest() external;

    // View functions
    function remainingSeconds() external view returns (uint256);
    function tradingOpportunity() external view returns (bool);
    function tokenAvailable() external view returns (uint256);

    // State variables getters
    function isActive() external view returns (bool);
    function lockEndTime() external view returns (uint256);
    function currentPrice() external view returns (uint256);
    function totalTokensSold() external view returns (uint256);
    function contractSupportBalance() external view returns (uint256);
    function profitInTime() external view returns (bool);
    function canWithdrawal() external view returns (bool);
}
