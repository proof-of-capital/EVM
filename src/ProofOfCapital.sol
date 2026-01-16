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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IProofOfCapital} from "./interfaces/IProofOfCapital.sol";
import {IRoyalty} from "./interfaces/IRoyalty.sol";
import {Constants} from "./utils/Constant.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IDaoUpgradeOwnerShare} from "./interfaces/IDaoUpgradeOwnerShare.sol";

/**
 * @title ProofOfCapital
 * @dev Proof of Capital contract
 * @notice This contract allows locking desired part of token issuance for selected period with guaranteed buyback
 */
contract ProofOfCapital is Ownable, IProofOfCapital {
    using SafeERC20 for IERC20;

    // Contract state
    bool public override isActive;
    mapping(address => bool) public override oldContractAddress;

    // Core addresses
    address public override reserveOwner;
    IERC20 public override launchToken;
    mapping(address => bool) public override returnWalletAddresses;
    address public override royaltyWalletAddress;
    address public override daoAddress; // DAO address for governance

    // Time and control variables
    uint256 public override lockEndTime;
    uint256 public override controlDay;
    uint256 public override controlPeriod;

    // Pricing and level variables
    uint256 public override initialPricePerLaunchToken;
    uint256 public override firstLevelLaunchTokenQuantity;
    uint256 public override currentPrice;
    uint256 public override quantityLaunchPerLevel;
    uint256 public override remainderOfStep;
    uint256 public override currentStep;

    // Multipliers and percentages
    uint256 public override priceIncrementMultiplier;
    int256 public override levelIncreaseMultiplier;
    uint256 public override trendChangeStep;
    int256 public override levelDecreaseMultiplierAfterTrend;
    uint256 public override profitPercentage;
    uint256 public override royaltyProfitPercent;
    uint256 public override profitBeforeTrendChange; // Profit percentage before trend change

    // Balances and counters
    uint256 public override totalLaunchSold;
    uint256 public override contractCollateralBalance; // WETH balance for backing
    uint256 public override launchBalance; // Main token balance
    uint256 public override launchTokensEarned;
    uint256 public override ownerEarnedLaunchTokens; // EOL: launch tokens earned for owner from return wallet sales

    // Return tracking variables
    uint256 public override currentStepEarned;
    uint256 public override remainderOfStepEarned;
    uint256 public override quantityLaunchPerLevelEarned;
    uint256 public override currentPriceEarned;

    // Offset variables
    uint256 public override offsetLaunch;
    uint256 public override offsetStep;
    uint256 public override offsetPrice;
    uint256 public override remainderOfStepOffset;
    uint256 public override quantityLaunchPerLevelOffset;

    // Collateral token variables
    IERC20 public override collateralToken;

    // Market makers
    mapping(address => bool) public override marketMakerAddresses;

    // Profit tracking
    uint256 public override ownerCollateralBalance; // Owner's profit balance (universal for both ETH and collateral tokens)
    uint256 public override royaltyCollateralBalance; // Royalty profit balance (universal for both ETH and collateral tokens)
    bool public override profitInTime; // true = immediate, false = on request

    // Deferred withdrawal
    bool public override canWithdrawal;
    uint256 public override launchDeferredWithdrawalDate;
    uint256 public override launchDeferredWithdrawalAmount;
    address public override recipientDeferredWithdrawalLaunch;
    uint256 public override collateralTokenDeferredWithdrawalDate;
    address public override recipientDeferredWithdrawalCollateralToken;

    // Old contract address change control

    // Unaccounted balances for gradual processing
    uint256 public override unaccountedCollateralBalance; // Unaccounted collateral balance
    uint256 public override unaccountedOffset; // Unaccounted offset balance
    uint256 public override unaccountedOffsetLaunchBalance; // Unaccounted offset token balance for gradual processing
    uint256 public override unaccountedReturnBuybackBalance; // Unaccounted return buyback balance for gradual processing

    // Initialization flag
    bool public override isInitialized; // Flag indicating whether the contract's initialization is complete

    // First deposit tracking
    bool public override isFirstLaunchDeposit; // Flag to track if this is the first launch deposit

    // Collateral token oracle
    address public override collateralTokenOracle;
    int256 public override collateralTokenMinOracleValue;

    modifier whenInitialized() {
        _isInitialized();
        _;
    }

    modifier onlyOwnerOrOldContract() {
        _onlyOwnerOrOldContract();
        _;
    }

    modifier onlyActiveContract() {
        _onlyActiveContract();
        _;
    }

    modifier onlyReserveOwner() {
        _onlyReserveOwner();
        _;
    }

    modifier onlyOwnerOrReserveOwner() {
        _onlyOwnerOrReserveOwner();
        _;
    }

    modifier onlyDao() {
        _onlyDao();
        _;
    }

    modifier whenCollateralTokenOracleValid() {
        _validateCollateralTokenOracle();
        _;
    }

    constructor(IProofOfCapital.InitParams memory params) Ownable(params.initialOwner) {
        require(params.initialPricePerLaunchToken > 0, InitialPriceMustBePositive());
        require(
            params.levelDecreaseMultiplierAfterTrend < int256(Constants.PERCENTAGE_DIVISOR)
                && params.levelDecreaseMultiplierAfterTrend > -int256(Constants.PERCENTAGE_DIVISOR),
            InvalidLevelDecreaseMultiplierAfterTrend()
        );
        require(
            params.levelIncreaseMultiplier > -int256(Constants.PERCENTAGE_DIVISOR)
                && params.levelIncreaseMultiplier < int256(Constants.PERCENTAGE_DIVISOR),
            InvalidLevelIncreaseMultiplier()
        );
        require(params.priceIncrementMultiplier > 0, PriceIncrementTooLow());
        require(
            params.royaltyProfitPercent > Constants.MIN_ROYALTY_PERCENT
                && params.royaltyProfitPercent <= Constants.MAX_ROYALTY_PERCENT,
            InvalidRoyaltyProfitPercentage()
        );
        require(params.profitBeforeTrendChange > 0, ProfitBeforeTrendChangeMustBePositive());

        // Validate addresses
        require(params.initialOwner != address(0), InvalidInitialOwner());
        require(params.launchToken != address(0), InvalidLaunchTokenAddress());
        require(params.marketMakerAddress != address(0), InvalidMarketMakerAddress());
        require(params.returnWalletAddress != address(0), InvalidReturnWalletAddress());
        require(params.royaltyWalletAddress != address(0), InvalidRoyaltyWalletAddress());
        require(params.collateralToken != address(0), InvalidCollateralTokenAddress());

        // Validate numeric values
        require(params.lockEndTime > block.timestamp, InvalidLockEndTime());
        require(params.firstLevelLaunchTokenQuantity > 0, InvalidFirstLevelTokenQuantity());
        require(params.profitPercentage > 0, InvalidProfitPercentage());

        isActive = true;
        launchToken = IERC20(params.launchToken);

        returnWalletAddresses[params.returnWalletAddress] = true;
        royaltyWalletAddress = params.royaltyWalletAddress;
        lockEndTime = params.lockEndTime;
        initialPricePerLaunchToken = params.initialPricePerLaunchToken;
        firstLevelLaunchTokenQuantity = params.firstLevelLaunchTokenQuantity;
        priceIncrementMultiplier = params.priceIncrementMultiplier;
        levelIncreaseMultiplier = params.levelIncreaseMultiplier;
        trendChangeStep = params.trendChangeStep;
        levelDecreaseMultiplierAfterTrend = params.levelDecreaseMultiplierAfterTrend;
        profitPercentage = params.profitPercentage;
        offsetLaunch = params.offsetLaunch;
        controlPeriod = _getPeriod(params.controlPeriod);
        collateralToken = IERC20(params.collateralToken);
        royaltyProfitPercent = params.royaltyProfitPercent;
        profitBeforeTrendChange = params.profitBeforeTrendChange;
        daoAddress = params.daoAddress;

        // Initialize state variables
        currentStep = 0;
        remainderOfStep = params.firstLevelLaunchTokenQuantity;
        quantityLaunchPerLevel = params.firstLevelLaunchTokenQuantity;
        currentPrice = params.initialPricePerLaunchToken;
        controlDay = block.timestamp + Constants.THIRTY_DAYS;
        reserveOwner = params.initialOwner;

        // Initialize market makers
        marketMakerAddresses[params.marketMakerAddress] = true;

        // Initialize offset variables
        offsetStep = 0;
        offsetPrice = params.initialPricePerLaunchToken;
        remainderOfStepOffset = params.firstLevelLaunchTokenQuantity;
        quantityLaunchPerLevelOffset = params.firstLevelLaunchTokenQuantity;

        // Initialize earned tracking
        currentStepEarned = 0;
        remainderOfStepEarned = params.firstLevelLaunchTokenQuantity;
        quantityLaunchPerLevelEarned = params.firstLevelLaunchTokenQuantity;
        currentPriceEarned = params.initialPricePerLaunchToken;

        recipientDeferredWithdrawalLaunch = params.initialOwner;
        recipientDeferredWithdrawalCollateralToken = params.initialOwner;

        profitInTime = true;
        canWithdrawal = true;

        collateralTokenOracle = params.collateralTokenOracle;
        collateralTokenMinOracleValue = params.collateralTokenMinOracleValue;

        if (params.offsetLaunch > 0) {
            unaccountedOffset = params.offsetLaunch;
            isInitialized = false; // Will be set to true after processing offset
        } else {
            isInitialized = true; // No offset to process
        }

        // Set old contract addresses
        for (uint256 i = 0; i < params.oldContractAddresses.length; i++) {
            oldContractAddress[params.oldContractAddresses[i]] = true;
        }

        // Check that return wallet and royalty wallet addresses don't match old contracts
        require(!oldContractAddress[params.returnWalletAddress], ReturnWalletCannotBeOldContract());
        require(!oldContractAddress[params.royaltyWalletAddress], RoyaltyWalletCannotBeOldContract());
    }

    /**
     * @dev Extend lock period
     */
    function extendLock(uint256 lockTimestamp) external override onlyOwner {
        require(lockTimestamp > block.timestamp, InvalidTimePeriod());
        require(lockTimestamp > lockEndTime, NewLockMustBeGreaterThanOld());
        require(lockTimestamp <= block.timestamp + Constants.FIVE_YEARS, LockCannotExceedFiveYears());

        lockEndTime = lockTimestamp;
        emit LockExtended(lockTimestamp);
    }

    /**
     * @dev Toggle deferred withdrawal state
     * @notice If called when less than 60 days remain until the end of the lock (i.e., when users can already interact with the contract),
     * the owner can re-enable withdrawal—for example, to transfer tokens to another contract with a lock (for a safe migration).
     */
    function toggleDeferredWithdrawal() external override onlyOwner {
        if (canWithdrawal) {
            canWithdrawal = false;
        } else {
            require(lockEndTime - block.timestamp < Constants.SIXTY_DAYS, CannotActivateWithdrawalTooCloseToLockEnd());
            canWithdrawal = true;
        }
        emit DeferredWithdrawalToggled(canWithdrawal);
    }

    /**
     * @dev Verifies and registers the old contract address.
     * Requires that the address is non-zero and does not match the main contract addresses.
     * Can be changed no more than once every 40 days.
     * @param oldContractAddr Address of the old contract to register
     */
    function registerOldContract(address oldContractAddr) external override onlyOwner {
        require(!_checkTradingAccess(), TradingIsActive());
        require(oldContractAddr != address(0), OldContractAddressZero());
        require(
            oldContractAddr != owner() && oldContractAddr != reserveOwner && oldContractAddr != address(launchToken)
                && oldContractAddr != address(collateralToken) && !returnWalletAddresses[oldContractAddr]
                && oldContractAddr != royaltyWalletAddress && oldContractAddr != recipientDeferredWithdrawalLaunch
                && oldContractAddr != recipientDeferredWithdrawalCollateralToken
                && !marketMakerAddresses[oldContractAddr],
            OldContractAddressConflict()
        );

        oldContractAddress[oldContractAddr] = true;
        emit OldContractRegistered(oldContractAddr);
    }

    /**
     * @dev Schedule deferred withdrawal of main token
     */
    function launchDeferredWithdrawal(address recipientAddress, uint256 amount) external override onlyOwner {
        require(recipientAddress != address(0) && amount > 0, InvalidRecipientOrAmount());
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(launchDeferredWithdrawalAmount == 0, LaunchDeferredWithdrawalAlreadyScheduled());

        recipientDeferredWithdrawalLaunch = recipientAddress;
        launchDeferredWithdrawalDate = block.timestamp + Constants.THIRTY_DAYS;
        launchDeferredWithdrawalAmount = amount;

        emit DeferredWithdrawalScheduled(recipientAddress, amount, launchDeferredWithdrawalDate);
    }

    /**
     * @dev Cancel deferred withdrawal of main token
     */
    function stopLaunchDeferredWithdrawal() external override {
        require(msg.sender == owner() || msg.sender == royaltyWalletAddress || msg.sender == daoAddress, AccessDenied());
        require(launchDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());

        launchDeferredWithdrawalDate = 0;
        launchDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalLaunch = owner();

        emit LaunchDeferredWithdrawalCancelled(msg.sender);
    }

    /**
     * @dev Confirm and execute deferred withdrawal of main token
     */
    function confirmLaunchDeferredWithdrawal() external override onlyOwner {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(block.timestamp >= launchDeferredWithdrawalDate, WithdrawalDateNotReached());
        require(launchBalance > totalLaunchSold, InsufficientTokenBalance());
        require(launchBalance - totalLaunchSold >= launchDeferredWithdrawalAmount, InsufficientAmount());
        require(block.timestamp <= launchDeferredWithdrawalDate + Constants.SEVEN_DAYS, WithdrawalDateNotReached());

        uint256 withdrawalAmount = launchDeferredWithdrawalAmount;
        address recipient = recipientDeferredWithdrawalLaunch;
        launchBalance -= withdrawalAmount;
        launchDeferredWithdrawalDate = 0;
        launchDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalLaunch = owner();

        emit LaunchDeferredWithdrawalConfirmed(recipient, withdrawalAmount);

        launchToken.safeIncreaseAllowance(recipient, withdrawalAmount);
        IProofOfCapital(recipient).depositLaunch(withdrawalAmount);
    }

    /**
     * @dev Schedule deferred withdrawal of collateral tokens
     */
    function collateralDeferredWithdrawal(address recipientAddress) external override onlyOwner {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(recipientAddress != address(0), InvalidRecipient());
        require(collateralTokenDeferredWithdrawalDate == 0, CollateralDeferredWithdrawalAlreadyScheduled());

        recipientDeferredWithdrawalCollateralToken = recipientAddress;
        collateralTokenDeferredWithdrawalDate = block.timestamp + Constants.THIRTY_DAYS;

        emit DeferredWithdrawalScheduled(
            recipientAddress, contractCollateralBalance, collateralTokenDeferredWithdrawalDate
        );
    }

    /**
     * @dev Cancel deferred withdrawal of collateral tokens
     */
    function stopCollateralDeferredWithdrawal() external override {
        require(msg.sender == owner() || msg.sender == royaltyWalletAddress || msg.sender == daoAddress, AccessDenied());
        require(collateralTokenDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());

        collateralTokenDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalCollateralToken = owner();

        emit CollateralDeferredWithdrawalCancelled(msg.sender);
    }

    /**
     * @dev Confirm and execute deferred withdrawal of collateral tokens
     */
    function confirmCollateralDeferredWithdrawal() external override onlyOwner {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(collateralTokenDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());
        require(block.timestamp >= collateralTokenDeferredWithdrawalDate, WithdrawalDateNotReached());
        require(
            block.timestamp <= collateralTokenDeferredWithdrawalDate + Constants.SEVEN_DAYS,
            CollateralTokenWithdrawalWindowExpired()
        );

        uint256 collateralBalance = contractCollateralBalance;
        address recipient = recipientDeferredWithdrawalCollateralToken;
        contractCollateralBalance = 0;
        collateralTokenDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalCollateralToken = owner();
        isActive = false;

        emit CollateralDeferredWithdrawalConfirmed(recipient, collateralBalance);

        collateralToken.safeIncreaseAllowance(recipient, collateralBalance);
        IProofOfCapital(recipient).depositCollateral(collateralBalance);
    }

    /**
     * @dev Assign new owner
     */
    function transferOwnership(address newOwner) public override onlyOwnerOrReserveOwner {
        require(newOwner != address(0), InvalidNewOwner());
        require(!oldContractAddress[newOwner], OldContractAddressConflict());

        if (owner() == reserveOwner) {
            _transferOwnership(newOwner);
            _transferReserveOwner(newOwner);
        } else {
            _transferOwnership(newOwner);
        }
    }

    /**
     * @dev Assign new reserve owner
     */
    function assignNewReserveOwner(address newReserveOwner) external override onlyReserveOwner {
        require(newReserveOwner != address(0), InvalidReserveOwner());
        _transferReserveOwner(newReserveOwner);
    }

    /**
     * @dev Switch profit withdrawal mode
     */
    function switchProfitMode(bool flag) external override onlyOwner {
        profitInTime = flag;
        emit ProfitModeChanged(flag);

        // Notify royalty contract about profit mode change
        if (royaltyWalletAddress != address(0)) {
            try IRoyalty(royaltyWalletAddress).notifyProfitModeChanged(address(this), flag) {}
            catch (bytes memory reason) {
                emit RoyaltyNotificationFailed(royaltyWalletAddress, reason);
            }
        }
    }

    /**
     * @dev Set return wallet status for an address
     */
    function setReturnWallet(address returnWalletAddress, bool isReturnWallet) external override onlyOwner {
        require(returnWalletAddress != address(0), InvalidAddress());
        returnWalletAddresses[returnWalletAddress] = isReturnWallet;
        emit ReturnWalletChanged(returnWalletAddress, isReturnWallet);
    }

    /**
     * @dev Change royalty wallet address
     */
    function changeRoyaltyWallet(address newRoyaltyWalletAddress) external override {
        require(msg.sender == royaltyWalletAddress, OnlyRoyaltyWalletCanChange());
        require(newRoyaltyWalletAddress != address(0), InvalidAddress());
        royaltyWalletAddress = newRoyaltyWalletAddress;
        emit RoyaltyWalletChanged(newRoyaltyWalletAddress);
    }

    /**
     * @dev Change profit percentage distribution
     */
    function changeProfitPercentage(uint256 newRoyaltyProfitPercentage) external override {
        require(msg.sender == owner() || msg.sender == royaltyWalletAddress, AccessDenied());
        require(
            newRoyaltyProfitPercentage > 0 && newRoyaltyProfitPercentage <= Constants.PERCENTAGE_DIVISOR,
            InvalidPercentage()
        );

        if (msg.sender == owner()) {
            require(newRoyaltyProfitPercentage > royaltyProfitPercent, CannotDecreaseRoyalty());
        } else {
            require(newRoyaltyProfitPercentage < royaltyProfitPercent, CannotIncreaseRoyalty());
        }

        royaltyProfitPercent = newRoyaltyProfitPercentage;
        emit ProfitPercentageChanged(newRoyaltyProfitPercentage);
    }

    /**
     * @dev Set market maker status for an address
     */
    function setMarketMaker(address marketMakerAddress, bool isMarketMaker) external override onlyDao {
        require(marketMakerAddress != address(0), InvalidAddress());

        marketMakerAddresses[marketMakerAddress] = isMarketMaker;
        emit MarketMakerStatusChanged(marketMakerAddress, isMarketMaker);
    }

    /**
     * @dev Buy tokens with collateral tokens
     */
    function buyLaunchTokens(uint256 amount)
        external
        override
        onlyActiveContract
        whenInitialized
        whenCollateralTokenOracleValid
    {
        require(amount > 0, InvalidAmount());

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        _handleLaunchTokenPurchaseCommon(amount);
    }

    /**
     * @dev Deposit collateral tokens (for owners and old contracts)
     */
    function depositCollateral(uint256 amount)
        external
        override
        onlyActiveContract
        onlyOwnerOrOldContract
        whenInitialized
    {
        require(amount > 0, InvalidAmount());

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        unaccountedCollateralBalance += amount;
        emit CollateralDeposited(amount);
    }

    /**
     * @dev Deposit launch tokens back to contract (for owners and old contracts)
     * Used when owner needs to return tokens and potentially trigger offset reduction
     */
    function depositLaunch(uint256 amount) external override onlyActiveContract onlyOwnerOrOldContract whenInitialized {
        require(amount > 0, InvalidAmount());

        launchToken.safeTransferFrom(msg.sender, address(this), amount);

        if (isFirstLaunchDeposit) {
            launchBalance += amount;

            if (totalLaunchSold == offsetLaunch) {
                uint256 availableCapacity = offsetLaunch - launchTokensEarned;
                if (availableCapacity > unaccountedOffsetLaunchBalance) {
                    uint256 remainingCapacity = availableCapacity - unaccountedOffsetLaunchBalance;
                    uint256 newAmount = amount < remainingCapacity ? amount : remainingCapacity;
                    unaccountedOffsetLaunchBalance += newAmount;
                    isInitialized = false;
                }
            }
        } else {
            launchBalance += amount;
            isFirstLaunchDeposit = true;
        }

        emit LaunchDeposited(msg.sender, amount);
    }

    /**
     * @dev Sell tokens back to contract (for regular users and market makers)
     */
    function sellLaunchTokens(uint256 amount) external override onlyActiveContract whenInitialized {
        require(amount > 0, InvalidAmount());

        launchToken.safeTransferFrom(msg.sender, address(this), amount);
        _handleLaunchTokenSale(amount);
    }

    /**
     * @dev Sell tokens back to contract (for return wallet only)
     */
    function sellLaunchTokensReturnWallet(uint256 amount) external override onlyActiveContract whenInitialized {
        require(amount > 0, InvalidAmount());
        require(msg.sender != daoAddress, AccessDenied());
        require(returnWalletAddresses[msg.sender], OnlyReturnWallet());

        launchToken.safeTransferFrom(msg.sender, address(this), amount);
        ownerEarnedLaunchTokens += amount;
        _handleReturnWalletSale(amount);
    }

    /**
     * @dev Sell tokens back to contract (for DAO only). Owner earned counter is intentionally untouched.
     */
    function sellLaunchTokensDao(uint256 amount) external override onlyActiveContract whenInitialized onlyDao {
        require(amount > 0, InvalidAmount());

        launchToken.safeTransferFrom(msg.sender, address(this), amount);
        _handleReturnWalletSale(amount);
    }

    /**
     * @dev Upgrade owner share in DAO by sending accumulated earned launch tokens.
     */
    function upgradeOwnerShare() external override onlyDao {
        uint256 amount = ownerEarnedLaunchTokens;
        require(amount > 0, InvalidAmount());

        IDaoUpgradeOwnerShare(daoAddress).upgradeOwnerShare(amount);
        ownerEarnedLaunchTokens = 0;

        emit OwnerShareUpgraded(amount);
    }

    /**
     * @dev Withdraw all tokens after lock period
     * @notice Only DAO can withdraw all tokens after lock period ends
     */
    function withdrawAllLaunchTokens() external override onlyDao {
        require(block.timestamp >= lockEndTime, LockPeriodNotEnded());
        uint256 _launchBalance = launchToken.balanceOf(address(this));
        require(_launchBalance > 0, NoTokensToWithdraw());

        launchToken.safeTransfer(owner(), _launchBalance);

        isActive = false;

        emit AllTokensWithdrawn(owner(), _launchBalance);
    }

    /**
     * @dev Withdraw all collateral tokens after lock period
     * @notice Only DAO can withdraw all collateral tokens after lock period ends
     */
    function withdrawAllCollateralTokens() external override onlyDao {
        require(block.timestamp >= lockEndTime, LockPeriodNotEnded());
        uint256 _collateralBalance = collateralToken.balanceOf(address(this));
        require(_collateralBalance > 0, NoCollateralTokensToWithdraw());

        collateralToken.safeTransfer(daoAddress, _collateralBalance);

        isActive = false;

        emit AllCollateralTokensWithdrawn(daoAddress, _collateralBalance);
    }

    /**
     * @dev Withdraw any ERC20 token from contract (except launch and collateral tokens)
     * @notice Only DAO can withdraw tokens, works at any time regardless of lock
     * @param token Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     */
    function withdrawToken(address token, uint256 amount) external override onlyDao {
        require(token != address(0), InvalidAddress());
        require(token != address(launchToken) && token != address(collateralToken), InvalidTokenForWithdrawal());
        require(amount > 0, InvalidAmount());

        IERC20(token).safeTransfer(daoAddress, amount);

        emit TokenWithdrawn(token, daoAddress, amount);
    }

    /**
     * @dev Set DAO address
     * @notice Owner can set DAO only if it was zero. Once set, DAO cannot be reassigned
     * @param newDaoAddress New DAO address to set
     */
    function setDao(address newDaoAddress) external override {
        require(daoAddress == address(0), DAOAlreadySet());
        require(msg.sender == owner(), AccessDenied());
        require(newDaoAddress != address(0), InvalidDAOAddress());
        daoAddress = newDaoAddress;
        emit DAOAddressChanged(newDaoAddress);
    }

    /**
     * @dev Calculate unaccounted collateral balance gradually
     * @param amount Amount of collateral to process
     */
    function calculateUnaccountedCollateralBalance(uint256 amount) external override {
        if (!_checkTradingAccess()) {
            _updateUnlockWindow();
            _checkOwner();
        }

        require(unaccountedCollateralBalance >= amount, InsufficientUnaccountedCollateralBalance());

        uint256 deltaCollateralBalance = _calculateChangeOffsetCollateral(amount);
        unaccountedCollateralBalance -= amount;
        contractCollateralBalance += deltaCollateralBalance;

        uint256 change = amount - deltaCollateralBalance;
        if (change > 0) {
            collateralToken.safeTransfer(daoAddress, change);
        }

        emit UnaccountedCollateralBalanceProcessed(amount, deltaCollateralBalance, change);
    }

    /**
     * @dev Calculate unaccounted offset balance gradually
     * @param amount Amount of offset tokens to process
     */
    function calculateUnaccountedOffsetBalance(uint256 amount) external override {
        if (!_checkTradingAccess()) {
            _updateUnlockWindow();
            _checkOwner();
        }
        require(!isInitialized, ContractAlreadyInitialized());
        require(unaccountedOffset >= amount, InsufficientUnaccountedOffsetBalance());

        _calculateOffset(amount);
        unaccountedOffset -= amount;

        // Check if all offset has been processed
        _checkAndSetInitialized();

        emit UnaccountedOffsetBalanceProcessed(amount);
    }

    /**
     * @dev Calculate unaccounted offset token balance gradually (for reducing offset when tokens are returned)
     * @param amount Amount of tokens to process
     */
    function calculateUnaccountedOffsetLaunchBalance(uint256 amount) external override {
        if (!_checkTradingAccess()) {
            _updateUnlockWindow();
            _checkOwner();
        }

        require(unaccountedOffsetLaunchBalance >= amount, InsufficientUnaccountedOffsetTokenBalance());

        _calculateChangeOffsetLaunch(amount);
        unaccountedOffsetLaunchBalance -= amount;
        _checkAndSetInitialized();

        emit UnaccountedOffsetTokenBalanceProcessed(amount);
    }

    /**
     * @dev Get profit on request
     */
    function claimProfitOnRequest() external override {
        if (msg.sender == owner()) {
            require(ownerCollateralBalance > 0, NoProfitAvailable());
            uint256 profitAmount = ownerCollateralBalance;
            collateralToken.safeTransfer(owner(), ownerCollateralBalance);
            ownerCollateralBalance = 0;
            emit ProfitWithdrawn(owner(), profitAmount);
        } else {
            require(msg.sender == royaltyWalletAddress, AccessDenied());
            require(royaltyCollateralBalance > 0, NoProfitAvailable());
            uint256 profitAmount = royaltyCollateralBalance;
            collateralToken.safeTransfer(royaltyWalletAddress, royaltyCollateralBalance);
            royaltyCollateralBalance = 0;
            emit ProfitWithdrawn(royaltyWalletAddress, profitAmount);
        }
    }

    // View functions

    /**
     * @dev Get remaining seconds
     */
    function remainingSeconds() external view override returns (uint256) {
        return lockEndTime > block.timestamp ? lockEndTime - block.timestamp : 0;
    }

    function tradingOpportunity() external view override returns (bool) {
        return lockEndTime < Constants.SIXTY_DAYS + block.timestamp;
    }

    function launchAvailable() external view override returns (uint256) {
        return totalLaunchSold - launchTokensEarned;
    }

    // Internal functions for handling different types of transactions

    /**
     * @dev Limit period to valid range
     */
    function _getPeriod(uint256 period) internal pure returns (uint256) {
        if (period < Constants.MIN_CONTROL_PERIOD) {
            return Constants.MIN_CONTROL_PERIOD;
        } else if (period > Constants.MAX_CONTROL_PERIOD) {
            return Constants.MAX_CONTROL_PERIOD;
        }
        return period;
    }

    /**
     * @dev Common logic for handling token purchases with any collateral currency
     * @param collateralAmount Amount of collateral currency (ETH or collateral token)
     */
    function _handleLaunchTokenPurchaseCommon(uint256 collateralAmount) internal {
        if (!_checkTradingAccess()) {
            _updateUnlockWindow();
            require(marketMakerAddresses[msg.sender], TradingNotAllowedOnlyMarketMakers());
        }
        require(launchBalance > totalLaunchSold, InsufficientTokenBalance());

        (uint256 totalLaunch, uint256 actualProfit) = _calculateLaunchToGiveForCollateralAmount(collateralAmount);
        uint256 royaltyProfit = (actualProfit * royaltyProfitPercent) / Constants.PERCENTAGE_DIVISOR;
        uint256 creatorProfit = actualProfit - royaltyProfit;

        if (profitInTime) {
            if (creatorProfit > 0) {
                collateralToken.safeTransfer(owner(), creatorProfit);
            }
            if (royaltyProfit > 0) {
                collateralToken.safeTransfer(royaltyWalletAddress, royaltyProfit);
            }
        } else {
            ownerCollateralBalance += creatorProfit;
            royaltyCollateralBalance += royaltyProfit;
        }

        // Check to prevent arithmetic underflow
        uint256 netValue = 0;
        if (collateralAmount > actualProfit) {
            netValue = collateralAmount - actualProfit;
        }

        contractCollateralBalance += netValue;
        totalLaunchSold += totalLaunch;

        launchToken.safeTransfer(msg.sender, totalLaunch);

        emit TokensPurchased(msg.sender, totalLaunch, collateralAmount);
    }

    function _handleReturnWalletSale(uint256 amount) internal {
        uint256 collateralAmountToPay = 0;

        // Check to prevent arithmetic underflow
        uint256 launchAvailableForReturnBuyback = 0;
        if (totalLaunchSold > launchTokensEarned) {
            launchAvailableForReturnBuyback = totalLaunchSold - launchTokensEarned;
        }

        // Add unaccounted balance from previous calls
        uint256 totalAmount = amount + unaccountedReturnBuybackBalance;
        uint256 effectiveAmount =
            totalAmount < launchAvailableForReturnBuyback ? totalAmount : launchAvailableForReturnBuyback;

        // Store the difference for future processing
        uint256 remainingAmount = totalAmount - effectiveAmount;
        unaccountedReturnBuybackBalance = remainingAmount;

        if (offsetLaunch > launchTokensEarned) {
            uint256 offsetAmount = offsetLaunch - launchTokensEarned;

            if (effectiveAmount > offsetAmount) {
                _calculateCollateralForTokenAmountEarned(offsetAmount);
                uint256 buybackAmount = effectiveAmount - offsetAmount;
                collateralAmountToPay = _calculateCollateralForTokenAmountEarned(buybackAmount);
            } else {
                _calculateCollateralForTokenAmountEarned(effectiveAmount);
                collateralAmountToPay = 0;
            }
        } else {
            collateralAmountToPay = _calculateCollateralForTokenAmountEarned(effectiveAmount);
        }

        launchTokensEarned += effectiveAmount;
        require(contractCollateralBalance >= collateralAmountToPay, InsufficientCollateralBalance());
        contractCollateralBalance -= collateralAmountToPay;
        launchBalance += amount;

        if (collateralAmountToPay > 0) {
            collateralToken.safeTransfer(daoAddress, collateralAmountToPay);
        }

        emit TokensSoldReturnWallet(msg.sender, amount, collateralAmountToPay);
    }

    function _handleLaunchTokenSale(uint256 amount) internal {
        if (!_checkTradingAccess()) {
            _updateUnlockWindow();
            require(marketMakerAddresses[msg.sender], TradingNotAllowedOnlyMarketMakers());
        }
        uint256 maxEarnedOrOffset = offsetLaunch > launchTokensEarned ? offsetLaunch : launchTokensEarned;

        // Check for tokens available for buyback (prevents underflow and ensures > 0)
        require(totalLaunchSold > maxEarnedOrOffset, NoTokensAvailableForBuyback());

        uint256 launchAvailableForBuyback = totalLaunchSold - maxEarnedOrOffset;
        require(launchAvailableForBuyback >= amount, InsufficientTokensForBuyback());

        uint256 collateralAmountToPay = _calculateCollateralToPayForTokenAmount(amount);
        require(contractCollateralBalance >= collateralAmountToPay, InsufficientCollateralBalance());

        contractCollateralBalance -= collateralAmountToPay;
        totalLaunchSold -= amount;

        collateralToken.safeTransfer(msg.sender, collateralAmountToPay);

        emit TokensSold(msg.sender, amount, collateralAmountToPay);
    }

    function _checkTradingAccess() internal view returns (bool) {
        return _checkControlDay() || (launchDeferredWithdrawalDate > 0) || (collateralTokenDeferredWithdrawalDate > 0)
            || (lockEndTime < block.timestamp + Constants.SIXTY_DAYS);
    }

    function _checkControlDay() internal view returns (bool) {
        // If block.timestamp is before controlDay, we're not in a control window
        if (block.timestamp < controlDay) {
            return false;
        }

        uint256 timeSinceControlDay = block.timestamp - controlDay;

        // Check if we are in the current window
        if (timeSinceControlDay < controlPeriod) {
            return true;
        }

        // Check if we are in one of the following windows (every 30 days)
        uint256 periodsSinceControlDay = timeSinceControlDay / Constants.THIRTY_DAYS;
        uint256 timeInCurrentPeriod = timeSinceControlDay - (periodsSinceControlDay * Constants.THIRTY_DAYS);
        return timeInCurrentPeriod < controlPeriod;
    }

    function _transferReserveOwner(address newOwner) internal {
        reserveOwner = newOwner;
        emit ReserveOwnerChanged(newOwner);
    }

    // Helper functions for profit and level calculations
    function _calculateProfit(uint256 currentStepParam) internal view returns (uint256) {
        if (currentStepParam > trendChangeStep) {
            return profitPercentage;
        } else {
            return profitBeforeTrendChange;
        }
    }

    function _calculateLaunchPerLevel(uint256 launchPerLevel, uint256 currentStepParam)
        internal
        view
        returns (uint256)
    {
        if (currentStepParam > trendChangeStep) {
            return (launchPerLevel * uint256(int256(Constants.PERCENTAGE_DIVISOR) - levelDecreaseMultiplierAfterTrend))
                / Constants.PERCENTAGE_DIVISOR;
        } else {
            return (launchPerLevel * uint256(int256(Constants.PERCENTAGE_DIVISOR) + levelIncreaseMultiplier))
                / Constants.PERCENTAGE_DIVISOR;
        }
    }

    function _calculateAdjustedPrice(uint256 price, uint256 profitPercent) internal pure returns (uint256) {
        return (price * (Constants.PERCENTAGE_DIVISOR - profitPercent)) / Constants.PERCENTAGE_DIVISOR;
    }

    function _calculateOffset(uint256 offsetAmount) internal {
        int256 remainingOffset = int256(offsetAmount);
        uint256 localCurrentStep = offsetStep;
        int256 remainderOfStepLocal = int256(remainderOfStepOffset);
        uint256 launchPerLevel = quantityLaunchPerLevelOffset;
        uint256 currentPriceLocal = currentPrice;

        while (remainingOffset > 0) {
            int256 launchAvailableInStep = remainderOfStepLocal;

            if (remainingOffset >= launchAvailableInStep) {
                remainingOffset -= launchAvailableInStep;
                localCurrentStep += 1;

                launchPerLevel = _calculateLaunchPerLevel(launchPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(launchPerLevel);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                remainderOfStepLocal -= remainingOffset;
                remainingOffset = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOfStepOffset = uint256(remainderOfStepLocal);
        quantityLaunchPerLevelOffset = launchPerLevel;
        offsetPrice = currentPriceLocal;

        currentStep = localCurrentStep;
        quantityLaunchPerLevel = launchPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = uint256(remainderOfStepLocal);
        launchBalance += offsetAmount;
        totalLaunchSold += offsetAmount;
    }

    /**
     * @dev Calculate change in offset when adding tokens (reducing offset)
     * @param amountLaunch Amount of tokens being added
     * @return Current step after recalculation
     */
    function _calculateChangeOffsetLaunch(uint256 amountLaunch) internal returns (uint256) {
        int256 remainingAddLaunchTokens = int256(amountLaunch);
        uint256 localCurrentStep = offsetStep;
        int256 remainderOfStepLocal = int256(remainderOfStepOffset);
        uint256 launchPerLevel = quantityLaunchPerLevelOffset;
        uint256 currentPriceLocal = offsetPrice;

        while (remainingAddLaunchTokens > 0) {
            int256 launchAvailableInStep = int256(launchPerLevel) - remainderOfStepLocal;

            if (remainingAddLaunchTokens >= launchAvailableInStep) {
                remainingAddLaunchTokens -= launchAvailableInStep;

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        launchPerLevel = (launchPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) - levelDecreaseMultiplierAfterTrend);
                    } else {
                        launchPerLevel = (launchPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) + levelIncreaseMultiplier);
                    }
                    currentPriceLocal = (currentPriceLocal * Constants.PERCENTAGE_DIVISOR)
                        / (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier);
                    localCurrentStep -= 1;
                    remainderOfStepLocal = 0;
                } else {
                    remainderOfStepLocal = int256(launchPerLevel);
                    remainingAddLaunchTokens = 0;
                }
            } else {
                remainderOfStepLocal += remainingAddLaunchTokens;
                remainingAddLaunchTokens = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOfStepOffset = uint256(remainderOfStepLocal);
        offsetPrice = currentPriceLocal;
        quantityLaunchPerLevelOffset = launchPerLevel;

        offsetLaunch -= amountLaunch;

        currentStep = localCurrentStep;
        quantityLaunchPerLevel = launchPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = uint256(remainderOfStepLocal);
        totalLaunchSold -= amountLaunch;

        return localCurrentStep;
    }

    function _calculateChangeOffsetCollateral(uint256 amountCollateral) internal returns (uint256) {
        int256 remainingAddCollateral = int256(amountCollateral);
        uint256 remainingOffsetLaunchTokensLocal = offsetLaunch;
        int256 remainingAddLaunchTokens = int256(offsetLaunch) - int256(launchTokensEarned);
        uint256 localCurrentStep = offsetStep;
        uint256 remainderOfStepLocal = remainderOfStepOffset;
        uint256 launchPerLevel = quantityLaunchPerLevelOffset;
        uint256 currentPriceLocal = offsetPrice;

        while (remainingAddCollateral > 0 && remainingAddLaunchTokens > 0) {
            uint256 launchAvailableInStep = launchPerLevel - remainderOfStepLocal;
            uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
            uint256 collateralInStep = (launchAvailableInStep * currentPriceLocal) / Constants.PRICE_PRECISION;
            uint256 collateralRealInStep = (collateralInStep * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                / Constants.PERCENTAGE_DIVISOR;

            if (
                remainingAddCollateral >= int256(collateralRealInStep)
                    && remainingAddLaunchTokens >= int256(launchAvailableInStep)
            ) {
                remainingAddCollateral -= int256(collateralRealInStep);
                remainingOffsetLaunchTokensLocal -= launchAvailableInStep;
                remainingAddLaunchTokens -= int256(launchAvailableInStep);

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        launchPerLevel = (launchPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) - levelDecreaseMultiplierAfterTrend);
                    } else {
                        launchPerLevel = (launchPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) + levelIncreaseMultiplier);
                    }
                    currentPriceLocal = (currentPriceLocal * Constants.PERCENTAGE_DIVISOR)
                        / (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier);
                    localCurrentStep -= 1;
                    remainderOfStepLocal = 0;
                } else {
                    remainderOfStepLocal = launchPerLevel;
                    remainingAddLaunchTokens = 0;
                }
            } else {
                uint256 adjustedPrice = _calculateAdjustedPrice(currentPriceLocal, profitPercentageLocal);

                uint256 collateralToPayForStep = 0;
                uint256 launchToBuyInThisStep = 0;

                if (remainingAddCollateral >= int256(collateralRealInStep)) {
                    collateralToPayForStep =
                        (uint256(remainingAddLaunchTokens) * adjustedPrice) / Constants.PRICE_PRECISION;
                    launchToBuyInThisStep = uint256(remainingAddLaunchTokens);
                } else {
                    uint256 launchToBuyBasedOnCollateral =
                        (uint256(remainingAddCollateral) * Constants.PRICE_PRECISION) / adjustedPrice;

                    if (uint256(remainingAddLaunchTokens) < launchToBuyBasedOnCollateral) {
                        launchToBuyInThisStep = uint256(remainingAddLaunchTokens);
                        collateralToPayForStep = (launchToBuyInThisStep * adjustedPrice) / Constants.PRICE_PRECISION;
                    } else {
                        launchToBuyInThisStep = launchToBuyBasedOnCollateral;
                        collateralToPayForStep = uint256(remainingAddCollateral);
                    }
                }

                remainderOfStepLocal += launchToBuyInThisStep;
                remainingAddCollateral -= int256(collateralToPayForStep);
                remainingOffsetLaunchTokensLocal -= launchToBuyInThisStep;
                remainingAddLaunchTokens = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOfStepOffset = remainderOfStepLocal;
        offsetPrice = currentPriceLocal;
        quantityLaunchPerLevelOffset = launchPerLevel;
        offsetLaunch = remainingOffsetLaunchTokensLocal;

        return (amountCollateral - uint256(remainingAddCollateral));
    }

    function _calculateLaunchToGiveForCollateralAmount(uint256 collateralAmount) internal returns (uint256, uint256) {
        uint256 launchToGive = 0;
        int256 remainingCollateralAmount = int256(collateralAmount);
        uint256 localCurrentStep = currentStep;
        int256 remainderOfStepLocal = int256(remainderOfStep);
        uint256 launchPerLevel = quantityLaunchPerLevel;
        uint256 currentPriceLocal = currentPrice;
        uint256 totalProfit = 0;
        uint256 remainderOfLaunch = launchBalance - totalLaunchSold;

        while (remainingCollateralAmount > 0 && remainderOfLaunch > launchToGive) {
            int256 launchAvailableInStep = remainderOfStepLocal;
            // Ceil division to ensure any remainder rounds up the required collateral
            int256 collateralRequiredForStep =
                ((launchAvailableInStep * int256(currentPriceLocal)) + int256(Constants.PRICE_PRECISION) - 1)
                    / int256(Constants.PRICE_PRECISION);

            if (remainingCollateralAmount >= collateralRequiredForStep) {
                launchToGive += uint256(launchAvailableInStep);
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);

                uint256 profitInStep =
                    (uint256(collateralRequiredForStep) * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingCollateralAmount -= collateralRequiredForStep;
                localCurrentStep += 1;

                launchPerLevel = _calculateLaunchPerLevel(launchPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(launchPerLevel);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 launchToBuyInThisStep =
                    (uint256(remainingCollateralAmount) * Constants.PRICE_PRECISION) / currentPriceLocal;
                launchToGive += launchToBuyInThisStep;
                uint256 collateralSpentInThisStep = uint256(remainingCollateralAmount);

                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 profitInStep =
                    (collateralSpentInThisStep * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingCollateralAmount = 0;
                remainderOfStepLocal -= int256(launchToBuyInThisStep);
            }
        }

        require(remainderOfLaunch >= launchToGive, InsufficientLaunchAvailable());

        require(remainingCollateralAmount == 0, ExcessCollateralAmount());

        currentStep = localCurrentStep;
        quantityLaunchPerLevel = launchPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = uint256(remainderOfStepLocal);

        return (launchToGive, totalProfit);
    }

    function _calculateCollateralToPayForTokenAmount(uint256 launchAmount) internal returns (uint256) {
        uint256 collateralAmountToPay = 0;
        int256 remainingLaunchAmount = int256(launchAmount);
        uint256 localCurrentStep = currentStep;
        int256 remainderOfStepLocal = int256(remainderOfStep);
        uint256 launchPerLevel = quantityLaunchPerLevel;
        uint256 currentPriceLocal = currentPrice;

        while (remainingLaunchAmount > 0) {
            int256 launchAvailableInStep = int256(launchPerLevel) - remainderOfStepLocal;

            if (remainingLaunchAmount >= launchAvailableInStep) {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = _calculateAdjustedPrice(currentPriceLocal, profitPercentageLocal);
                uint256 collateralToPayForStep =
                    (uint256(launchAvailableInStep) * adjustedPrice) / Constants.PRICE_PRECISION;
                collateralAmountToPay += collateralToPayForStep;

                remainingLaunchAmount -= launchAvailableInStep;

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        launchPerLevel = (launchPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) - levelDecreaseMultiplierAfterTrend);
                    } else {
                        launchPerLevel = (launchPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) + levelIncreaseMultiplier);
                    }
                    currentPriceLocal = (currentPriceLocal * Constants.PERCENTAGE_DIVISOR)
                        / (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier);
                    localCurrentStep -= 1;
                    remainderOfStepLocal = 0;
                } else {
                    remainderOfStepLocal = int256(launchPerLevel);
                    remainingLaunchAmount = 0;
                }
            } else {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = _calculateAdjustedPrice(currentPriceLocal, profitPercentageLocal);
                uint256 collateralToPayForStep =
                    (uint256(remainingLaunchAmount) * adjustedPrice) / Constants.PRICE_PRECISION;
                collateralAmountToPay += collateralToPayForStep;

                remainderOfStepLocal += remainingLaunchAmount;
                remainingLaunchAmount = 0;
            }
        }

        currentStep = localCurrentStep;
        quantityLaunchPerLevel = launchPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = uint256(remainderOfStepLocal);

        return collateralAmountToPay;
    }

    function _calculateCollateralForTokenAmountEarned(uint256 launchAmount) internal returns (uint256) {
        uint256 collateralAmountToPay = 0;
        int256 remainingLaunchAmount = int256(launchAmount);
        uint256 localCurrentStep = currentStepEarned;
        int256 remainderOfStepLocal = int256(remainderOfStepEarned);
        uint256 launchPerLevel = quantityLaunchPerLevelEarned;
        uint256 currentPriceLocal = currentPriceEarned;

        while (remainingLaunchAmount > 0) {
            int256 launchAvailableInStep = remainderOfStepLocal;

            if (remainingLaunchAmount >= launchAvailableInStep) {
                require(localCurrentStep <= currentStep, CurrentStepEarnedExceedsCurrentStep());
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = _calculateAdjustedPrice(currentPriceLocal, profitPercentageLocal);
                uint256 collateralToPayForStep =
                    (uint256(launchAvailableInStep) * adjustedPrice) / Constants.PRICE_PRECISION;
                collateralAmountToPay += collateralToPayForStep;

                localCurrentStep += 1;
                launchPerLevel = _calculateLaunchPerLevel(launchPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(launchPerLevel);
                remainingLaunchAmount -= launchAvailableInStep;
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = _calculateAdjustedPrice(currentPriceLocal, profitPercentageLocal);
                uint256 collateralToPayForStep =
                    (uint256(remainingLaunchAmount) * adjustedPrice) / Constants.PRICE_PRECISION;
                collateralAmountToPay += collateralToPayForStep;

                remainderOfStepLocal -= remainingLaunchAmount;
                remainingLaunchAmount = 0;
            }
        }

        currentStepEarned = localCurrentStep;
        quantityLaunchPerLevelEarned = launchPerLevel;
        currentPriceEarned = currentPriceLocal;

        remainderOfStepEarned = uint256(remainderOfStepLocal);

        return collateralAmountToPay;
    }

    function _validateCollateralTokenOracle() internal view {
        if (collateralTokenOracle != address(0)) {
            (, int256 collateralTokenValue,, uint256 updatedAt,) =
                IAggregatorV3(collateralTokenOracle).latestRoundData();
            require(
                collateralTokenValue >= collateralTokenMinOracleValue || collateralTokenValue == 0
                    || updatedAt < block.timestamp - Constants.THIRTY_DAYS,
                InsufficientCollateralTokenValue()
            );
        }
    }

    /**
     * @dev Update controlDay to the nearest future by adding whole number of 30-day periods
     * Shifts controlDay forward so it's always in the future relative to current block
     */
    function _updateUnlockWindow() internal {
        // If controlDay is already in the future, no update needed
        if (block.timestamp < controlDay) {
            return;
        }

        // Calculate how many 30-day periods fit between controlDay and current time
        uint256 timeSinceControlDay = block.timestamp - controlDay;
        uint256 periodsToAdd = (timeSinceControlDay / Constants.THIRTY_DAYS) + 1;

        // Shift controlDay to the nearest future
        controlDay += periodsToAdd * Constants.THIRTY_DAYS;
    }

    function _onlyActiveContract() internal view {
        require(isActive, ContractNotActive());
    }

    function _onlyOwnerOrReserveOwner() internal view {
        require(msg.sender == owner() || msg.sender == reserveOwner, OnlyReserveOwner());
    }

    function _onlyOwnerOrOldContract() internal view {
        require(msg.sender == owner() || oldContractAddress[msg.sender], AccessDenied());
    }

    function _onlyReserveOwner() internal view {
        require(msg.sender == reserveOwner, OnlyReserveOwner());
    }

    function _onlyDao() internal view {
        require(msg.sender == daoAddress, AccessDenied());
    }

    function _isInitialized() internal view {
        require(isInitialized, ContractNotInitialized());
    }

    /**
     * @dev Check if all unaccounted balances are processed and set isInitialized to true
     */
    function _checkAndSetInitialized() internal {
        if (unaccountedOffset == 0 && unaccountedOffsetLaunchBalance == 0) {
            isInitialized = true;
        }
    }
}
