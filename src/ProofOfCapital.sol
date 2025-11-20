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

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IProofOfCapital.sol";
import "./utils/Constant.sol";

/**
 * @title ProofOfCapital
 * @dev Proof of Capital contract
 * @notice This contract allows locking desired part of token issuance for selected period with guaranteed buyback
 */
contract ProofOfCapital is ReentrancyGuard, Ownable, IProofOfCapital {
    using SafeERC20 for IERC20;

    // Custom errors
    error AccessDenied();
    error NotMarketMaker();
    error ContractNotActive();
    error OnlyReserveOwner();
    error InitialPriceMustBePositive();
    error MultiplierTooHigh();
    error MultiplierTooLow();
    error PriceIncrementTooLow();
    error InvalidRoyaltyProfitPercentage();
    error ETHTransferFailed();
    error LockCannotExceedFiveYears();
    error InvalidTimePeriod();
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
    error NoReturnWalletChangeProposed();
    error ReturnWalletChangeDelayNotPassed();
    error InvalidDAOAddress();
    error InsufficientUnaccountedCollateralBalance();
    error InsufficientUnaccountedOffsetBalance();
    error InsufficientUnaccountedOffsetTokenBalance();
    error UnaccountedOffsetBalanceNotSet();
    error ContractAlreadyInitialized();
    error ProfitBeforeTrendChangeMustBePositive();

    // Events
    event OldContractRegistered(address indexed oldContractAddress);
    event UnaccountedCollateralBalanceProcessed(uint256 amount, uint256 deltaCollateral, uint256 change);
    event UnaccountedOffsetBalanceProcessed(uint256 amount);
    event UnaccountedOffsetTokenBalanceProcessed(uint256 amount);
    event ReturnWalletChangeProposed(address indexed newReturnWalletAddress, uint256 proposalTime);
    event ReturnWalletChangeConfirmed(address indexed newReturnWalletAddress);
    event DAOAddressChanged(address indexed newDAOAddress);

    // Struct for initialization parameters to avoid "Stack too deep" error
    struct InitParams {
        address initialOwner; // Initial owner address
        address launchToken;
        address marketMakerAddress;
        address returnWalletAddress;
        address royaltyWalletAddress;
        uint256 lockEndTime;
        uint256 initialPricePerToken;
        uint256 firstLevelTokenQuantity;
        uint256 priceIncrementMultiplier;
        int256 levelIncreaseMultiplier;
        uint256 trendChangeStep;
        int256 levelDecreaseMultiplierafterTrend;
        uint256 profitPercentage;
        uint256 offsetTokens;
        uint256 controlPeriod;
        address collateralAddress;
        uint256 royaltyProfitPercent;
        address[] oldContractAddresses; // Array of old contract addresses
        uint256 profitBeforeTrendChange; // Profit percentage before trend change
        address daoAddress; // DAO address for governance
    }

    // Contract state
    bool public isActive;
    mapping(address => bool) public oldContractAddress;

    // Core addresses
    address public reserveOwner;
    IERC20 public launchToken;
    address public returnWalletAddress;
    address public royaltyWalletAddress;
    address public daoAddress; // DAO address for governance

    // Time and control variables
    uint256 public lockEndTime;
    uint256 public controlDay;
    uint256 public controlPeriod;

    // Pricing and level variables
    uint256 public initialPricePerToken;
    uint256 public firstLevelTokenQuantity;
    uint256 public currentPrice;
    uint256 public quantityTokensPerLevel;
    uint256 public remainderOfStep;
    uint256 public currentStep;

    // Multipliers and percentages
    uint256 public priceIncrementMultiplier;
    int256 public levelIncreaseMultiplier;
    uint256 public trendChangeStep;
    int256 public levelDecreaseMultiplierafterTrend;
    uint256 public profitPercentage;
    uint256 public royaltyProfitPercent;
    uint256 public creatorProfitPercent;
    uint256 public profitBeforeTrendChange; // Profit percentage before trend change

    // Balances and counters
    uint256 public override totalLaunchSold;
    uint256 public override contractCollateralBalance; // WETH balance for backing
    uint256 public launchBalance; // Main token balance
    uint256 public tokensEarned;
    uint256 public actualProfit;

    // Return tracking variables
    uint256 public currentStepEarned;
    uint256 public remainderOfStepEarned;
    uint256 public quantityTokensPerLevelEarned;
    uint256 public currentPriceEarned;

    // Offset variables
    uint256 public offsetTokens;
    uint256 public offsetStep;
    uint256 public offsetPrice;
    uint256 public remainderOffsetTokens;
    uint256 public sizeOffsetStep;

    // Collateral token variables
    address public collateralAddress;

    // Market makers
    mapping(address => bool) public marketMakerAddresses;

    // Profit tracking
    uint256 public ownerCollateralBalance; // Owner's profit balance (universal for both ETH and collateral tokens)
    uint256 public royaltyCollateralBalance; // Royalty profit balance (universal for both ETH and collateral tokens)
    bool public override profitInTime; // true = immediate, false = on request

    // Deferred withdrawal
    bool public override canWithdrawal;
    uint256 public launchDeferredWithdrawalDate;
    uint256 public launchDeferredWithdrawalAmount;
    address public recipientDeferredWithdrawalLaunch;
    uint256 public collateralTokenDeferredWithdrawalDate;
    address public recipientDeferredWithdrawalCollateralToken;

    // Return wallet change proposal
    address public proposedReturnWalletAddress; // Proposed return wallet address
    uint256 public proposedReturnWalletChangeTime; // Time when return wallet change was proposed

    // Old contract address change control

    // Unaccounted balances for gradual processing
    uint256 public unaccountedCollateralBalance; // Unaccounted collateral balance
    uint256 public unaccountedOffset; // Unaccounted offset balance
    uint256 public unaccountedOffsetLaunchBalance; // Unaccounted offset token balance for gradual processing
    uint256 public unaccountedReturnBuybackBalance; // Unaccounted return buyback balance for gradual processing

    // Initialization flag
    bool public isInitialized; // Flag indicating whether the contract's initialization is complete

    modifier onlyOwnerOrOldContract() {
        require(msg.sender == owner() || oldContractAddress[msg.sender], AccessDenied());
        _;
    }

    modifier onlyActiveContract() {
        require(isActive, ContractNotActive());
        _;
    }

    modifier onlyReserveOwner() {
        require(msg.sender == reserveOwner, OnlyReserveOwner());
        _;
    }

    modifier onlyDAO() {
        require(msg.sender == daoAddress, AccessDenied());
        _;
    }

    constructor(InitParams memory params) Ownable(params.initialOwner) {
        require(params.initialPricePerToken > 0, InitialPriceMustBePositive());
        require(params.levelDecreaseMultiplierafterTrend < int256(Constants.PERCENTAGE_DIVISOR), MultiplierTooHigh());
        require(params.levelIncreaseMultiplier > 0, MultiplierTooLow());
        require(params.priceIncrementMultiplier > 0, PriceIncrementTooLow());
        require(
            params.royaltyProfitPercent > 1 && params.royaltyProfitPercent <= Constants.MAX_ROYALTY_PERCENT,
            InvalidRoyaltyProfitPercentage()
        );
        require(params.profitBeforeTrendChange > 0, ProfitBeforeTrendChangeMustBePositive());

        isActive = true;
        launchToken = IERC20(params.launchToken);

        returnWalletAddress = params.returnWalletAddress;
        royaltyWalletAddress = params.royaltyWalletAddress;
        lockEndTime = params.lockEndTime;
        initialPricePerToken = params.initialPricePerToken;
        firstLevelTokenQuantity = params.firstLevelTokenQuantity;
        priceIncrementMultiplier = params.priceIncrementMultiplier;
        levelIncreaseMultiplier = params.levelIncreaseMultiplier;
        trendChangeStep = params.trendChangeStep;
        levelDecreaseMultiplierafterTrend = params.levelDecreaseMultiplierafterTrend;
        profitPercentage = params.profitPercentage;
        offsetTokens = params.offsetTokens;
        controlPeriod = _getPeriod(params.controlPeriod);
        collateralAddress = params.collateralAddress;
        royaltyProfitPercent = params.royaltyProfitPercent;
        creatorProfitPercent = Constants.PERCENTAGE_DIVISOR - params.royaltyProfitPercent;
        profitBeforeTrendChange = params.profitBeforeTrendChange;
        daoAddress = params.daoAddress != address(0) ? params.daoAddress : params.initialOwner;

        // Initialize state variables
        currentStep = 0;
        remainderOfStep = params.firstLevelTokenQuantity;
        quantityTokensPerLevel = params.firstLevelTokenQuantity;
        currentPrice = params.initialPricePerToken;
        controlDay = block.timestamp + Constants.THIRTY_DAYS;
        reserveOwner = params.initialOwner;

        // Initialize market makers
        marketMakerAddresses[params.marketMakerAddress] = true;

        // Initialize offset variables
        offsetStep = 0;
        offsetPrice = params.initialPricePerToken;
        remainderOffsetTokens = params.firstLevelTokenQuantity;
        sizeOffsetStep = params.firstLevelTokenQuantity;

        // Initialize earned tracking
        currentStepEarned = 0;
        remainderOfStepEarned = params.firstLevelTokenQuantity;
        quantityTokensPerLevelEarned = params.firstLevelTokenQuantity;
        currentPriceEarned = params.initialPricePerToken;

        recipientDeferredWithdrawalLaunch = params.initialOwner;
        recipientDeferredWithdrawalCollateralToken = params.initialOwner;

        profitInTime = true;
        canWithdrawal = true;

        if (params.offsetTokens > 0) {
            unaccountedOffset = params.offsetTokens;
            isInitialized = false; // Will be set to true after processing offset
        } else {
            isInitialized = true; // No offset to process
        }

        // Set old contract addresses
        for (uint256 i = 0; i < params.oldContractAddresses.length; i++) {
            oldContractAddress[params.oldContractAddresses[i]] = true;
        }

        // Check that return wallet and royalty wallet addresses don't match old contracts and each other
        require(!oldContractAddress[params.returnWalletAddress], CannotBeSelf());
        require(!oldContractAddress[params.royaltyWalletAddress], CannotBeSelf());
        require(params.returnWalletAddress != params.royaltyWalletAddress, CannotBeSelf());
    }

    receive() external payable {}

    /**
     * @dev Extend lock period
     */
    function extendLock(uint256 additionalTime) external override onlyOwner {
        require((lockEndTime + additionalTime) - block.timestamp < Constants.FIVE_YEARS, LockCannotExceedFiveYears());
        require(
            additionalTime == Constants.HALF_YEAR || additionalTime == Constants.TEN_MINUTES
                || additionalTime == Constants.THREE_MONTHS,
            InvalidTimePeriod()
        );

        lockEndTime += additionalTime;
        emit LockExtended(additionalTime);
    }

    /**
     * @dev Block or unblock deferred withdrawal
     * @notice If called when less than 60 days remain until the end of the lock (i.e., when users can already interact with the contract),
     * the owner can re-enable withdrawal—for example, to transfer tokens to another contract with a lock (for a safe migration).
     */
    function blockDeferredWithdrawal() external override onlyOwner {
        if (canWithdrawal) {
            canWithdrawal = false;
        } else {
            require(lockEndTime - block.timestamp < Constants.SIXTY_DAYS, CannotActivateWithdrawalTooCloseToLockEnd());
            canWithdrawal = true;
        }
    }

    /**
     * @dev Verifies and registers the old contract address.
     * Requires that the address is non-zero and does not match the main contract addresses.
     * Can be changed no more than once every 40 days.
     * @param oldContractAddr Address of the old contract to register
     */
    function registerOldContract(address oldContractAddr) external onlyOwner {
        require(!_checkTradingAccess(), LockIsActive());
        require(oldContractAddr != address(0), OldContractAddressZero());
        require(
            oldContractAddr != owner() && oldContractAddr != reserveOwner && oldContractAddr != address(launchToken)
                && oldContractAddr != collateralAddress
                && oldContractAddr != returnWalletAddress
                && oldContractAddr != royaltyWalletAddress && oldContractAddr != recipientDeferredWithdrawalLaunch
                && oldContractAddr != recipientDeferredWithdrawalCollateralToken && !marketMakerAddresses[oldContractAddr],
            OldContractAddressConflict()
        );

        oldContractAddress[oldContractAddr] = true;
        emit OldContractRegistered(oldContractAddr);
    }

    /**
     * @dev Schedule deferred withdrawal of main token
     */
    function tokenDeferredWithdrawal(address recipientAddress, uint256 amount) external override onlyOwner {
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
    function stopTokenDeferredWithdrawal() external override {
        require(msg.sender == owner() || msg.sender == royaltyWalletAddress || msg.sender == daoAddress, AccessDenied());
        require(launchDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());

        launchDeferredWithdrawalDate = 0;
        launchDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalLaunch = owner();
    }

    /**
     * @dev Confirm and execute deferred withdrawal of main token
     */
    function confirmTokenDeferredWithdrawal() external override onlyOwner nonReentrant {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(launchDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());
        require(block.timestamp >= launchDeferredWithdrawalDate, WithdrawalDateNotReached());
        require(launchBalance > totalLaunchSold, InsufficientTokenBalance());
        require(launchBalance - totalLaunchSold >= launchDeferredWithdrawalAmount, InsufficientAmount());
        require(block.timestamp <= launchDeferredWithdrawalDate + Constants.SEVEN_DAYS, WithdrawalDateNotReached());

        launchToken.safeTransfer(recipientDeferredWithdrawalLaunch, launchDeferredWithdrawalAmount);

        launchBalance -= launchDeferredWithdrawalAmount;
        launchDeferredWithdrawalDate = 0;
        launchDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalLaunch = owner();
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

        emit DeferredWithdrawalScheduled(recipientAddress, contractCollateralBalance, collateralTokenDeferredWithdrawalDate);
    }

    /**
     * @dev Cancel deferred withdrawal of collateral tokens
     */
    function stopCollateralDeferredWithdrawal() external override {
        require(msg.sender == owner() || msg.sender == royaltyWalletAddress || msg.sender == daoAddress, AccessDenied());
        require(collateralTokenDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());

        collateralTokenDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalCollateralToken = owner();
    }

    /**
     * @dev Confirm and execute deferred withdrawal of collateral tokens
     */
    function confirmCollateralDeferredWithdrawal() external override onlyOwner nonReentrant {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(collateralTokenDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());
        require(block.timestamp >= collateralTokenDeferredWithdrawalDate, WithdrawalDateNotReached());
        require(
            block.timestamp <= collateralTokenDeferredWithdrawalDate + Constants.SEVEN_DAYS,
            CollateralTokenWithdrawalWindowExpired()
        );

        uint256 collateralBalance = contractCollateralBalance;
        contractCollateralBalance = 0;
        collateralTokenDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalCollateralToken = owner();
        isActive = false;

        emit CollateralDeferredWithdrawalConfirmed(recipientDeferredWithdrawalCollateralToken, collateralBalance);

        IERC20(collateralAddress).safeIncreaseAllowance(recipientDeferredWithdrawalCollateralToken, collateralBalance);
        IProofOfCapital(recipientDeferredWithdrawalCollateralToken).deposit(collateralBalance);
    }

    /**
     * @dev Assign new owner
     */
    function assignNewOwner(address newOwner) external override onlyReserveOwner {
        require(newOwner != address(0), InvalidNewOwner());
        require(!oldContractAddress[newOwner], OldContractAddressConflict());

        if (owner() == reserveOwner) {
            _transferOwnership(newOwner);
            _transferReserveOwner(newOwner);
        } else {
            _transferOwnership(newOwner);
        }

        if (owner() == daoAddress) {
            daoAddress = newOwner;
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
    }


    /**
     * @dev Propose return wallet address change (requires lock to be active)
     */
    function proposeReturnWalletChange(address newReturnWalletAddress) external onlyOwner {
        require(!_checkTradingAccess(), LockIsActive());
        require(newReturnWalletAddress != address(0), InvalidAddress());
        require(
            newReturnWalletAddress != owner() && newReturnWalletAddress != reserveOwner
                && newReturnWalletAddress != address(launchToken) && newReturnWalletAddress != collateralAddress
                && newReturnWalletAddress != returnWalletAddress && newReturnWalletAddress != royaltyWalletAddress
                && newReturnWalletAddress != recipientDeferredWithdrawalLaunch
                && newReturnWalletAddress != recipientDeferredWithdrawalCollateralToken
                && !marketMakerAddresses[newReturnWalletAddress] && !oldContractAddress[newReturnWalletAddress],
            OldContractAddressConflict()
        );

        proposedReturnWalletAddress = newReturnWalletAddress;
        proposedReturnWalletChangeTime = block.timestamp;
        emit ReturnWalletChangeProposed(newReturnWalletAddress, block.timestamp);
    }

    /**
     * @dev Confirm proposed return wallet address change after 24 hours
     */
    function confirmReturnWalletChange() external onlyOwner {
        require(!_checkTradingAccess(), LockIsActive());
        require(proposedReturnWalletAddress != address(0), NoReturnWalletChangeProposed());
        require(
            block.timestamp >= proposedReturnWalletChangeTime + Constants.ONE_DAY, ReturnWalletChangeDelayNotPassed()
        );

        returnWalletAddress = proposedReturnWalletAddress;
        proposedReturnWalletAddress = address(0);
        proposedReturnWalletChangeTime = 0;
        emit ReturnWalletChangeConfirmed(returnWalletAddress);
    }

    /**
     * @dev Change return wallet address (legacy function for backwards compatibility)
     */
    function changeReturnWallet(address newReturnWalletAddress) external override onlyOwner {
        require(newReturnWalletAddress != address(0), InvalidAddress());
        returnWalletAddress = newReturnWalletAddress;
        emit ReturnWalletChanged(newReturnWalletAddress);
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
        creatorProfitPercent = Constants.PERCENTAGE_DIVISOR - newRoyaltyProfitPercentage;
        emit ProfitPercentageChanged(newRoyaltyProfitPercentage);
    }

    /**
     * @dev Set market maker status for an address
     */
    function setMarketMaker(address marketMakerAddress, bool isMarketMaker) external override onlyOwner {
        require(marketMakerAddress != address(0), InvalidAddress());

        marketMakerAddresses[marketMakerAddress] = isMarketMaker;
        emit MarketMakerStatusChanged(marketMakerAddress, isMarketMaker);
    }

    /**
     * @dev Buy tokens with collateral tokens
     */
    function buyTokens(uint256 amount) external override nonReentrant onlyActiveContract {
        require(amount > 0, InvalidAmount());
        require(!(msg.sender == owner() || oldContractAddress[msg.sender]), UseDepositFunctionForOwners());

        IERC20(collateralAddress).safeTransferFrom(msg.sender, address(this), amount);
        _handleTokenPurchaseCommon(amount);
    }


    /**
     * @dev Deposit collateral tokens (for owners and old contracts)
     */
    function deposit(uint256 amount) external override nonReentrant onlyActiveContract onlyOwnerOrOldContract {
        require(amount > 0, InvalidAmount());

        IERC20(collateralAddress).safeTransferFrom(msg.sender, address(this), amount);
        _handleOwnerDeposit(amount);
    }


    /**
     * @dev Deposit launch tokens back to contract (for owners and old contracts)
     * Used when owner needs to return tokens and potentially trigger offset reduction
     */
    function depositTokens(uint256 amount) external nonReentrant onlyActiveContract onlyOwnerOrOldContract {
        require(amount > 0, InvalidAmount());

        launchToken.safeTransferFrom(msg.sender, address(this), amount);

        // Check if we should accumulate in unaccountedOffsetLaunchBalance for gradual offset reduction
        if (totalLaunchSold == offsetTokens && (offsetTokens - tokensEarned) >= amount) {
            unaccountedOffsetLaunchBalance += amount;
        } else {
            launchBalance += amount;
        }
    }

    /**
     * @dev Sell tokens back to contract
     */
    function sellTokens(uint256 amount) external override nonReentrant onlyActiveContract {
        require(amount > 0, InvalidAmount());

        launchToken.safeTransferFrom(msg.sender, address(this), amount);

        if (msg.sender == returnWalletAddress) {
            _handleReturnWalletSale(amount);
        } else {
            _handleTokenSale(amount);
        }
    }

    /**
     * @dev Withdraw all tokens after lock period
     * @notice Only DAO can withdraw all tokens after lock period ends
     */
    function withdrawAllTokens() external override onlyDAO nonReentrant {
        require(block.timestamp >= lockEndTime, LockPeriodNotEnded());

        uint256 availableTokens = launchBalance - totalLaunchSold;
        require(availableTokens > 0, NoTokensToWithdraw());

        launchToken.safeTransfer(daoAddress, availableTokens);

        // Reset state
        currentStep = 0;
        launchBalance = 0;
        totalLaunchSold = 0;
        tokensEarned = 0;
        quantityTokensPerLevel = firstLevelTokenQuantity;
        currentPrice = initialPricePerToken;
        remainderOfStep = firstLevelTokenQuantity;
        currentStepEarned = 0;
        remainderOfStepEarned = firstLevelTokenQuantity;
        quantityTokensPerLevelEarned = firstLevelTokenQuantity;
        currentPriceEarned = initialPricePerToken;
        isActive = false;

        emit AllTokensWithdrawn(daoAddress, availableTokens);
    }

    /**
     * @dev Withdraw all collateral tokens after lock period
     * @notice Only DAO can withdraw all collateral tokens after lock period ends
     */
    function withdrawAllCollateralTokens() external override onlyDAO nonReentrant {
        require(block.timestamp >= lockEndTime, LockPeriodNotEnded());
        require(contractCollateralBalance > 0, NoCollateralTokensToWithdraw());

        uint256 withdrawnAmount = contractCollateralBalance;
        contractCollateralBalance = 0;
        isActive = false;
        _transferCollateralTokens(daoAddress, withdrawnAmount);

        emit AllCollateralTokensWithdrawn(daoAddress, withdrawnAmount);
    }

    /**
     * @dev Set DAO address (can only be called by current DAO)
     */
    function setDAO(address newDAOAddress) external {
        require(msg.sender == daoAddress, AccessDenied());
        require(newDAOAddress != address(0), InvalidDAOAddress());
        daoAddress = newDAOAddress;
        emit DAOAddressChanged(newDAOAddress);
    }

    /**
     * @dev Calculate unaccounted collateral balance gradually
     * @param amount Amount of collateral to process
     */
    function calculateUnaccountedCollateralBalance(uint256 amount) external nonReentrant {
        if (!_checkTradingAccess()) {
            if (_checkUnlockWindow()) {
                controlDay += Constants.THIRTY_DAYS;
            }
            _checkOwner();
        }

        require(unaccountedCollateralBalance >= amount, InsufficientUnaccountedCollateralBalance());

        uint256 deltaCollateralBalance = _calculateChangeOffsetCollateral(amount);
        unaccountedCollateralBalance -= amount;
        contractCollateralBalance += deltaCollateralBalance;

        uint256 change = amount - deltaCollateralBalance;
        if (change > 0) {
            _transferCollateralTokens(daoAddress, change);
        }

        emit UnaccountedCollateralBalanceProcessed(amount, deltaCollateralBalance, change);
    }

    /**
     * @dev Calculate unaccounted offset balance gradually
     * @param amount Amount of offset tokens to process
     */
    function calculateUnaccountedOffsetBalance(uint256 amount) external nonReentrant {
        if (!_checkTradingAccess()) {
            if (_checkUnlockWindow()) {
                controlDay += Constants.THIRTY_DAYS;
            }
            _checkOwner();
        }
        require(!isInitialized, ContractAlreadyInitialized());
        require(unaccountedOffset >= amount, InsufficientUnaccountedOffsetBalance());

        _calculateOffset(amount);
        unaccountedOffset -= amount;

        // Check if all offset has been processed
        if (unaccountedOffset == 0) {
            isInitialized = true;
        }

        emit UnaccountedOffsetBalanceProcessed(amount);
    }

    /**
     * @dev Calculate unaccounted offset token balance gradually (for reducing offset when tokens are returned)
     * @param amount Amount of tokens to process
     */
    function calculateUnaccountedOffsetTokenBalance(uint256 amount) external nonReentrant {
        if (!_checkTradingAccess()) {
            if (_checkUnlockWindow()) {
                controlDay += Constants.THIRTY_DAYS;
            }
            _checkOwner();
        }

        require(unaccountedOffsetLaunchBalance >= amount, InsufficientUnaccountedOffsetTokenBalance());

        _calculateChangeOffsetToken(amount);
        unaccountedOffsetLaunchBalance -= amount;

        emit UnaccountedOffsetTokenBalanceProcessed(amount);
    }

    /**
     * @dev Get profit on request
     */
    function getProfitOnRequest() external override nonReentrant {
        if (msg.sender == owner()) {
            require(ownerCollateralBalance > 0, NoProfitAvailable());
            uint256 profitAmount = ownerCollateralBalance;
            _transferCollateralTokens(owner(), ownerCollateralBalance);
            ownerCollateralBalance = 0;
            emit ProfitWithdrawn(owner(), profitAmount, true);
        } else {
            require(msg.sender == royaltyWalletAddress, AccessDenied());
            require(royaltyCollateralBalance > 0, NoProfitAvailable());
            uint256 profitAmount = royaltyCollateralBalance;
            _transferCollateralTokens(royaltyWalletAddress, royaltyCollateralBalance);
            royaltyCollateralBalance = 0;
            emit ProfitWithdrawn(royaltyWalletAddress, profitAmount, false);
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

    function tokenAvailable() external view override returns (uint256) {
        if (totalLaunchSold < tokensEarned) {
            return 0;
        }
        return totalLaunchSold - tokensEarned;
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


    function _handleOwnerDeposit(uint256 value) internal {
        if (offsetTokens > tokensEarned) {
            // Accumulate in unaccounted balance for gradual processing
            unaccountedCollateralBalance += value;
        }
    }

    /**
     * @dev Common logic for handling token purchases with any collateral currency
     * @param collateralAmount Amount of collateral currency (ETH or collateral token)
     */
    function _handleTokenPurchaseCommon(uint256 collateralAmount) internal {
        if (!_checkTradingAccess()) {
            if (_checkUnlockWindow()) {
                controlDay += Constants.THIRTY_DAYS;
            }
            require(marketMakerAddresses[msg.sender], TradingNotAllowedOnlyMarketMakers());
        }
        require(launchBalance > totalLaunchSold, InsufficientTokenBalance());

        uint256 totalTokens = _calculateTokensToGiveForCollateralAmount(collateralAmount);
        uint256 creatorProfit = (actualProfit * creatorProfitPercent) / Constants.PERCENTAGE_DIVISOR;
        uint256 royaltyProfit = (actualProfit * royaltyProfitPercent) / Constants.PERCENTAGE_DIVISOR;

        if (profitInTime) {
            _transferCollateralTokens(owner(), creatorProfit);
            _transferCollateralTokens(royaltyWalletAddress, royaltyProfit);
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
        totalLaunchSold += totalTokens;

        launchToken.safeTransfer(msg.sender, totalTokens);

        emit TokensPurchased(msg.sender, totalTokens, collateralAmount);
    }

    function _handleReturnWalletSale(uint256 amount) internal {
        uint256 collateralAmountToPay = 0;

        // Check to prevent arithmetic underflow
        uint256 tokensAvailableForReturnBuyback = 0;
        if (totalLaunchSold > tokensEarned) {
            tokensAvailableForReturnBuyback = totalLaunchSold - tokensEarned;
        }

        // Add unaccounted balance from previous calls
        uint256 totalAmount = amount + unaccountedReturnBuybackBalance;
        uint256 effectiveAmount =
            totalAmount < tokensAvailableForReturnBuyback ? totalAmount : tokensAvailableForReturnBuyback;

        // Store the difference for future processing
        uint256 remainingAmount = totalAmount - effectiveAmount;
        unaccountedReturnBuybackBalance = remainingAmount;

        if (offsetTokens > tokensEarned) {
            uint256 offsetAmount = offsetTokens - tokensEarned;

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

        tokensEarned += effectiveAmount;
        require(contractCollateralBalance >= collateralAmountToPay, InsufficientCollateralBalance());
        contractCollateralBalance -= collateralAmountToPay;
        launchBalance += amount;

        if (collateralAmountToPay > 0) {
            _transferCollateralTokens(daoAddress, collateralAmountToPay);
        }
    }

    function _handleTokenSale(uint256 amount) internal {
        if (!_checkTradingAccess()) {
            if (_checkUnlockWindow()) {
                controlDay += Constants.THIRTY_DAYS;
            }
            require(marketMakerAddresses[msg.sender], TradingNotAllowedOnlyMarketMakers());
        }
        uint256 maxEarnedOrOffset = offsetTokens > tokensEarned ? offsetTokens : tokensEarned;

        // Check for tokens available for buyback (prevents underflow and ensures > 0)
        require(totalLaunchSold > maxEarnedOrOffset, NoTokensAvailableForBuyback());

        uint256 tokensAvailableForBuyback = totalLaunchSold - maxEarnedOrOffset;
        require(tokensAvailableForBuyback >= amount, InsufficientTokensForBuyback());

        uint256 collateralAmountToPay = _calculateCollateralToPayForTokenAmount(amount);
        require(contractCollateralBalance >= collateralAmountToPay, InsufficientCollateralBalance());

        contractCollateralBalance -= collateralAmountToPay;
        totalLaunchSold -= amount;

        _transferCollateralTokens(msg.sender, collateralAmountToPay);

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

    function _calculateTokensPerLevel(uint256 tokensPerLevel, uint256 currentStepParam)
        internal
        view
        returns (uint256)
    {
        if (currentStepParam > trendChangeStep) {
            return (tokensPerLevel * uint256(int256(Constants.PERCENTAGE_DIVISOR) - levelDecreaseMultiplierafterTrend))
                / Constants.PERCENTAGE_DIVISOR;
        } else {
            return
                (tokensPerLevel * uint256(int256(Constants.PERCENTAGE_DIVISOR) + levelIncreaseMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
        }
    }

    // Full implementation of calculation functions based on Tact contract
    function _calculateOffset(uint256 amountTokens) internal {
        int256 remainingOffsetTokens = int256(amountTokens);
        uint256 localCurrentStep = offsetStep;
        int256 remainderOfStepLocal = int256(remainderOffsetTokens);
        uint256 tokensPerLevel = sizeOffsetStep;
        uint256 currentPriceLocal = currentPrice;

        while (remainingOffsetTokens > 0) {
            int256 tokensAvailableInStep = remainderOfStepLocal;

            if (remainingOffsetTokens >= tokensAvailableInStep) {
                remainingOffsetTokens -= int256(tokensAvailableInStep);
                localCurrentStep += 1;

                tokensPerLevel = _calculateTokensPerLevel(tokensPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(tokensPerLevel);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                remainderOfStepLocal -= int256(remainingOffsetTokens);
                remainingOffsetTokens = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOffsetTokens = uint256(remainderOfStepLocal);
        sizeOffsetStep = tokensPerLevel;
        offsetPrice = currentPriceLocal;

        currentStep = localCurrentStep;
        quantityTokensPerLevel = tokensPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = uint256(remainderOfStepLocal);
        launchBalance += amountTokens;
        totalLaunchSold += amountTokens;
    }

    /**
     * @dev Calculate change in offset when adding tokens (reducing offset)
     * @param amountToken Amount of tokens being added
     * @return Current step after recalculation
     */
    function _calculateChangeOffsetToken(uint256 amountToken) internal returns (uint256) {
        int256 remainingAddTokens = int256(amountToken);
        uint256 localCurrentStep = offsetStep;
        int256 remainderOfStepLocal = int256(remainderOffsetTokens);
        uint256 tokensPerLevel = sizeOffsetStep;
        uint256 currentPriceLocal = offsetPrice;

        while (remainingAddTokens > 0) {
            int256 tokensAvailableInStep = int256(tokensPerLevel) - remainderOfStepLocal;

            if (remainingAddTokens >= tokensAvailableInStep) {
                remainingAddTokens -= tokensAvailableInStep;

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) - levelDecreaseMultiplierafterTrend);
                    } else {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) + levelIncreaseMultiplier);
                    }
                    currentPriceLocal = (currentPriceLocal * Constants.PERCENTAGE_DIVISOR)
                        / (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier);
                    localCurrentStep -= 1;
                    remainderOfStepLocal = 0;
                } else {
                    remainderOfStepLocal = int256(tokensPerLevel);
                    remainingAddTokens = 0;
                }
            } else {
                remainderOfStepLocal += remainingAddTokens;
                remainingAddTokens = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOffsetTokens = uint256(remainderOfStepLocal);
        offsetPrice = currentPriceLocal;
        sizeOffsetStep = tokensPerLevel;

        offsetTokens -= amountToken;

        currentStep = localCurrentStep;
        quantityTokensPerLevel = tokensPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = uint256(remainderOfStepLocal);
        totalLaunchSold -= amountToken;

        return localCurrentStep;
    }

    function _calculateChangeOffsetCollateral(uint256 amountCollateral) internal returns (uint256) {
        int256 remainingAddCollateral = int256(amountCollateral);
        uint256 remainingOffsetTokensLocal = offsetTokens;
        int256 remainingAddTokens = int256(offsetTokens) - int256(tokensEarned);
        uint256 localCurrentStep = offsetStep;
        uint256 remainderOfStepLocal = remainderOffsetTokens;
        uint256 tokensPerLevel = sizeOffsetStep;
        uint256 currentPriceLocal = offsetPrice;

        while (remainingAddCollateral > 0 && remainingAddTokens > 0) {
            uint256 tokensAvailableInStep = tokensPerLevel - remainderOfStepLocal;
            uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
            uint256 collateralInStep = (uint256(tokensAvailableInStep) * currentPriceLocal) / Constants.PRICE_PRECISION;
            uint256 collateralRealInStep =
                (collateralInStep * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal)) / Constants.PERCENTAGE_DIVISOR;

            if (remainingAddCollateral >= int256(collateralRealInStep) && remainingAddTokens >= int256(tokensAvailableInStep)) {
                remainingAddCollateral -= int256(collateralRealInStep);
                remainingOffsetTokensLocal -= tokensAvailableInStep;
                remainingAddTokens -= int256(tokensAvailableInStep);

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) - levelDecreaseMultiplierafterTrend);
                    } else {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) + levelIncreaseMultiplier);
                    }
                    currentPriceLocal = (currentPriceLocal * Constants.PERCENTAGE_DIVISOR)
                        / (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier);
                }

                if (localCurrentStep > currentStepEarned) {
                    localCurrentStep -= 1;
                    remainderOfStepLocal = 0;
                } else {
                    localCurrentStep = currentStepEarned;
                    remainderOfStepLocal = tokensPerLevel;
                    remainingAddTokens = 0;
                }
            } else {
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;

                uint256 collateralToPayForStep = 0;
                uint256 tokensToBuyInThisStep = 0;

                if (remainingAddCollateral >= int256(collateralRealInStep)) {
                    collateralToPayForStep = (uint256(remainingAddTokens) * adjustedPrice) / Constants.PRICE_PRECISION;
                    tokensToBuyInThisStep = uint256(remainingAddTokens);
                } else {
                    collateralToPayForStep = uint256(remainingAddCollateral);
                    tokensToBuyInThisStep = (uint256(remainingAddCollateral) * Constants.PRICE_PRECISION) / adjustedPrice;
                }

                remainderOfStepLocal += tokensToBuyInThisStep;
                remainingAddCollateral -= int256(collateralToPayForStep);
                remainingOffsetTokensLocal -= tokensToBuyInThisStep;
                remainingAddTokens = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOffsetTokens = remainderOfStepLocal;
        offsetPrice = currentPriceLocal;
        sizeOffsetStep = tokensPerLevel;
        offsetTokens = remainingOffsetTokensLocal;

        return (amountCollateral - uint256(remainingAddCollateral));
    }

    function _calculateTokensToGiveForCollateralAmount(uint256 collateralAmount) internal returns (uint256) {
        uint256 tokensToGive = 0;
        int256 remainingCollateralAmount = int256(collateralAmount);
        uint256 localCurrentStep = currentStep;
        int256 remainderOfStepLocal = int256(remainderOfStep);
        uint256 tokensPerLevel = quantityTokensPerLevel;
        uint256 currentPriceLocal = currentPrice;
        uint256 totalProfit = 0;
        uint256 remainderOfTokens = launchBalance - totalLaunchSold;

        while (remainingCollateralAmount > 0 && remainderOfTokens >= tokensToGive) {
            int256 tokensAvailableInStep = remainderOfStepLocal;
            int256 collateralRequiredForStep =
                (int256(tokensAvailableInStep) * int256(currentPriceLocal)) / int256(Constants.PRICE_PRECISION);

            if (remainingCollateralAmount >= collateralRequiredForStep) {
                tokensToGive += uint256(tokensAvailableInStep);
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);

                uint256 profitInStep =
                    (uint256(collateralRequiredForStep) * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingCollateralAmount -= collateralRequiredForStep;
                localCurrentStep += 1;

                tokensPerLevel = _calculateTokensPerLevel(tokensPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(tokensPerLevel);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 tokensToBuyInThisStep =
                    (uint256(remainingCollateralAmount) * Constants.PRICE_PRECISION) / currentPriceLocal;
                tokensToGive += tokensToBuyInThisStep;
                uint256 collateralSpentInThisStep = uint256(remainingCollateralAmount);

                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 profitInStep = (collateralSpentInThisStep * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingCollateralAmount = 0;
                remainderOfStepLocal -= int256(tokensToBuyInThisStep);
            }
        }

        if (remainderOfTokens < tokensToGive) {
            tokensToGive = remainderOfTokens;
        }

        currentStep = localCurrentStep;
        quantityTokensPerLevel = tokensPerLevel;
        currentPrice = currentPriceLocal;
        actualProfit = totalProfit;

        remainderOfStep = uint256(remainderOfStepLocal);

        return tokensToGive;
    }

    function _calculateCollateralToPayForTokenAmount(uint256 tokenAmount) internal returns (uint256) {
        uint256 collateralAmountToPay = 0;
        int256 remainingTokenAmount = int256(tokenAmount);
        uint256 localCurrentStep = currentStep;
        int256 remainderOfStepLocal = int256(remainderOfStep);
        uint256 tokensPerLevel = quantityTokensPerLevel;
        uint256 currentPriceLocal = currentPrice;

        while (remainingTokenAmount > 0) {
            int256 tokensAvailableInStep = int256(tokensPerLevel) - remainderOfStepLocal;

            if (remainingTokenAmount >= int256(tokensAvailableInStep)) {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 collateralToPayForStep =
                    (uint256(tokensAvailableInStep) * adjustedPrice) / Constants.PRICE_PRECISION;
                collateralAmountToPay += collateralToPayForStep;

                remainingTokenAmount -= int256(tokensAvailableInStep);

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) - levelDecreaseMultiplierafterTrend);
                    } else {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / uint256(int256(Constants.PERCENTAGE_DIVISOR) + levelIncreaseMultiplier);
                    }
                    currentPriceLocal = (currentPriceLocal * Constants.PERCENTAGE_DIVISOR)
                        / (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier);
                }

                if (localCurrentStep > currentStepEarned) {
                    localCurrentStep -= 1;
                    remainderOfStepLocal = 0;
                } else {
                    localCurrentStep = currentStepEarned;
                    remainderOfStepLocal = int256(tokensPerLevel);
                    remainingTokenAmount = 0;
                }
            } else {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 collateralToPayForStep =
                    (uint256(remainingTokenAmount) * adjustedPrice) / Constants.PRICE_PRECISION;
                collateralAmountToPay += collateralToPayForStep;

                remainderOfStepLocal += int256(remainingTokenAmount);
                remainingTokenAmount = 0;
            }
        }

        currentStep = localCurrentStep;
        quantityTokensPerLevel = tokensPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = uint256(remainderOfStepLocal);

        return collateralAmountToPay;
    }

    function _calculateCollateralForTokenAmountEarned(uint256 tokenAmount) internal returns (uint256) {
        uint256 collateralAmountToPay = 0;
        int256 remainingTokenAmount = int256(tokenAmount);
        uint256 localCurrentStep = currentStepEarned;
        int256 remainderOfStepLocal = int256(remainderOfStepEarned);
        uint256 tokensPerLevel = quantityTokensPerLevelEarned;
        uint256 currentPriceLocal = currentPriceEarned;

        while (remainingTokenAmount > 0 && localCurrentStep <= currentStep) {
            int256 tokensAvailableInStep = remainderOfStepLocal;

            if (remainingTokenAmount >= int256(tokensAvailableInStep)) {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 collateralToPayForStep =
                    (uint256(tokensAvailableInStep) * adjustedPrice) / Constants.PRICE_PRECISION;
                collateralAmountToPay += collateralToPayForStep;

                localCurrentStep += 1;
                tokensPerLevel = _calculateTokensPerLevel(tokensPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(tokensPerLevel);
                remainingTokenAmount -= int256(tokensAvailableInStep);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 collateralToPayForStep =
                    (uint256(remainingTokenAmount) * adjustedPrice) / Constants.PRICE_PRECISION;
                collateralAmountToPay += collateralToPayForStep;

                remainderOfStepLocal -= remainingTokenAmount;
                remainingTokenAmount = 0;
            }
        }

        currentStepEarned = localCurrentStep;
        quantityTokensPerLevelEarned = tokensPerLevel;
        currentPriceEarned = currentPriceLocal;

        remainderOfStepEarned = uint256(remainderOfStepLocal);

        return collateralAmountToPay;
    }


    /**
     * @dev General transfer function for collateral tokens (ERC20 only)
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _transferCollateralTokens(address to, uint256 amount) internal {
        if (amount == 0) return;

        // Transfer collateral tokens
        IERC20(collateralAddress).safeTransfer(to, amount);
    }

    /**
     * @dev Check if current time is within unlock window period after lock expires
     * Accounts for the fact that we might be in one of the following windows, not the current one
     * @return True if in unlock window, false otherwise
     */
    function _checkUnlockWindow() internal view returns (bool) {
        // Check for underflow
        if (block.timestamp < controlDay) {
            return false;
        }

        uint256 timeSinceControlDay = block.timestamp - controlDay;

        // If more than controlPeriod has passed since the last controlDay, we are not in the current window
        if (timeSinceControlDay > controlPeriod) {
            // Check if we are in one of the following windows (every 30 days)
            uint256 periodsSinceControlDay = timeSinceControlDay / Constants.THIRTY_DAYS;
            uint256 timeInCurrentPeriod = timeSinceControlDay - (periodsSinceControlDay * Constants.THIRTY_DAYS);
            // If we are still not in a window, return true (need to add 30 days)
            return timeInCurrentPeriod > controlPeriod;
        }
        return false;
    }
}
