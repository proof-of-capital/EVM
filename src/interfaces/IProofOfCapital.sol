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

// This is the third version of the contract. It introduces the following features: the ability to choose any jetcollateral as collateral, build collateral with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IProofOfCapital
 * @dev Interface for Proof of Capital contract
 */
interface IProofOfCapital {
    // Custom errors
    error AccessDenied();
    error NotMarketMaker();
    error ContractNotActive();
    error OnlyReserveOwner();
    error InitialPriceMustBePositive();
    error InvalidLevelDecreaseMultiplierAfterTrend();
    error InvalidLevelIncreaseMultiplier();
    error PriceIncrementTooLow();
    error InvalidRoyaltyProfitPercentage();
    error ETHTransferFailed();
    error LockCannotExceedFiveYears();
    error InvalidTimePeriod();
    error NewLockMustBeGreaterThanOld();
    error CannotActivateWithdrawalTooCloseToLockEnd();
    error InvalidRecipientOrAmount();
    error DeferredWithdrawalBlocked();
    error LaunchDeferredWithdrawalAlreadyScheduled();
    error NoDeferredWithdrawalScheduled();
    error WithdrawalDateNotReached();
    error CollateralTokenWithdrawalWindowExpired();
    error InsufficientTokenBalance();
    error InsufficientAmount();
    error InvalidRecipient();
    error CollateralDeferredWithdrawalAlreadyScheduled();
    error InvalidNewOwner();
    error InvalidReserveOwner();
    error SameModeAlreadyActive();
    error InvalidAddress();
    error OnlyRoyaltyWalletCanChange();
    error InvalidPercentage();
    error CannotDecreaseRoyalty();
    error CannotIncreaseRoyalty();
    error CannotBeSelf();
    error ReturnWalletCannotBeOldContract();
    error RoyaltyWalletCannotBeOldContract();
    error InvalidAmount();
    error UseDepositFunctionForOwners();
    error LockPeriodNotEnded();
    error NoTokensToWithdraw();
    error NoCollateralTokensToWithdraw();
    error ProfitModeNotActive();
    error NoProfitAvailable();
    error TradingNotAllowedOnlyMarketMakers();
    error InsufficientCollateralBalance();
    error NoTokensAvailableForBuyback();
    error InsufficientTokensForBuyback();
    error InsufficientSoldTokens();
    error LockIsActive();
    error OldContractAddressZero();
    error OldContractAddressConflict();
    error InvalidDAOAddress();
    error InsufficientUnaccountedCollateralBalance();
    error InsufficientUnaccountedOffsetBalance();
    error InsufficientUnaccountedOffsetTokenBalance();
    error UnaccountedOffsetBalanceNotSet();
    error ContractAlreadyInitialized();
    error ContractNotInitialized();
    error ProfitBeforeTrendChangeMustBePositive();
    error UseReturnWalletFunction();
    error OnlyReturnWallet();
    error InvalidTokenForWithdrawal();
    error InsufficientLaunchAvailable();
    error ExcessCollateralAmount();
    error InsufficientCollateralTokenValue();
    // Events
    event OldContractRegistered(address indexed oldContractAddress);
    event UnaccountedCollateralBalanceProcessed(uint256 amount, uint256 deltaCollateral, uint256 change);
    event UnaccountedOffsetBalanceProcessed(uint256 amount);
    event UnaccountedOffsetTokenBalanceProcessed(uint256 amount);
    event DAOAddressChanged(address indexed newDaoAddress);
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
    event CollateralDeferredWithdrawalConfirmed(address indexed recipient, uint256 amount);
    event AllTokensWithdrawn(address indexed owner, uint256 amount);
    event AllCollateralTokensWithdrawn(address indexed owner, uint256 amount);
    event ProfitWithdrawn(address indexed recipient, uint256 amount);
    event RoyaltyNotificationFailed(address indexed royaltyAddress, bytes reason);
    event TokenWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    event CollateralDeposited(uint256 amount);

    // Struct for initialization parameters to avoid "Stack too deep" error
    struct InitParams {
        address initialOwner; // Initial owner address
        address launchToken;
        address marketMakerAddress;
        address returnWalletAddress;
        address royaltyWalletAddress;
        uint256 lockEndTime;
        uint256 initialPricePerLaunchToken;
        uint256 firstLevelLaunchTokenQuantity;
        uint256 priceIncrementMultiplier;
        int256 levelIncreaseMultiplier;
        uint256 trendChangeStep;
        int256 levelDecreaseMultiplierAfterTrend;
        uint256 profitPercentage;
        uint256 offsetLaunch;
        uint256 controlPeriod;
        address collateralToken;
        uint256 royaltyProfitPercent;
        address[] oldContractAddresses; // Array of old contract addresses
        uint256 profitBeforeTrendChange; // Profit percentage before trend change
        address daoAddress; // DAO address for governance
        address collateralTokenOracle;
        int256 collateralTokenMinOracleValue;
    }

    // Management functions

