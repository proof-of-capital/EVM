// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
    event UnwrapModeChanged(bool isNeedToUnwrap);
    
    // Upgrade events
    event UpgradeProposed(address indexed implementation, uint256 proposalTime);
    event UpgradeConfirmed(address indexed implementation, uint256 confirmationTime);
    event UpgradeCancelled(address indexed implementation, uint256 cancellationTime);

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

    // Contract migration
    function setOldContractAddress(address oldContract) external;

    // Upgrade management
    function proposeUpgrade(address newImplementation) external;
    function confirmUpgrade() external;
    function cancelUpgradeProposal() external;

    // Trading functions
    function buyTokens(uint256 amount) external;
    function buyTokensWithETH() external payable;
    function deposit(uint256 amount) external;
    function depositWithETH() external payable;
    function sellTokens(uint256 amount) external;

    // Deferred withdrawals
    function jettonDeferredWithdrawal(address recipientAddress, uint256 amount) external;
    function stopJettonDeferredWithdrawal() external;
    function confirmJettonDeferredWithdrawal() external;
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
    function jettonAvailable() external view returns (uint256);

    // State variables getters
    function isActive() external view returns (bool);
    function lockEndTime() external view returns (uint256);
    function currentPrice() external view returns (uint256);
    function totalJettonsSold() external view returns (uint256);
    function contractSupportBalance() external view returns (uint256);
    function jettonSupport() external view returns (bool);
    function profitInTime() external view returns (bool);
    function canWithdrawal() external view returns (bool);
}
