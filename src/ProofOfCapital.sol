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

// All royalties collected are automatically used to repurchase the project’s core token, as
// specified on the website, and are returned to the contract.

// This is the third version of the contract. It introduces the following features: the ability to choose any jetton as support, build support with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.

pragma solidity 0.8.29;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IProofOfCapital.sol";
import "./utils/Constant.sol";

/**
 * @title ProofOfCapital
 * @dev Upgradeable Proof of Capital contract using UUPS proxy pattern
 * @notice This contract allows locking desired part of token issuance for selected period with guaranteed buyback
 */
contract ProofOfCapital is
    Initializable,
    ReentrancyGuardTransientUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IProofOfCapital
{
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
    error LockCannotExceedTwoYears();
    error InvalidTimePeriod();
    error CannotActivateWithdrawalTooCloseToLockEnd();
    error InvalidRecipientOrAmount();
    error DeferredWithdrawalBlocked();
    error MainTokenDeferredWithdrawalAlreadyScheduled();
    error NoDeferredWithdrawalScheduled();
    error WithdrawalDateNotReached();
    error InsufficientTokenBalance();
    error InsufficientAmount();
    error InvalidRecipient();
    error SupportDeferredWithdrawalAlreadyScheduled();
    error InvalidNewOwner();
    error InvalidReserveOwner();
    error SameModeAlreadyActive();
    error SameUnwrapModeAlreadyActive();
    error InvalidAddress();
    error OnlyRoyaltyWalletCanChange();
    error InvalidPercentage();
    error CannotDecreaseRoyalty();
    error CannotIncreaseRoyalty();
    error CannotBeSelf();
    error InvalidAmount();
    error UseDepositFunctionForOwners();
    error UseSupportTokenInstead();
    error InvalidETHAmount();
    error LockPeriodNotEnded();
    error NoTokensToWithdraw();
    error NoSupportTokensToWithdraw();
    error ProfitModeNotActive();
    error NoProfitAvailable();
    error TradingNotAllowedOnlyMarketMakers();
    error InsufficientSupportBalance();
    error NoTokensAvailableForBuyback();
    error InsufficientTokensForBuyback();
    error InsufficientSoldTokens();
    error UpgradeAlreadyProposed();
    error NoUpgradeProposed();
    error UpgradeProposalExpired();
    error UpgradeConfirmationPeriodNotPassed();
    error UpgradeNotConfirmed();
    error OnlyRoyaltyCanProposeUpgrade();

    // Struct for initialization parameters to avoid "Stack too deep" error
    struct InitParams {
        address launchToken;
        address marketMakerAddress;
        address returnWalletAddress;
        address royaltyWalletAddress;
        address wethAddress;
        uint256 lockEndTime;
        uint256 initialPricePerToken;
        uint256 firstLevelTokenQuantity;
        uint256 priceIncrementMultiplier;
        uint256 levelIncreaseMultiplier;
        uint256 trendChangeStep;
        uint256 levelDecreaseMultiplierafterTrend;
        uint256 profitPercentage;
        uint256 offsetTokens;
        uint256 controlPeriod;
        address tokenSupportAddress;
        uint256 royaltyProfitPercent;
        address[] oldContractAddresses; // Array of old contract addresses
    }

    // Contract state
    bool public override isActive;
    mapping(address => bool) public oldContractAddress;

    // Core addresses
    address public reserveOwner;
    IERC20 public launchToken;
    address public returnWalletAddress;
    address public royaltyWalletAddress;
    address public wethAddress;

    // Time and control variables
    uint256 public override lockEndTime;
    uint256 public controlDay;
    uint256 public controlPeriod;

    // Pricing and level variables
    uint256 public initialPricePerToken;
    uint256 public firstLevelTokenQuantity;
    uint256 public override currentPrice;
    uint256 public quantityTokensPerLevel;
    uint256 public remainderOfStep;
    uint256 public currentStep;

    // Multipliers and percentages
    uint256 public priceIncrementMultiplier;
    uint256 public levelIncreaseMultiplier;
    uint256 public trendChangeStep;
    uint256 public levelDecreaseMultiplierafterTrend;
    uint256 public profitPercentage;
    uint256 public royaltyProfitPercent;
    uint256 public creatorProfitPercent;

    // Balances and counters
    uint256 public override totalTokensSold;
    uint256 public override contractSupportBalance; // WETH balance for backing
    uint256 public contractTokenBalance; // Main token balance
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

    // Support token variables
    bool public override tokenSupport; // If true, uses support token instead of WETH
    address public tokenSupportAddress;
    address public additionalTokenAddress;

    // Market makers
    mapping(address => bool) public marketMakerAddresses;

    // Profit tracking
    uint256 public ownerSupportBalance; // Owner's profit balance (universal for both ETH and support tokens)
    uint256 public royaltySupportBalance; // Royalty profit balance (universal for both ETH and support tokens)
    bool public override profitInTime; // true = on request, false = immediate

    // Deferred withdrawal
    bool public override canWithdrawal;
    uint256 public mainTokenDeferredWithdrawalDate;
    uint256 public mainTokenDeferredWithdrawalAmount;
    address public recipientDeferredWithdrawalMainToken;
    uint256 public supportTokenDeferredWithdrawalDate;
    address public recipientDeferredWithdrawalSupportToken;

    bool public isNeedToUnwrap; // Controls whether to unwrap WETH to ETH when sending

    // Upgrade control variables
    address public proposedUpgradeImplementation; // Proposed new implementation address
    uint256 public upgradeProposalTime; // When upgrade was proposed by royalty wallet
    uint256 public upgradeConfirmationTime; // When upgrade was confirmed by owner
    bool public upgradeConfirmed; // Whether upgrade is confirmed by owner

    modifier onlyOwnerOrOldContract() {
        require(_msgSender() == owner() || oldContractAddress[_msgSender()], AccessDenied());
        _;
    }

    modifier onlyActiveContract() {
        require(isActive, ContractNotActive());
        _;
    }

    modifier onlyReserveOwner() {
        require(_msgSender() == reserveOwner, OnlyReserveOwner());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(InitParams calldata params) public initializer {
        require(params.initialPricePerToken > 0, InitialPriceMustBePositive());
        require(params.levelDecreaseMultiplierafterTrend < Constants.PERCENTAGE_DIVISOR, MultiplierTooHigh());
        require(params.levelIncreaseMultiplier > 0, MultiplierTooLow());
        require(params.priceIncrementMultiplier > 0, PriceIncrementTooLow());
        require(
            params.royaltyProfitPercent > 1 && params.royaltyProfitPercent <= Constants.MAX_ROYALTY_PERCENT,
            InvalidRoyaltyProfitPercentage()
        );

        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
        __ReentrancyGuardTransient_init();

        isActive = true;
        launchToken = IERC20(params.launchToken);

        returnWalletAddress = params.returnWalletAddress;
        royaltyWalletAddress = params.royaltyWalletAddress;
        wethAddress = params.wethAddress;
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
        tokenSupport = params.tokenSupportAddress == wethAddress;
        tokenSupportAddress = params.tokenSupportAddress;
        royaltyProfitPercent = params.royaltyProfitPercent;
        creatorProfitPercent = Constants.PERCENTAGE_DIVISOR - params.royaltyProfitPercent;

        // Initialize state variables
        currentStep = 0;
        remainderOfStep = params.firstLevelTokenQuantity;
        quantityTokensPerLevel = params.firstLevelTokenQuantity;
        currentPrice = params.initialPricePerToken;
        controlDay = block.timestamp + Constants.THIRTY_DAYS;
        reserveOwner = _msgSender();

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

        recipientDeferredWithdrawalMainToken = _msgSender();
        recipientDeferredWithdrawalSupportToken = _msgSender();

        profitInTime = true;
        canWithdrawal = true;
        isNeedToUnwrap = true; // Default to true - unwrap WETH to ETH when sending

        if (params.offsetTokens > 0) {
            _calculateOffset(params.offsetTokens);
        }

        // Set old contract addresses
        for (uint256 i = 0; i < params.oldContractAddresses.length; i++) {
            oldContractAddress[params.oldContractAddresses[i]] = true;
        }
    }

    /**
     * @dev Extend lock period
     */
    function extendLock(uint256 additionalTime) external override onlyOwner {
        require((lockEndTime + additionalTime) - block.timestamp < Constants.TWO_YEARS, LockCannotExceedTwoYears());
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
     */
    function blockDeferredWithdrawal() external override onlyOwner {
        if (canWithdrawal) {
            canWithdrawal = false;
        } else {
            require(lockEndTime - block.timestamp > Constants.THIRTY_DAYS, CannotActivateWithdrawalTooCloseToLockEnd());
            canWithdrawal = true;
        }
    }

    /**
     * @dev Schedule deferred withdrawal of main token
     */
    function tokenDeferredWithdrawal(address recipientAddress, uint256 amount) external override onlyOwner {
        require(recipientAddress != address(0) && amount > 0, InvalidRecipientOrAmount());
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(mainTokenDeferredWithdrawalAmount == 0, MainTokenDeferredWithdrawalAlreadyScheduled());

        recipientDeferredWithdrawalMainToken = recipientAddress;
        mainTokenDeferredWithdrawalDate = block.timestamp + Constants.THIRTY_DAYS;
        mainTokenDeferredWithdrawalAmount = amount;

        emit DeferredWithdrawalScheduled(recipientAddress, amount, mainTokenDeferredWithdrawalDate);
    }

    /**
     * @dev Cancel deferred withdrawal of main token
     */
    function stopTokenDeferredWithdrawal() external override {
        require(_msgSender() == owner() || _msgSender() == royaltyWalletAddress, AccessDenied());
        require(mainTokenDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());

        mainTokenDeferredWithdrawalDate = 0;
        mainTokenDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalMainToken = owner();
    }

    /**
     * @dev Confirm and execute deferred withdrawal of main token
     */
    function confirmTokenDeferredWithdrawal() external override onlyOwner nonReentrant {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(mainTokenDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());
        require(block.timestamp >= mainTokenDeferredWithdrawalDate, WithdrawalDateNotReached());
        require(contractTokenBalance > totalTokensSold, InsufficientTokenBalance());
        require(contractTokenBalance - totalTokensSold >= mainTokenDeferredWithdrawalAmount, InsufficientAmount());

        launchToken.safeTransfer(recipientDeferredWithdrawalMainToken, mainTokenDeferredWithdrawalAmount);

        contractTokenBalance -= mainTokenDeferredWithdrawalAmount;
        mainTokenDeferredWithdrawalDate = 0;
        mainTokenDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalMainToken = owner();
    }

    /**
     * @dev Schedule deferred withdrawal of support tokens
     */
    function supportDeferredWithdrawal(address recipientAddress) external override onlyOwner {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(recipientAddress != address(0), InvalidRecipient());
        require(supportTokenDeferredWithdrawalDate == 0, SupportDeferredWithdrawalAlreadyScheduled());

        recipientDeferredWithdrawalSupportToken = recipientAddress;
        supportTokenDeferredWithdrawalDate = block.timestamp + Constants.THIRTY_DAYS;

        emit DeferredWithdrawalScheduled(recipientAddress, contractSupportBalance, supportTokenDeferredWithdrawalDate);
    }

    /**
     * @dev Cancel deferred withdrawal of support tokens
     */
    function stopSupportDeferredWithdrawal() external override {
        require(_msgSender() == owner() || _msgSender() == royaltyWalletAddress, AccessDenied());
        require(supportTokenDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());

        supportTokenDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalSupportToken = owner();
    }

    /**
     * @dev Confirm and execute deferred withdrawal of support tokens
     */
    function confirmSupportDeferredWithdrawal() external override onlyOwner nonReentrant {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(supportTokenDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());
        require(block.timestamp >= supportTokenDeferredWithdrawalDate, WithdrawalDateNotReached());

        _transferSupportTokens(recipientDeferredWithdrawalSupportToken, contractSupportBalance);

        contractSupportBalance = 0;
        supportTokenDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalSupportToken = owner();
        isActive = false;
    }

    /**
     * @dev Assign new owner
     */
    function assignNewOwner(address newOwner) external override onlyReserveOwner {
        require(newOwner != address(0), InvalidNewOwner());

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
    }

    /**
     * @dev Set whether to unwrap WETH to ETH when sending
     */
    function setUnwrapMode(bool needToUnwrap) external onlyOwner {
        require(needToUnwrap != isNeedToUnwrap, SameUnwrapModeAlreadyActive());

        isNeedToUnwrap = needToUnwrap;
        emit UnwrapModeChanged(needToUnwrap);
    }

    /**
     * @dev Change return wallet address
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
        require(_msgSender() == royaltyWalletAddress, OnlyRoyaltyWalletCanChange());
        require(newRoyaltyWalletAddress != address(0), InvalidAddress());
        royaltyWalletAddress = newRoyaltyWalletAddress;
        emit RoyaltyWalletChanged(newRoyaltyWalletAddress);
    }

    /**
     * @dev Change profit percentage distribution
     */
    function changeProfitPercentage(uint256 newRoyaltyProfitPercentage) external override {
        require(_msgSender() == owner() || _msgSender() == royaltyWalletAddress, AccessDenied());
        require(
            newRoyaltyProfitPercentage > 0 && newRoyaltyProfitPercentage <= Constants.PERCENTAGE_DIVISOR,
            InvalidPercentage()
        );

        if (_msgSender() == owner()) {
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
     * @dev Buy tokens with support tokens
     */
    function buyTokens(uint256 amount) external override nonReentrant onlyActiveContract {
        require(amount > 0, InvalidAmount());
        require(!(_msgSender() == owner() || oldContractAddress[_msgSender()]), UseDepositFunctionForOwners());

        IERC20(tokenSupportAddress).safeTransferFrom(_msgSender(), address(this), amount);
        _handleTokenPurchaseCommon(amount);
    }

    /**
     * @dev Buy tokens with ETH
     */
    function buyTokensWithETH() external payable override nonReentrant onlyActiveContract {
        require(!tokenSupport, UseSupportTokenInstead());
        require(msg.value > 0, InvalidETHAmount());
        require(!(_msgSender() == owner() || oldContractAddress[_msgSender()]), UseDepositFunctionForOwners());

        // Wrap received ETH to WETH
        _wrapETH(msg.value);
        _handleTokenPurchaseCommon(msg.value);
    }

    /**
     * @dev Deposit support tokens (for owners and old contracts)
     */
    function deposit(uint256 amount) external override nonReentrant onlyActiveContract onlyOwnerOrOldContract {
        require(amount > 0, InvalidAmount());

        IERC20(tokenSupportAddress).safeTransferFrom(_msgSender(), address(this), amount);
        _handleOwnerDeposit(amount);
    }

    /**
     * @dev Deposit ETH (for owners and old contracts)
     */
    function depositWithETH() external payable override nonReentrant onlyActiveContract onlyOwnerOrOldContract {
        require(!tokenSupport, UseSupportTokenInstead());
        require(msg.value > 0, InvalidETHAmount());

        // Wrap received ETH to WETH
        _wrapETH(msg.value);
        _handleOwnerDeposit(msg.value);
    }

    /**
     * @dev Sell tokens back to contract
     */
    function sellTokens(uint256 amount) external override nonReentrant onlyActiveContract {
        require(amount > 0, InvalidAmount());

        launchToken.safeTransferFrom(_msgSender(), address(this), amount);

        if (_msgSender() == returnWalletAddress) {
            _handleReturnWalletSale(amount);
        } else {
            _handleTokenSale(amount);
        }
    }

    /**
     * @dev Withdraw all tokens after lock period
     */
    function withdrawAllTokens() external override onlyOwner nonReentrant {
        require(block.timestamp >= lockEndTime, LockPeriodNotEnded());

        uint256 availableTokens = contractTokenBalance - totalTokensSold;
        require(availableTokens > 0, NoTokensToWithdraw());

        launchToken.safeTransfer(owner(), availableTokens);

        // Reset state
        currentStep = 0;
        contractTokenBalance = 0;
        totalTokensSold = 0;
        tokensEarned = 0;
        quantityTokensPerLevel = firstLevelTokenQuantity;
        currentPrice = initialPricePerToken;
        remainderOfStep = firstLevelTokenQuantity;
        currentStepEarned = 0;
        remainderOfStepEarned = firstLevelTokenQuantity;
        quantityTokensPerLevelEarned = firstLevelTokenQuantity;
        currentPriceEarned = initialPricePerToken;
    }

    /**
     * @dev Withdraw all support tokens after lock period
     */
    function withdrawAllSupportTokens() external override onlyOwner nonReentrant {
        require(block.timestamp >= lockEndTime, LockPeriodNotEnded());
        require(contractSupportBalance > 0, NoSupportTokensToWithdraw());

        _transferSupportTokens(owner(), contractSupportBalance);
        contractSupportBalance = 0;
    }

    /**
     * @dev Propose contract upgrade by royalty wallet
     */
    function proposeUpgrade(address newImplementation) external {
        require(_msgSender() == royaltyWalletAddress, OnlyRoyaltyCanProposeUpgrade());
        require(newImplementation != address(0), InvalidAddress());
        require(proposedUpgradeImplementation == address(0), UpgradeAlreadyProposed());

        proposedUpgradeImplementation = newImplementation;
        upgradeProposalTime = block.timestamp;
        upgradeConfirmed = false;
        upgradeConfirmationTime = 0;

        emit UpgradeProposed(newImplementation, block.timestamp);
    }

    /**
     * @dev Confirm proposed upgrade by owner (within 30 days of proposal)
     */
    function confirmUpgrade() external onlyOwner {
        require(proposedUpgradeImplementation != address(0), NoUpgradeProposed());
        require(block.timestamp <= upgradeProposalTime + Constants.THIRTY_DAYS, UpgradeProposalExpired());
        require(!upgradeConfirmed, UpgradeAlreadyProposed());

        upgradeConfirmed = true;
        upgradeConfirmationTime = block.timestamp;

        emit UpgradeConfirmed(proposedUpgradeImplementation, block.timestamp);
    }

    /**
     * @dev Cancel upgrade proposal (can be called by royalty wallet or owner)
     */
    function cancelUpgradeProposal() external {
        require(_msgSender() == royaltyWalletAddress || _msgSender() == owner(), AccessDenied());
        require(proposedUpgradeImplementation != address(0), NoUpgradeProposed());

        address cancelledImplementation = proposedUpgradeImplementation;
        proposedUpgradeImplementation = address(0);
        upgradeProposalTime = 0;
        upgradeConfirmed = false;
        upgradeConfirmationTime = 0;

        emit UpgradeCancelled(cancelledImplementation, block.timestamp);
    }
    /**
     * @dev Get profit on request
     */

    function getProfitOnRequest() external override nonReentrant {
        require(profitInTime, ProfitModeNotActive());

        if (_msgSender() == owner()) {
            require(ownerSupportBalance > 0, NoProfitAvailable());
            _transferSupportTokens(owner(), ownerSupportBalance);
            ownerSupportBalance = 0;
        } else {
            require(_msgSender() == royaltyWalletAddress, AccessDenied());
            require(royaltySupportBalance > 0, NoProfitAvailable());
            _transferSupportTokens(royaltyWalletAddress, royaltySupportBalance);
            royaltySupportBalance = 0;
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
        return lockEndTime < Constants.THIRTY_DAYS + block.timestamp;
    }

    function tokenAvailable() external view override returns (uint256) {
        if (totalTokensSold < tokensEarned) {
            return 0;
        }
        return totalTokensSold - tokensEarned;
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
     * @dev Safe transfer ETH - unwraps WETH and sends native ETH
     */
    function _safeTransferETH(address to, uint256 amount) internal {
        if (isNeedToUnwrap) {
            // Unwrap WETH to ETH before sending
            IWETH(wethAddress).withdraw(amount);
            (bool success,) = to.call{value: amount}("");
            require(success, ETHTransferFailed());
        } else {
            // Transfer WETH directly without unwrapping
            IERC20(wethAddress).safeTransfer(to, amount);
        }
    }

    function _handleOwnerDeposit(uint256 value) internal {
        if (offsetTokens > tokensEarned) {
            uint256 deltaSupportBalance = _calculateChangeOffsetSupport(value);
            contractSupportBalance += deltaSupportBalance;

            // Check to prevent arithmetic underflow
            if (value > deltaSupportBalance) {
                uint256 change = value - deltaSupportBalance;
                _transferSupportTokens(_msgSender(), change);
            }
        }
    }

    /**
     * @dev Common logic for handling token purchases with any support currency
     * @param supportAmount Amount of support currency (ETH or support token)
     */
    function _handleTokenPurchaseCommon(uint256 supportAmount) internal {
        if (!_checkTradingAccess()) {
            require(marketMakerAddresses[_msgSender()], TradingNotAllowedOnlyMarketMakers());
        }
        require(contractTokenBalance > totalTokensSold, InsufficientTokenBalance());

        uint256 totalTokens = _calculateTokensToGiveForSupportAmount(supportAmount);
        uint256 creatorProfit = (actualProfit * creatorProfitPercent) / Constants.PERCENTAGE_DIVISOR;
        uint256 royaltyProfit = (actualProfit * royaltyProfitPercent) / Constants.PERCENTAGE_DIVISOR;

        if (!profitInTime) {
            _transferSupportTokens(owner(), creatorProfit);
            _transferSupportTokens(royaltyWalletAddress, royaltyProfit);
        } else {
            ownerSupportBalance += creatorProfit;
            royaltySupportBalance += royaltyProfit;
        }

        // Check to prevent arithmetic underflow
        uint256 netValue = 0;
        if (supportAmount > actualProfit) {
            netValue = supportAmount - actualProfit;
        }
        contractSupportBalance += netValue;
        totalTokensSold += totalTokens;

        launchToken.safeTransfer(_msgSender(), totalTokens);

        emit TokensPurchased(_msgSender(), totalTokens, supportAmount);
    }

    function _handleReturnWalletSale(uint256 amount) internal {
        uint256 supportAmountToPay = 0;

        // Check to prevent arithmetic underflow
        uint256 tokensAvailableForReturnBuyback = 0;
        if (totalTokensSold > tokensEarned) {
            tokensAvailableForReturnBuyback = totalTokensSold - tokensEarned;
        }

        uint256 effectiveAmount = amount < tokensAvailableForReturnBuyback ? amount : tokensAvailableForReturnBuyback;

        if (offsetTokens > tokensEarned) {
            uint256 offsetAmount = offsetTokens - tokensEarned;
            if (effectiveAmount > offsetAmount) {
                _calculateSupportForTokenAmountEarned(offsetAmount);
                uint256 buybackAmount = effectiveAmount - offsetAmount;
                supportAmountToPay = _calculateSupportForTokenAmountEarned(buybackAmount);
            } else {
                _calculateSupportForTokenAmountEarned(effectiveAmount);
                supportAmountToPay = 0;
            }
        } else {
            supportAmountToPay = _calculateSupportForTokenAmountEarned(effectiveAmount);
        }

        tokensEarned += effectiveAmount;
        require(contractSupportBalance >= supportAmountToPay, InsufficientSupportBalance());
        contractSupportBalance -= supportAmountToPay;
        contractTokenBalance += amount;

        if (supportAmountToPay > 0) {
            _transferSupportTokens(owner(), supportAmountToPay);
        }
    }

    function _handleTokenSale(uint256 amount) internal {
        if (!_checkTradingAccess()) {
            require(marketMakerAddresses[_msgSender()], TradingNotAllowedOnlyMarketMakers());
        }

        uint256 maxEarnedOrOffset = offsetTokens > tokensEarned ? offsetTokens : tokensEarned;

        // Check for tokens available for buyback (prevents underflow and ensures > 0)
        require(totalTokensSold > maxEarnedOrOffset, NoTokensAvailableForBuyback());

        uint256 tokensAvailableForBuyback = totalTokensSold - maxEarnedOrOffset;
        require(tokensAvailableForBuyback >= amount, InsufficientTokensForBuyback());
        require(totalTokensSold >= amount, InsufficientSoldTokens());

        uint256 supportAmountToPay = _calculateSupportToPayForTokenAmount(amount);
        require(contractSupportBalance >= supportAmountToPay, InsufficientSupportBalance());

        contractSupportBalance -= supportAmountToPay;
        totalTokensSold -= amount;

        _transferSupportTokens(_msgSender(), supportAmountToPay);

        emit TokensSold(_msgSender(), amount, supportAmountToPay);
    }

    function _checkTradingAccess() internal view returns (bool) {
        return _checkControlDay() || (mainTokenDeferredWithdrawalDate > 0) || (supportTokenDeferredWithdrawalDate > 0);
    }

    function _checkControlDay() internal view returns (bool) {
        return (
            block.timestamp > Constants.THIRTY_DAYS + controlDay
                && block.timestamp < controlPeriod + controlDay + Constants.THIRTY_DAYS
        );
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
            return profitPercentage * 2;
        }
    }

    function _calculateTokensPerLevel(uint256 tokensPerLevel, uint256 currentStepParam)
        internal
        view
        returns (uint256)
    {
        if (currentStepParam > trendChangeStep) {
            return (tokensPerLevel * (Constants.PERCENTAGE_DIVISOR - levelDecreaseMultiplierafterTrend))
                / Constants.PERCENTAGE_DIVISOR;
        } else {
            return (tokensPerLevel * (Constants.PERCENTAGE_DIVISOR + levelIncreaseMultiplier))
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
        contractTokenBalance = amountTokens;
        totalTokensSold = amountTokens;
    }

    function _calculateChangeOffsetSupport(uint256 amountSupport) internal returns (uint256) {
        int256 remainingAddSupport = int256(amountSupport);
        uint256 remainingOffsetTokensLocal = offsetTokens;
        int256 remainingAddTokens = int256(offsetTokens) - int256(tokensEarned);
        uint256 localCurrentStep = offsetStep;
        uint256 remainderOfStepLocal = remainderOffsetTokens;
        uint256 tokensPerLevel = sizeOffsetStep;
        uint256 currentPriceLocal = offsetPrice;

        while (remainingAddSupport > 0 && remainingAddTokens > 0) {
            uint256 tokensAvailableInStep = tokensPerLevel - remainderOfStepLocal;
            uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
            uint256 tonInStep = (uint256(tokensAvailableInStep) * currentPriceLocal) / Constants.PRICE_PRECISION;
            uint256 tonRealInStep =
                (tonInStep * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal)) / Constants.PERCENTAGE_DIVISOR;

            if (remainingAddSupport >= int256(tonRealInStep) && remainingAddTokens >= int256(tokensAvailableInStep)) {
                remainingAddSupport -= int256(tonRealInStep);
                remainingOffsetTokensLocal -= tokensAvailableInStep;
                remainingAddTokens -= int256(tokensAvailableInStep);

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / (Constants.PERCENTAGE_DIVISOR - levelDecreaseMultiplierafterTrend);
                    } else {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / (Constants.PERCENTAGE_DIVISOR + levelIncreaseMultiplier);
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

                uint256 supportToPayForStep = 0;
                uint256 tokensToBuyInThisStep = 0;

                if (remainingAddSupport >= int256(tonRealInStep)) {
                    supportToPayForStep = (uint256(remainingAddTokens) * adjustedPrice) / Constants.PRICE_PRECISION;
                    tokensToBuyInThisStep = uint256(remainingAddTokens);
                } else {
                    supportToPayForStep = uint256(remainingAddSupport);
                    tokensToBuyInThisStep = (uint256(remainingAddSupport) * Constants.PRICE_PRECISION) / adjustedPrice;
                }

                remainderOfStepLocal += tokensToBuyInThisStep;
                remainingAddSupport -= int256(supportToPayForStep);
                remainingOffsetTokensLocal -= tokensToBuyInThisStep;
                remainingAddTokens = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOffsetTokens = remainderOfStepLocal;
        offsetPrice = currentPriceLocal;
        sizeOffsetStep = tokensPerLevel;
        offsetTokens = remainingOffsetTokensLocal;

        return (amountSupport - uint256(remainingAddSupport));
    }

    function _calculateTokensToGiveForSupportAmount(uint256 supportAmount) internal returns (uint256) {
        uint256 tokensToGive = 0;
        int256 remainingSupportAmount = int256(supportAmount);
        uint256 localCurrentStep = currentStep;
        int256 remainderOfStepLocal = int256(remainderOfStep);
        uint256 tokensPerLevel = quantityTokensPerLevel;
        uint256 currentPriceLocal = currentPrice;
        uint256 totalProfit = 0;
        uint256 remainderOfTokens = contractTokenBalance - totalTokensSold;

        while (remainingSupportAmount > 0 && remainderOfTokens >= tokensToGive) {
            int256 tokensAvailableInStep = remainderOfStepLocal;
            int256 tonRequiredForStep =
                (int256(tokensAvailableInStep) * int256(currentPriceLocal)) / int256(Constants.PRICE_PRECISION);

            if (remainingSupportAmount >= tonRequiredForStep) {
                tokensToGive += uint256(tokensAvailableInStep);
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);

                uint256 profitInStep =
                    (uint256(tonRequiredForStep) * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingSupportAmount -= tonRequiredForStep;
                localCurrentStep += 1;

                tokensPerLevel = _calculateTokensPerLevel(tokensPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(tokensPerLevel);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 tokensToBuyInThisStep =
                    (uint256(remainingSupportAmount) * Constants.PRICE_PRECISION) / currentPriceLocal;
                tokensToGive += tokensToBuyInThisStep;
                uint256 tonSpentInThisStep = uint256(remainingSupportAmount);

                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 profitInStep = (tonSpentInThisStep * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingSupportAmount = 0;
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

        if (remainderOfStepLocal < 0) {
            remainderOfStep = 0;
        } else {
            remainderOfStep = uint256(remainderOfStepLocal);
        }

        return tokensToGive;
    }

    function _calculateSupportToPayForTokenAmount(uint256 tokenAmount) internal returns (uint256) {
        uint256 supportAmountToPay = 0;
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
                uint256 supportToPayForStep =
                    (uint256(tokensAvailableInStep) * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                remainingTokenAmount -= int256(tokensAvailableInStep);

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / (Constants.PERCENTAGE_DIVISOR - levelDecreaseMultiplierafterTrend);
                    } else {
                        tokensPerLevel = (tokensPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / (Constants.PERCENTAGE_DIVISOR + levelIncreaseMultiplier);
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
                uint256 supportToPayForStep =
                    (uint256(remainingTokenAmount) * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                remainderOfStepLocal += int256(remainingTokenAmount);
                remainingTokenAmount = 0;
            }
        }

        currentStep = localCurrentStep;
        quantityTokensPerLevel = tokensPerLevel;
        currentPrice = currentPriceLocal;

        if (remainderOfStepLocal < 0) {
            remainderOfStep = 0;
        } else {
            remainderOfStep = uint256(remainderOfStepLocal);
        }

        return supportAmountToPay;
    }

    function _calculateSupportForTokenAmountEarned(uint256 tokenAmount) internal returns (uint256) {
        uint256 supportAmountToPay = 0;
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
                uint256 supportToPayForStep =
                    (uint256(tokensAvailableInStep) * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

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
                uint256 supportToPayForStep =
                    (uint256(remainingTokenAmount) * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                remainderOfStepLocal -= remainingTokenAmount;
                remainingTokenAmount = 0;
            }
        }

        currentStepEarned = localCurrentStep;
        quantityTokensPerLevelEarned = tokensPerLevel;
        currentPriceEarned = currentPriceLocal;

        if (remainderOfStepLocal < 0) {
            remainderOfStepEarned = 0;
        } else {
            remainderOfStepEarned = uint256(remainderOfStepLocal);
        }

        return supportAmountToPay;
    }

    /**
     * @dev Wrap received ETH to WETH
     */
    function _wrapETH(uint256 amount) internal {
        IWETH(wethAddress).deposit{value: amount}();
    }

    /**
     * @dev General transfer function for support tokens (ETH or ERC20)
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _transferSupportTokens(address to, uint256 amount) internal {
        if (amount == 0) return;

        if (!tokenSupport) {
            // Transfer ETH (unwrap WETH first)
            _safeTransferETH(to, amount);
        } else {
            // Transfer support tokens
            IERC20(tokenSupportAddress).safeTransfer(to, amount);
        }
    }

    /**
     * @dev Authorize upgrade - only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(proposedUpgradeImplementation != address(0), NoUpgradeProposed());
        require(upgradeConfirmed, UpgradeNotConfirmed());
        require(newImplementation == proposedUpgradeImplementation, InvalidAddress());
        require(
            block.timestamp >= upgradeConfirmationTime + Constants.THIRTY_DAYS, UpgradeConfirmationPeriodNotPassed()
        );

        // Reset upgrade state after successful upgrade
        proposedUpgradeImplementation = address(0);
        upgradeProposalTime = 0;
        upgradeConfirmed = false;
        upgradeConfirmationTime = 0;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