    function extendLock(uint256 lockTimestamp) external;
    function toggleDeferredWithdrawal() external;
    function assignNewReserveOwner(address newReserveOwner) external;
    function switchProfitMode(bool flag) external;
    function setReturnWallet(address returnWalletAddress, bool isReturnWallet) external;
    function changeRoyaltyWallet(address newRoyaltyWalletAddress) external;
    function changeProfitPercentage(uint256 newRoyaltyProfitPercentage) external;

    // Market maker management
    function setMarketMaker(address marketMakerAddress, bool isMarketMaker) external;

    // Old contract management
    function registerOldContract(address oldContractAddr) external;

    // Trading functions
    function buyLaunchTokens(uint256 amount) external;
    function depositCollateral(uint256 amount) external;
    function depositLaunch(uint256 amount) external;
    function sellLaunchTokens(uint256 amount) external;
    function sellLaunchTokensReturnWallet(uint256 amount) external;

    // Deferred withdrawals
    function launchDeferredWithdrawal(address recipientAddress, uint256 amount) external;
    function stopLaunchDeferredWithdrawal() external;
    function confirmLaunchDeferredWithdrawal() external;
    function collateralDeferredWithdrawal(address recipientAddress) external;
    function stopCollateralDeferredWithdrawal() external;
    function confirmCollateralDeferredWithdrawal() external;

    // Withdrawal functions
    function withdrawAllLaunchTokens() external;
    function withdrawAllCollateralTokens() external;
    function withdrawToken(address token, uint256 amount) external;
    function claimProfitOnRequest() external;

    // DAO management
    function setDao(address newDaoAddress) external;

    // Unaccounted balance calculations
    function calculateUnaccountedCollateralBalance(uint256 amount) external;
    function calculateUnaccountedOffsetBalance(uint256 amount) external;
    function calculateUnaccountedOffsetLaunchBalance(uint256 amount) external;

    // View functions
    function remainingSeconds() external view returns (uint256);
    function tradingOpportunity() external view returns (bool);
    function launchAvailable() external view returns (uint256);

    // State variables getters
    function isActive() external view returns (bool);
    function oldContractAddress(address) external view returns (bool);
    function reserveOwner() external view returns (address);
    function launchToken() external view returns (IERC20);
    function returnWalletAddresses(address) external view returns (bool);
    function royaltyWalletAddress() external view returns (address);
    function daoAddress() external view returns (address);
    function lockEndTime() external view returns (uint256);
    function controlDay() external view returns (uint256);
    function controlPeriod() external view returns (uint256);
    function initialPricePerLaunchToken() external view returns (uint256);
    function firstLevelLaunchTokenQuantity() external view returns (uint256);
    function currentPrice() external view returns (uint256);
    function quantityLaunchPerLevel() external view returns (uint256);
    function remainderOfStep() external view returns (uint256);
    function currentStep() external view returns (uint256);
    function priceIncrementMultiplier() external view returns (uint256);
    function levelIncreaseMultiplier() external view returns (int256);
    function trendChangeStep() external view returns (uint256);
    function levelDecreaseMultiplierAfterTrend() external view returns (int256);
    function profitPercentage() external view returns (uint256);
    function royaltyProfitPercent() external view returns (uint256);
    function creatorProfitPercent() external view returns (uint256);
    function profitBeforeTrendChange() external view returns (uint256);
    function totalLaunchSold() external view returns (uint256);
    function contractCollateralBalance() external view returns (uint256);
    function launchBalance() external view returns (uint256);
    function launchTokensEarned() external view returns (uint256);
    function currentStepEarned() external view returns (uint256);
    function remainderOfStepEarned() external view returns (uint256);
    function quantityLaunchPerLevelEarned() external view returns (uint256);
    function currentPriceEarned() external view returns (uint256);
    function offsetLaunch() external view returns (uint256);
    function offsetStep() external view returns (uint256);
    function offsetPrice() external view returns (uint256);
    function remainderOfStepOffset() external view returns (uint256);
    function quantityLaunchPerLevelOffset() external view returns (uint256);
    function collateralToken() external view returns (IERC20);
    function marketMakerAddresses(address) external view returns (bool);
    function ownerCollateralBalance() external view returns (uint256);
    function royaltyCollateralBalance() external view returns (uint256);
    function profitInTime() external view returns (bool);
    function canWithdrawal() external view returns (bool);
    function launchDeferredWithdrawalDate() external view returns (uint256);
    function launchDeferredWithdrawalAmount() external view returns (uint256);
    function recipientDeferredWithdrawalLaunch() external view returns (address);
    function collateralTokenDeferredWithdrawalDate() external view returns (uint256);
    function recipientDeferredWithdrawalCollateralToken() external view returns (address);
    function unaccountedCollateralBalance() external view returns (uint256);
    function unaccountedOffset() external view returns (uint256);
    function unaccountedOffsetLaunchBalance() external view returns (uint256);
    function unaccountedReturnBuybackBalance() external view returns (uint256);
    function isInitialized() external view returns (bool);
    function isFirstLaunchDeposit() external view returns (bool);
    function collateralTokenOracle() external view returns (address);
    function collateralTokenMinOracleValue() external view returns (int256);
}
