// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM
pragma solidity ^0.8.19;

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
    error MainJettonDeferredWithdrawalAlreadyScheduled();
    error NoDeferredWithdrawalScheduled();
    error WithdrawalDateNotReached();
    error InsufficientJettonBalance();
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
    error InsufficientTokenBalance();
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
        uint256 firstLevelJettonQuantity;
        uint256 priceIncrementMultiplier;
        uint256 levelIncreaseMultiplier;
        uint256 trendChangeStep;
        uint256 levelDecreaseMultiplierafterTrend;
        uint256 profitPercentage;
        uint256 offsetJettons;
        uint256 controlPeriod;
        address jettonSupportAddress;
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
    uint256 public firstLevelJettonQuantity;
    uint256 public override currentPrice;
    uint256 public quantityJettonsPerLevel;
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
    uint256 public override totalJettonsSold;
    uint256 public override contractSupportBalance; // WETH balance for backing
    uint256 public contractJettonBalance; // Main token balance
    uint256 public jettonsEarned;
    uint256 public actualProfit;

    // Return tracking variables
    uint256 public currentStepEarned;
    uint256 public remainderOfStepEarned;
    uint256 public quantityJettonsPerLevelEarned;
    uint256 public currentPriceEarned;

    // Offset variables
    uint256 public offsetJettons;
    uint256 public offsetStep;
    uint256 public offsetPrice;
    uint256 public remainderOffsetJettons;
    uint256 public sizeOffsetStep;

    // Support token variables
    bool public override jettonSupport; // If true, uses support token instead of WETH
    address public jettonSupportAddress;
    address public additionalJettonAddress;

    // Market makers
    mapping(address => bool) public marketMakerAddresses;

    // Profit tracking
    uint256 public ownerSupportBalance; // Owner's profit balance (universal for both ETH and support tokens)
    uint256 public royaltySupportBalance; // Royalty profit balance (universal for both ETH and support tokens)
    bool public override profitInTime; // true = on request, false = immediate

    // Deferred withdrawal
    bool public override canWithdrawal;
    uint256 public mainJettonDeferredWithdrawalDate;
    uint256 public mainJettonDeferredWithdrawalAmount;
    address public recipientDeferredWithdrawalMainJetton;
    uint256 public supportJettonDeferredWithdrawalDate;
    address public recipientDeferredWithdrawalSupportJetton;

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
        firstLevelJettonQuantity = params.firstLevelJettonQuantity;
        priceIncrementMultiplier = params.priceIncrementMultiplier;
        levelIncreaseMultiplier = params.levelIncreaseMultiplier;
        trendChangeStep = params.trendChangeStep;
        levelDecreaseMultiplierafterTrend = params.levelDecreaseMultiplierafterTrend;
        profitPercentage = params.profitPercentage;
        offsetJettons = params.offsetJettons;
        controlPeriod = _getPeriod(params.controlPeriod);
        jettonSupport = params.jettonSupportAddress == wethAddress;
        jettonSupportAddress = params.jettonSupportAddress;
        royaltyProfitPercent = params.royaltyProfitPercent;
        creatorProfitPercent = Constants.PERCENTAGE_DIVISOR - params.royaltyProfitPercent;

        // Initialize state variables
        currentStep = 0;
        remainderOfStep = params.firstLevelJettonQuantity;
        quantityJettonsPerLevel = params.firstLevelJettonQuantity;
        currentPrice = params.initialPricePerToken;
        controlDay = block.timestamp + Constants.THIRTY_DAYS;
        reserveOwner = _msgSender();

        // Initialize market makers
        marketMakerAddresses[params.marketMakerAddress] = true;

        // Initialize offset variables
        offsetStep = 0;
        offsetPrice = params.initialPricePerToken;
        remainderOffsetJettons = params.firstLevelJettonQuantity;
        sizeOffsetStep = params.firstLevelJettonQuantity;

        // Initialize earned tracking
        currentStepEarned = 0;
        remainderOfStepEarned = params.firstLevelJettonQuantity;
        quantityJettonsPerLevelEarned = params.firstLevelJettonQuantity;
        currentPriceEarned = params.initialPricePerToken;

        recipientDeferredWithdrawalMainJetton = _msgSender();
        recipientDeferredWithdrawalSupportJetton = _msgSender();

        profitInTime = true;
        canWithdrawal = true;
        isNeedToUnwrap = true; // Default to true - unwrap WETH to ETH when sending

        if (params.offsetJettons > 0) {
            _calculateOffset(params.offsetJettons);
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
            require(
                lockEndTime - block.timestamp > Constants.THIRTY_DAYS,
                CannotActivateWithdrawalTooCloseToLockEnd()
            );
            canWithdrawal = true;
        }
    }

    /**
     * @dev Schedule deferred withdrawal of main jetton
     */
    function jettonDeferredWithdrawal(address recipientAddress, uint256 amount) external override onlyOwner {
        require(recipientAddress != address(0) && amount > 0, InvalidRecipientOrAmount());
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(mainJettonDeferredWithdrawalAmount == 0, MainJettonDeferredWithdrawalAlreadyScheduled());

        recipientDeferredWithdrawalMainJetton = recipientAddress;
        mainJettonDeferredWithdrawalDate = block.timestamp + Constants.THIRTY_DAYS;
        mainJettonDeferredWithdrawalAmount = amount;

        emit DeferredWithdrawalScheduled(recipientAddress, amount, mainJettonDeferredWithdrawalDate);
    }

    /**
     * @dev Cancel deferred withdrawal of main jetton
     */
    function stopJettonDeferredWithdrawal() external override {
        require(_msgSender() == owner() || _msgSender() == royaltyWalletAddress, AccessDenied());
        require(mainJettonDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());

        mainJettonDeferredWithdrawalDate = 0;
        mainJettonDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalMainJetton = owner();
    }

    /**
     * @dev Confirm and execute deferred withdrawal of main jetton
     */
    function confirmJettonDeferredWithdrawal() external override onlyOwner nonReentrant {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(mainJettonDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());
        require(block.timestamp >= mainJettonDeferredWithdrawalDate, WithdrawalDateNotReached());
        require(contractJettonBalance > totalJettonsSold, InsufficientJettonBalance());
        require(contractJettonBalance - totalJettonsSold >= mainJettonDeferredWithdrawalAmount, InsufficientAmount());

        launchToken.safeTransfer(
            recipientDeferredWithdrawalMainJetton, mainJettonDeferredWithdrawalAmount
        );

        contractJettonBalance -= mainJettonDeferredWithdrawalAmount;
        mainJettonDeferredWithdrawalDate = 0;
        mainJettonDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalMainJetton = owner();
    }

    /**
     * @dev Schedule deferred withdrawal of support tokens
     */
    function supportDeferredWithdrawal(address recipientAddress) external override onlyOwner {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(recipientAddress != address(0), InvalidRecipient());
        require(supportJettonDeferredWithdrawalDate == 0, SupportDeferredWithdrawalAlreadyScheduled());

        recipientDeferredWithdrawalSupportJetton = recipientAddress;
        supportJettonDeferredWithdrawalDate = block.timestamp + Constants.THIRTY_DAYS;

        emit DeferredWithdrawalScheduled(recipientAddress, contractSupportBalance, supportJettonDeferredWithdrawalDate);
    }

    /**
     * @dev Cancel deferred withdrawal of support tokens
     */
    function stopSupportDeferredWithdrawal() external override {
        require(_msgSender() == owner() || _msgSender() == royaltyWalletAddress, AccessDenied());
        require(supportJettonDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());

        supportJettonDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalSupportJetton = owner();
    }

    /**
     * @dev Confirm and execute deferred withdrawal of support tokens
     */
    function confirmSupportDeferredWithdrawal() external override onlyOwner nonReentrant {
        require(canWithdrawal, DeferredWithdrawalBlocked());
        require(supportJettonDeferredWithdrawalDate != 0, NoDeferredWithdrawalScheduled());
        require(block.timestamp >= supportJettonDeferredWithdrawalDate, WithdrawalDateNotReached());

        _transferSupportTokens(recipientDeferredWithdrawalSupportJetton, contractSupportBalance);

        contractSupportBalance = 0;
        supportJettonDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalSupportJetton = owner();
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

        IERC20(jettonSupportAddress).safeTransferFrom(_msgSender(), address(this), amount);
        _handleTokenPurchaseCommon(amount);
    }

    /**
     * @dev Buy tokens with ETH
     */
    function buyTokensWithETH() external payable override nonReentrant onlyActiveContract {
        require(!jettonSupport, UseSupportTokenInstead());
        require(msg.value > 0, InvalidETHAmount());
        require(!(_msgSender() == owner() || oldContractAddress[_msgSender()]), UseDepositFunctionForOwners());

        // Wrap received ETH to WETH
        _wrapETH(msg.value);
        _handleTokenPurchaseCommon(msg.value);
    }

    /**
     * @dev Deposit support tokens (for owners and old contracts)
     */
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        onlyActiveContract
        onlyOwnerOrOldContract
    {
        require(amount > 0, InvalidAmount());

        IERC20(jettonSupportAddress).safeTransferFrom(_msgSender(), address(this), amount);
        _handleOwnerDeposit(amount);
    }

    /**
     * @dev Deposit ETH (for owners and old contracts)
     */
    function depositWithETH()
        external
        payable
        override
        nonReentrant
        onlyActiveContract
        onlyOwnerOrOldContract
    {
        require(!jettonSupport, UseSupportTokenInstead());
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

        uint256 availableTokens = contractJettonBalance - totalJettonsSold;
        require(availableTokens > 0, NoTokensToWithdraw());

        launchToken.safeTransfer(owner(), availableTokens);

        // Reset state
        currentStep = 0;
        contractJettonBalance = 0;
        totalJettonsSold = 0;
        jettonsEarned = 0;
        quantityJettonsPerLevel = firstLevelJettonQuantity;
        currentPrice = initialPricePerToken;
        remainderOfStep = firstLevelJettonQuantity;
        currentStepEarned = 0;
        remainderOfStepEarned = firstLevelJettonQuantity;
        quantityJettonsPerLevelEarned = firstLevelJettonQuantity;
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

    function jettonAvailable() external view override returns (uint256) {
        if (totalJettonsSold < jettonsEarned) {
            return 0;
        }
        return totalJettonsSold - jettonsEarned;
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
        if (offsetJettons > jettonsEarned) {
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
        require(contractJettonBalance > totalJettonsSold, InsufficientTokenBalance());

        uint256 totalTokens = _calculateJettonsToGiveForSupportAmount(supportAmount);
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
        totalJettonsSold += totalTokens;

        launchToken.safeTransfer(_msgSender(), totalTokens);

        emit TokensPurchased(_msgSender(), totalTokens, supportAmount);
    }

    function _handleReturnWalletSale(uint256 amount) internal {
        uint256 supportAmountToPay = 0;
        
        // Check to prevent arithmetic underflow
        uint256 tokensAvailableForReturnBuyback = 0;
        if (totalJettonsSold > jettonsEarned) {
            tokensAvailableForReturnBuyback = totalJettonsSold - jettonsEarned;
        }
        
        uint256 effectiveAmount = amount < tokensAvailableForReturnBuyback ? amount : tokensAvailableForReturnBuyback;

        if (offsetJettons > jettonsEarned) {
            uint256 offsetAmount = offsetJettons - jettonsEarned;
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

        jettonsEarned += effectiveAmount;
        require(contractSupportBalance >= supportAmountToPay, InsufficientSupportBalance());
        contractSupportBalance -= supportAmountToPay;
        contractJettonBalance += amount;

        if (supportAmountToPay > 0) {
            _transferSupportTokens(owner(), supportAmountToPay);
        }
    }

    function _handleTokenSale(uint256 amount) internal {
        if (!_checkTradingAccess()) {
            require(marketMakerAddresses[_msgSender()], TradingNotAllowedOnlyMarketMakers());
        }

        uint256 maxEarnedOrOffset = offsetJettons > jettonsEarned ? offsetJettons : jettonsEarned;
        
        // Check for tokens available for buyback (prevents underflow and ensures > 0)
        require(totalJettonsSold > maxEarnedOrOffset, NoTokensAvailableForBuyback());
        
        uint256 tokensAvailableForBuyback = totalJettonsSold - maxEarnedOrOffset;
        require(tokensAvailableForBuyback >= amount, InsufficientTokensForBuyback());
        require(totalJettonsSold >= amount, InsufficientSoldTokens());

        uint256 supportAmountToPay = _calculateSupportToPayForTokenAmount(amount);
        require(contractSupportBalance >= supportAmountToPay, InsufficientSupportBalance());

        contractSupportBalance -= supportAmountToPay;
        totalJettonsSold -= amount;

        _transferSupportTokens(_msgSender(), supportAmountToPay);

        emit TokensSold(_msgSender(), amount, supportAmountToPay);
    }

    function _checkTradingAccess() internal view returns (bool) {
        return _checkControlDay() || (mainJettonDeferredWithdrawalDate > 0) || (supportJettonDeferredWithdrawalDate > 0);
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

    function _calculateJettonsPerLevel(uint256 jettonsPerLevel, uint256 currentStepParam)
        internal
        view
        returns (uint256)
    {
        if (currentStepParam > trendChangeStep) {
            return (jettonsPerLevel * (Constants.PERCENTAGE_DIVISOR - levelDecreaseMultiplierafterTrend))
                / Constants.PERCENTAGE_DIVISOR;
        } else {
            return (jettonsPerLevel * (Constants.PERCENTAGE_DIVISOR + levelIncreaseMultiplier))
                / Constants.PERCENTAGE_DIVISOR;
        }
    }

    // Full implementation of calculation functions based on Tact contract
    function _calculateOffset(uint256 amountJettons) internal {
        int256 remainingOffsetJettons = int256(amountJettons);
        uint256 localCurrentStep = offsetStep;
        int256 remainderOfStepLocal = int256(remainderOffsetJettons);
        uint256 jettonsPerLevel = sizeOffsetStep;
        uint256 currentPriceLocal = currentPrice;

        while (remainingOffsetJettons > 0) {
            int256 tokensAvailableInStep = remainderOfStepLocal;

            if (remainingOffsetJettons >= tokensAvailableInStep) {
                remainingOffsetJettons -= int256(tokensAvailableInStep);
                localCurrentStep += 1;

                jettonsPerLevel = _calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(jettonsPerLevel);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                remainderOfStepLocal -= int256(remainingOffsetJettons);
                remainingOffsetJettons = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOffsetJettons = uint256(remainderOfStepLocal);
        sizeOffsetStep = jettonsPerLevel;
        offsetPrice = currentPriceLocal;

        currentStep = localCurrentStep;
        quantityJettonsPerLevel = jettonsPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = uint256(remainderOfStepLocal);
        contractJettonBalance = amountJettons;
        totalJettonsSold = amountJettons;
    }

    function _calculateChangeOffsetSupport(uint256 amountSupport) internal returns (uint256) {
        int256 remainingAddSupport = int256(amountSupport);
        uint256 remainingOffsetJettonsLocal = offsetJettons;
        int256 remainingAddJettons = int256(offsetJettons) - int256(jettonsEarned);
        uint256 localCurrentStep = offsetStep;
        uint256 remainderOfStepLocal = remainderOffsetJettons;
        uint256 jettonsPerLevel = sizeOffsetStep;
        uint256 currentPriceLocal = offsetPrice;

        while (remainingAddSupport > 0 && remainingAddJettons > 0) {
            uint256 tokensAvailableInStep = jettonsPerLevel - remainderOfStepLocal;
            uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
            uint256 tonInStep = (uint256(tokensAvailableInStep) * currentPriceLocal) / Constants.PRICE_PRECISION;
            uint256 tonRealInStep =
                (tonInStep * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal)) / Constants.PERCENTAGE_DIVISOR;

            if (remainingAddSupport >= int256(tonRealInStep) && remainingAddJettons >= int256(tokensAvailableInStep)) {
                remainingAddSupport -= int256(tonRealInStep);
                remainingOffsetJettonsLocal -= tokensAvailableInStep;
                remainingAddJettons -= int256(tokensAvailableInStep);

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        jettonsPerLevel = (jettonsPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / (Constants.PERCENTAGE_DIVISOR - levelDecreaseMultiplierafterTrend);
                    } else {
                        jettonsPerLevel = (jettonsPerLevel * Constants.PERCENTAGE_DIVISOR)
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
                    remainderOfStepLocal = jettonsPerLevel;
                    remainingAddJettons = 0;
                }
            } else {
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;

                uint256 supportToPayForStep = 0;
                uint256 tokensToBuyInThisStep = 0;

                if (remainingAddSupport >= int256(tonRealInStep)) {
                    supportToPayForStep = (uint256(remainingAddJettons) * adjustedPrice) / Constants.PRICE_PRECISION;
                    tokensToBuyInThisStep = uint256(remainingAddJettons);
                } else {
                    supportToPayForStep = uint256(remainingAddSupport);
                    tokensToBuyInThisStep = (uint256(remainingAddSupport) * Constants.PRICE_PRECISION) / adjustedPrice;
                }

                remainderOfStepLocal += tokensToBuyInThisStep;
                remainingAddSupport -= int256(supportToPayForStep);
                remainingOffsetJettonsLocal -= tokensToBuyInThisStep;
                remainingAddJettons = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOffsetJettons = remainderOfStepLocal;
        offsetPrice = currentPriceLocal;
        sizeOffsetStep = jettonsPerLevel;
        offsetJettons = remainingOffsetJettonsLocal;

        return (amountSupport - uint256(remainingAddSupport));
    }

    function _calculateJettonsToGiveForSupportAmount(uint256 supportAmount) internal returns (uint256) {
        uint256 jettonsToGive = 0;
        int256 remainingSupportAmount = int256(supportAmount);
        uint256 localCurrentStep = currentStep;
        int256 remainderOfStepLocal = int256(remainderOfStep);
        uint256 jettonsPerLevel = quantityJettonsPerLevel;
        uint256 currentPriceLocal = currentPrice;
        uint256 totalProfit = 0;
        uint256 remainderOfJettons = contractJettonBalance - totalJettonsSold;

        while (remainingSupportAmount > 0 && remainderOfJettons >= jettonsToGive) {
            int256 tokensAvailableInStep = remainderOfStepLocal;
            int256 tonRequiredForStep = (int256(tokensAvailableInStep) * int256(currentPriceLocal)) / int256(Constants.PRICE_PRECISION);

            if (remainingSupportAmount >= tonRequiredForStep) {
                jettonsToGive += uint256(tokensAvailableInStep);
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);

                uint256 profitInStep = (uint256(tonRequiredForStep) * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingSupportAmount -= tonRequiredForStep;
                localCurrentStep += 1;

                jettonsPerLevel = _calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(jettonsPerLevel);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 tokensToBuyInThisStep = (uint256(remainingSupportAmount) * Constants.PRICE_PRECISION) / currentPriceLocal;
                jettonsToGive += tokensToBuyInThisStep;
                uint256 tonSpentInThisStep = uint256(remainingSupportAmount);

                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 profitInStep = (tonSpentInThisStep * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingSupportAmount = 0;
                remainderOfStepLocal -= int256(tokensToBuyInThisStep);
            }
        }

        if (remainderOfJettons < jettonsToGive) {
            jettonsToGive = remainderOfJettons;
        }

        currentStep = localCurrentStep;
        quantityJettonsPerLevel = jettonsPerLevel;
        currentPrice = currentPriceLocal;
        actualProfit = totalProfit;

        if (remainderOfStepLocal < 0) {
            remainderOfStep = 0;
        } else {
            remainderOfStep = uint256(remainderOfStepLocal);
        }

        return jettonsToGive;
    }

    function _calculateSupportToPayForTokenAmount(uint256 tokenAmount) internal returns (uint256) {
        uint256 supportAmountToPay = 0;
        int256 remainingJettonAmount = int256(tokenAmount);
        uint256 localCurrentStep = currentStep;
        int256 remainderOfStepLocal = int256(remainderOfStep);
        uint256 jettonsPerLevel = quantityJettonsPerLevel;
        uint256 currentPriceLocal = currentPrice;

        while (remainingJettonAmount > 0) {
            int256 tokensAvailableInStep = int256(jettonsPerLevel) - remainderOfStepLocal;

            if (remainingJettonAmount >= int256(tokensAvailableInStep)) {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 supportToPayForStep = (uint256(tokensAvailableInStep) * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                remainingJettonAmount -= int256(tokensAvailableInStep);

                if (localCurrentStep > currentStepEarned) {
                    if (localCurrentStep > trendChangeStep) {
                        jettonsPerLevel = (jettonsPerLevel * Constants.PERCENTAGE_DIVISOR)
                            / (Constants.PERCENTAGE_DIVISOR - levelDecreaseMultiplierafterTrend);
                    } else {
                        jettonsPerLevel = (jettonsPerLevel * Constants.PERCENTAGE_DIVISOR)
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
                    remainderOfStepLocal = int256(jettonsPerLevel);
                    remainingJettonAmount = 0;
                }
            } else {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 supportToPayForStep = (uint256(remainingJettonAmount) * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                remainderOfStepLocal += int256(remainingJettonAmount);
                remainingJettonAmount = 0;
            }
        }

        currentStep = localCurrentStep;
        quantityJettonsPerLevel = jettonsPerLevel;
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
        int256 remainingJettonAmount = int256(tokenAmount);
        uint256 localCurrentStep = currentStepEarned;
        int256 remainderOfStepLocal = int256(remainderOfStepEarned);
        uint256 jettonsPerLevel = quantityJettonsPerLevelEarned;
        uint256 currentPriceLocal = currentPriceEarned;

        while (remainingJettonAmount > 0 && localCurrentStep <= currentStep) {
            int256 tokensAvailableInStep = remainderOfStepLocal;

            if (remainingJettonAmount >= int256(tokensAvailableInStep)) {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 supportToPayForStep = (uint256(tokensAvailableInStep) * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                localCurrentStep += 1;
                jettonsPerLevel = _calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStepLocal = int256(jettonsPerLevel);
                remainingJettonAmount -= int256(tokensAvailableInStep);
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 supportToPayForStep = (uint256(remainingJettonAmount) * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                remainderOfStepLocal -= remainingJettonAmount;
                remainingJettonAmount = 0;
            }
        }

        currentStepEarned = localCurrentStep;
        quantityJettonsPerLevelEarned = jettonsPerLevel;
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

        if (!jettonSupport) {
            // Transfer ETH (unwrap WETH first)
            _safeTransferETH(to, amount);
        } else {
            // Transfer support tokens
            IERC20(jettonSupportAddress).safeTransfer(to, amount);
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
            block.timestamp >= upgradeConfirmationTime + Constants.THIRTY_DAYS,
            UpgradeConfirmationPeriodNotPassed()
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
