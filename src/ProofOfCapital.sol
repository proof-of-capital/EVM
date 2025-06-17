// SPDX-License-Identifier: MIT
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
        bool jettonSupport;
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

    uint8 public callJettonsID;
    bool public isNeedToUnwrap; // Controls whether to unwrap WETH to ETH when sending

    modifier onlyOwnerOrOldContract() {
        require(_msgSender() == owner() || oldContractAddress[_msgSender()], "Access denied");
        _;
    }

    modifier onlyMarketMaker() {
        require(marketMakerAddresses[_msgSender()], "Not a market maker");
        _;
    }

    modifier onlyActiveContract() {
        require(isActive, "Contract is not active");
        _;
    }

    modifier onlyReserveOwner() {
        require(_msgSender() == reserveOwner, "Only reserve owner can call this function");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(InitParams calldata params) public initializer {
        require(params.initialPricePerToken > 0, "Initial price must be positive");
        require(params.levelDecreaseMultiplierafterTrend < Constants.PERCENTAGE_DIVISOR, "Multiplier too high");
        require(params.levelIncreaseMultiplier > 0, "Multiplier too low");
        require(params.priceIncrementMultiplier > 0, "Price increment too low");
        require(
            params.royaltyProfitPercent > 1 && params.royaltyProfitPercent <= Constants.MAX_ROYALTY_PERCENT,
            "Invalid royalty profit percentage"
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
        jettonSupport = params.jettonSupport;
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
        callJettonsID = 1;
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
     * @dev Authorize upgrade - only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Get implementation version
     */
    function getVersion() external pure returns (string memory) {
        return "1.0.0";
    }

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
            require(success, "ETH transfer failed");
        } else {
            // Transfer WETH directly without unwrapping
            IERC20(wethAddress).safeTransfer(to, amount);
        }
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
     * @dev Extend lock period
     */
    function extendLock(uint256 additionalTime) external override onlyOwner {
        require((lockEndTime + additionalTime) - block.timestamp < Constants.TWO_YEARS, "Lock cannot exceed two years");
        require(
            additionalTime == Constants.HALF_YEAR || additionalTime == Constants.TEN_MINUTES
                || additionalTime == Constants.THREE_MONTHS,
            "Invalid time period"
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
                "Cannot activate withdrawal too close to lock end"
            );
            canWithdrawal = true;
        }
    }

    /**
     * @dev Schedule deferred withdrawal of main jetton
     */
    function jettonDeferredWithdrawal(address recipientAddress, uint256 amount) external override onlyOwner {
        require(recipientAddress != address(0) && amount > 0, "Invalid recipient or amount");
        require(canWithdrawal, "Deferred withdrawal is blocked");
        require(mainJettonDeferredWithdrawalAmount == 0, "Main jetton deferred withdrawal already scheduled");

        recipientDeferredWithdrawalMainJetton = recipientAddress;
        mainJettonDeferredWithdrawalDate = block.timestamp + Constants.THIRTY_DAYS;
        mainJettonDeferredWithdrawalAmount = amount;

        emit DeferredWithdrawalScheduled(recipientAddress, amount, mainJettonDeferredWithdrawalDate);
    }

    /**
     * @dev Cancel deferred withdrawal of main jetton
     */
    function stopJettonDeferredWithdrawal() external override {
        require(_msgSender() == owner() || _msgSender() == royaltyWalletAddress, "Access denied");
        require(mainJettonDeferredWithdrawalDate != 0, "No deferred withdrawal scheduled");

        mainJettonDeferredWithdrawalDate = 0;
        mainJettonDeferredWithdrawalAmount = 0;
        recipientDeferredWithdrawalMainJetton = owner();
    }

    /**
     * @dev Confirm and execute deferred withdrawal of main jetton
     */
    function confirmJettonDeferredWithdrawal() external override onlyOwner nonReentrant {
        require(canWithdrawal, "Deferred withdrawal is blocked");
        require(mainJettonDeferredWithdrawalDate != 0, "No deferred withdrawal scheduled");
        require(block.timestamp >= mainJettonDeferredWithdrawalDate, "Withdrawal date not reached");
        require(contractJettonBalance > totalJettonsSold, "Insufficient jetton balance");
        require(contractJettonBalance - totalJettonsSold >= mainJettonDeferredWithdrawalAmount, "Insufficient amount");

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
        require(canWithdrawal, "Deferred withdrawal is blocked");
        require(recipientAddress != address(0), "Invalid recipient");
        require(supportJettonDeferredWithdrawalDate == 0, "Support deferred withdrawal already scheduled");

        recipientDeferredWithdrawalSupportJetton = recipientAddress;
        supportJettonDeferredWithdrawalDate = block.timestamp + Constants.THIRTY_DAYS;

        emit DeferredWithdrawalScheduled(recipientAddress, contractSupportBalance, supportJettonDeferredWithdrawalDate);
    }

    /**
     * @dev Cancel deferred withdrawal of support tokens
     */
    function stopSupportDeferredWithdrawal() external override {
        require(_msgSender() == owner() || _msgSender() == royaltyWalletAddress, "Access denied");
        require(supportJettonDeferredWithdrawalDate != 0, "No deferred withdrawal scheduled");

        supportJettonDeferredWithdrawalDate = 0;
        recipientDeferredWithdrawalSupportJetton = owner();
    }

    /**
     * @dev Confirm and execute deferred withdrawal of support tokens
     */
    function confirmSupportDeferredWithdrawal() external override onlyOwner nonReentrant {
        require(canWithdrawal, "Deferred withdrawal is blocked");
        require(supportJettonDeferredWithdrawalDate != 0, "No deferred withdrawal scheduled");
        require(block.timestamp >= supportJettonDeferredWithdrawalDate, "Withdrawal date not reached");

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
        require(newOwner != address(0), "Invalid new owner");

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
        require(newReserveOwner != address(0), "Invalid reserve owner");
        _transferReserveOwner(newReserveOwner);
    }

    /**
     * @dev Switch profit withdrawal mode
     */
    function switchProfitMode(bool flag) external override onlyOwner {
        require(flag != profitInTime, "Same mode already active");

        profitInTime = flag;
        emit ProfitModeChanged(flag);
    }

    /**
     * @dev Set whether to unwrap WETH to ETH when sending
     */
    function setUnwrapMode(bool needToUnwrap) external onlyOwner {
        require(needToUnwrap != isNeedToUnwrap, "Same unwrap mode already active");

        isNeedToUnwrap = needToUnwrap;
        emit UnwrapModeChanged(needToUnwrap);
    }

    /**
     * @dev Change return wallet address
     */
    function changeReturnWallet(address newReturnWalletAddress) external override onlyOwner {
        require(newReturnWalletAddress != address(0), "Invalid address");
        returnWalletAddress = newReturnWalletAddress;
        emit ReturnWalletChanged(newReturnWalletAddress);
    }

    /**
     * @dev Change royalty wallet address
     */
    function changeRoyaltyWallet(address newRoyaltyWalletAddress) external override {
        require(_msgSender() == royaltyWalletAddress, "Only royalty wallet can change");
        require(newRoyaltyWalletAddress != address(0), "Invalid address");
        royaltyWalletAddress = newRoyaltyWalletAddress;
        emit RoyaltyWalletChanged(newRoyaltyWalletAddress);
    }

    /**
     * @dev Change profit percentage distribution
     */
    function changeProfitPercentage(uint256 newRoyaltyProfitPercentage) external override {
        require(_msgSender() == owner() || _msgSender() == royaltyWalletAddress, "Access denied");
        require(
            newRoyaltyProfitPercentage > 0 && newRoyaltyProfitPercentage <= Constants.PERCENTAGE_DIVISOR,
            "Invalid percentage"
        );

        if (_msgSender() == owner()) {
            require(newRoyaltyProfitPercentage > royaltyProfitPercent, "Cannot decrease royalty");
        } else {
            require(newRoyaltyProfitPercentage < royaltyProfitPercent, "Cannot increase royalty");
        }

        royaltyProfitPercent = newRoyaltyProfitPercentage;
        creatorProfitPercent = Constants.PERCENTAGE_DIVISOR - newRoyaltyProfitPercentage;
        emit ProfitPercentageChanged(newRoyaltyProfitPercentage);
    }

    /**
     * @dev Set market maker status for an address
     */
    function setMarketMaker(address marketMakerAddress, bool isMarketMaker) external override onlyOwner {
        require(marketMakerAddress != address(0), "Invalid address");

        marketMakerAddresses[marketMakerAddress] = isMarketMaker;
        emit MarketMakerStatusChanged(marketMakerAddress, isMarketMaker);
    }

    /**
     * @dev Set old contract address for migration
     */
    function setOldContractAddress(address oldContract) external override onlyOwner {
        require(oldContract != address(0), "Invalid address");
        require(oldContract != address(this), "Cannot be self");
        oldContractAddress[oldContract] = true;
    }

    /**
     * @dev Buy tokens with support tokens
     */
    function buyTokens(uint256 amount) external override nonReentrant onlyActiveContract onlyInitializing {
        require(jettonSupport, "Support token not enabled");
        require(amount > 0, "Invalid amount");
        require(!(_msgSender() == owner() || oldContractAddress[_msgSender()]), "Use deposit function for owners");

        IERC20(jettonSupportAddress).safeTransferFrom(_msgSender(), address(this), amount);
        _handleTokenPurchaseCommon(amount);
    }

    /**
     * @dev Buy tokens with ETH
     */
    function buyTokensWithETH() external payable override nonReentrant onlyActiveContract onlyInitializing {
        require(!jettonSupport, "Use support token instead");
        require(msg.value > 0, "Invalid ETH amount");
        require(!(_msgSender() == owner() || oldContractAddress[_msgSender()]), "Use deposit function for owners");

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
        onlyInitializing
    {
        require(jettonSupport, "Support token not enabled");
        require(amount > 0, "Invalid amount");

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
        onlyInitializing
    {
        require(!jettonSupport, "Use support token instead");
        require(msg.value > 0, "Invalid ETH amount");

        // Wrap received ETH to WETH
        _wrapETH(msg.value);
        _handleOwnerDeposit(msg.value);
    }

    /**
     * @dev Sell tokens back to contract
     */
    function sellTokens(uint256 amount) external override nonReentrant onlyActiveContract onlyInitializing {
        require(amount > 0, "Invalid amount");

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
        require(block.timestamp >= lockEndTime, "Lock period not ended");

        uint256 availableTokens = contractJettonBalance - totalJettonsSold;
        require(availableTokens > 0, "No tokens to withdraw");

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
        require(block.timestamp >= lockEndTime, "Lock period not ended");
        require(contractSupportBalance > 0, "No support tokens to withdraw");

        _transferSupportTokens(owner(), contractSupportBalance);
        contractSupportBalance = 0;
    }

    /**
     * @dev Get profit on request
     */
    function getProfitOnRequest() external override nonReentrant {
        require(profitInTime, "Profit mode is not active");

        if (_msgSender() == owner()) {
            require(ownerSupportBalance > 0, "No profit available");
            _transferSupportTokens(owner(), ownerSupportBalance);
            ownerSupportBalance = 0;
        } else {
            require(_msgSender() == royaltyWalletAddress, "Access denied");
            require(royaltySupportBalance > 0, "No profit available");
            _transferSupportTokens(royaltyWalletAddress, royaltySupportBalance);
            royaltySupportBalance = 0;
        }
    }

    // Internal functions for handling different types of transactions
    function _handleOwnerDeposit(uint256 value) internal {
        if (offsetJettons > jettonsEarned) {
            uint256 deltaSupportBalance = _calculateChangeOffsetSupport(value);
            contractSupportBalance += deltaSupportBalance;
            uint256 change = value - deltaSupportBalance;
            if (change > 0) {
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
            require(marketMakerAddresses[_msgSender()], "Trading not allowed - only market makers can trade now");
        }
        require(contractJettonBalance > totalJettonsSold, "Insufficient token balance");

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

        uint256 netValue = supportAmount - actualProfit;
        contractSupportBalance += netValue;
        totalJettonsSold += totalTokens;

        launchToken.safeTransfer(_msgSender(), totalTokens);

        emit TokensPurchased(_msgSender(), totalTokens, supportAmount);
    }

    function _handleReturnWalletSale(uint256 amount) internal {
        uint256 supportAmountToPay = 0;
        uint256 tokensAvailableForReturnBuyback = totalJettonsSold - jettonsEarned;
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
        require(contractSupportBalance >= supportAmountToPay, "Insufficient support balance");
        contractSupportBalance -= supportAmountToPay;
        contractJettonBalance += amount;

        if (supportAmountToPay > 0) {
            _transferSupportTokens(owner(), supportAmountToPay);
        }
    }

    function _handleTokenSale(uint256 amount) internal {
        if (!_checkTradingAccess()) {
            require(marketMakerAddresses[_msgSender()], "Trading not allowed - only market makers can trade now");
        }

        uint256 tokensAvailableForBuyback =
            totalJettonsSold - (offsetJettons > jettonsEarned ? offsetJettons : jettonsEarned);
        require(tokensAvailableForBuyback > 0, "No tokens available for buyback");
        require(tokensAvailableForBuyback >= amount, "Insufficient tokens for buyback");

        uint256 supportAmountToPay = _calculateSupportToPayForTokenAmount(amount);
        require(contractSupportBalance >= supportAmountToPay, "Insufficient support balance");
        require(totalJettonsSold >= amount, "Insufficient sold tokens");

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
            block.timestamp - controlDay > Constants.THIRTY_DAYS
                && (block.timestamp - controlDay - Constants.THIRTY_DAYS) < controlPeriod
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
        uint256 remainingOffsetJettons = amountJettons;
        uint256 localCurrentStep = offsetStep;
        uint256 remainderOfStepLocal = remainderOffsetJettons;
        uint256 jettonsPerLevel = sizeOffsetStep;
        uint256 currentPriceLocal = currentPrice;

        while (remainingOffsetJettons > 0) {
            uint256 tokensAvailableInStep = remainderOfStepLocal;

            if (remainingOffsetJettons >= tokensAvailableInStep) {
                remainingOffsetJettons -= tokensAvailableInStep;
                localCurrentStep += 1;

                jettonsPerLevel = _calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStepLocal = jettonsPerLevel;
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                remainderOfStepLocal -= remainingOffsetJettons;
                remainingOffsetJettons = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOffsetJettons = remainderOfStepLocal;
        sizeOffsetStep = jettonsPerLevel;
        offsetPrice = currentPriceLocal;

        currentStep = localCurrentStep;
        quantityJettonsPerLevel = jettonsPerLevel;
        currentPrice = currentPriceLocal;

        remainderOfStep = remainderOfStepLocal;
        contractJettonBalance = amountJettons;
        totalJettonsSold = amountJettons;
    }

    function _calculateChangeOffsetSupport(uint256 amountSupport) internal returns (uint256) {
        uint256 remainingAddSupport = amountSupport;
        uint256 remainingOffsetJettonsLocal = offsetJettons;
        uint256 remainingAddJettons = offsetJettons - jettonsEarned;
        uint256 localCurrentStep = offsetStep;
        uint256 remainderOfStepLocal = remainderOffsetJettons;
        uint256 jettonsPerLevel = sizeOffsetStep;
        uint256 currentPriceLocal = offsetPrice;

        while (remainingAddSupport > 0 && remainingAddJettons > 0) {
            uint256 tokensAvailableInStep = jettonsPerLevel - remainderOfStepLocal;
            uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
            uint256 tonInStep = (tokensAvailableInStep * currentPriceLocal) / Constants.PRICE_PRECISION;
            uint256 tonRealInStep =
                (tonInStep * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal)) / Constants.PERCENTAGE_DIVISOR;

            if (remainingAddSupport >= tonRealInStep && remainingAddJettons >= tokensAvailableInStep) {
                remainingAddSupport -= tonRealInStep;
                remainingOffsetJettonsLocal -= tokensAvailableInStep;
                remainingAddJettons -= tokensAvailableInStep;

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

                if (remainingAddSupport >= tonRealInStep) {
                    supportToPayForStep = (remainingAddJettons * adjustedPrice) / Constants.PRICE_PRECISION;
                    tokensToBuyInThisStep = remainingAddJettons;
                } else {
                    supportToPayForStep = remainingAddSupport;
                    tokensToBuyInThisStep = (remainingAddSupport * Constants.PRICE_PRECISION) / adjustedPrice;
                }

                remainderOfStepLocal += tokensToBuyInThisStep;
                remainingAddSupport -= supportToPayForStep;
                remainingOffsetJettonsLocal -= tokensToBuyInThisStep;
                remainingAddJettons = 0;
            }
        }

        offsetStep = localCurrentStep;
        remainderOffsetJettons = remainderOfStepLocal;
        offsetPrice = currentPriceLocal;
        sizeOffsetStep = jettonsPerLevel;
        offsetJettons = remainingOffsetJettonsLocal;

        return (amountSupport - remainingAddSupport);
    }

    function _calculateJettonsToGiveForSupportAmount(uint256 supportAmount) internal returns (uint256) {
        uint256 jettonsToGive = 0;
        uint256 remainingSupportAmount = supportAmount;
        uint256 localCurrentStep = currentStep;
        uint256 remainderOfStepLocal = remainderOfStep;
        uint256 jettonsPerLevel = quantityJettonsPerLevel;
        uint256 currentPriceLocal = currentPrice;
        uint256 totalProfit = 0;
        uint256 remainderOfJettons = contractJettonBalance - totalJettonsSold;

        while (remainingSupportAmount > 0 && remainderOfJettons >= jettonsToGive) {
            uint256 tokensAvailableInStep = remainderOfStepLocal;
            uint256 tonRequiredForStep = (tokensAvailableInStep * currentPriceLocal) / Constants.PRICE_PRECISION;

            if (remainingSupportAmount >= tonRequiredForStep) {
                jettonsToGive += tokensAvailableInStep;
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);

                uint256 profitInStep = (tonRequiredForStep * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingSupportAmount -= tonRequiredForStep;
                localCurrentStep += 1;

                jettonsPerLevel = _calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStepLocal = jettonsPerLevel;
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 tokensToBuyInThisStep = (remainingSupportAmount * Constants.PRICE_PRECISION) / currentPriceLocal;
                jettonsToGive += tokensToBuyInThisStep;
                uint256 tonSpentInThisStep = remainingSupportAmount;

                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 profitInStep = (tonSpentInThisStep * profitPercentageLocal) / Constants.PERCENTAGE_DIVISOR;
                totalProfit += profitInStep;

                remainingSupportAmount = 0;
                remainderOfStepLocal -= tokensToBuyInThisStep;
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
            remainderOfStep = remainderOfStepLocal;
        }

        return jettonsToGive;
    }

    function _calculateSupportToPayForTokenAmount(uint256 tokenAmount) internal returns (uint256) {
        uint256 supportAmountToPay = 0;
        uint256 remainingJettonAmount = tokenAmount;
        uint256 localCurrentStep = currentStep;
        uint256 remainderOfStepLocal = remainderOfStep;
        uint256 jettonsPerLevel = quantityJettonsPerLevel;
        uint256 currentPriceLocal = currentPrice;

        while (remainingJettonAmount > 0) {
            uint256 tokensAvailableInStep = jettonsPerLevel - remainderOfStepLocal;

            if (remainingJettonAmount >= tokensAvailableInStep) {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 supportToPayForStep = (tokensAvailableInStep * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                remainingJettonAmount -= tokensAvailableInStep;

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
                    remainingJettonAmount = 0;
                }
            } else {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 supportToPayForStep = (remainingJettonAmount * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                remainderOfStepLocal += remainingJettonAmount;
                remainingJettonAmount = 0;
            }
        }

        currentStep = localCurrentStep;
        quantityJettonsPerLevel = jettonsPerLevel;
        currentPrice = currentPriceLocal;

        if (remainderOfStepLocal < 0) {
            remainderOfStep = 0;
        } else {
            remainderOfStep = remainderOfStepLocal;
        }

        return supportAmountToPay;
    }

    function _calculateSupportForTokenAmountEarned(uint256 tokenAmount) internal returns (uint256) {
        uint256 supportAmountToPay = 0;
        uint256 remainingJettonAmount = tokenAmount;
        uint256 localCurrentStep = currentStepEarned;
        uint256 remainderOfStepLocal = remainderOfStepEarned;
        uint256 jettonsPerLevel = quantityJettonsPerLevelEarned;
        uint256 currentPriceLocal = currentPriceEarned;

        while (remainingJettonAmount > 0 && localCurrentStep <= currentStep) {
            uint256 tokensAvailableInStep = remainderOfStepLocal;

            if (remainingJettonAmount >= tokensAvailableInStep) {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 supportToPayForStep = (tokensAvailableInStep * adjustedPrice) / Constants.PRICE_PRECISION;
                supportAmountToPay += supportToPayForStep;

                localCurrentStep += 1;
                jettonsPerLevel = _calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStepLocal = jettonsPerLevel;
                remainingJettonAmount -= tokensAvailableInStep;
                currentPriceLocal = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR + priceIncrementMultiplier))
                    / Constants.PERCENTAGE_DIVISOR;
            } else {
                uint256 profitPercentageLocal = _calculateProfit(localCurrentStep);
                uint256 adjustedPrice = (currentPriceLocal * (Constants.PERCENTAGE_DIVISOR - profitPercentageLocal))
                    / Constants.PERCENTAGE_DIVISOR;
                uint256 supportToPayForStep = (remainingJettonAmount * adjustedPrice) / Constants.PRICE_PRECISION;
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
            remainderOfStepEarned = remainderOfStepLocal;
        }

        return supportAmountToPay;
    }

    // View functions
    function remainingSeconds() external view override returns (uint256) {
        return lockEndTime > block.timestamp ? lockEndTime - block.timestamp : 0;
    }

    function tradingOpportunity() external view override returns (bool) {
        return lockEndTime - block.timestamp < Constants.THIRTY_DAYS;
    }

    function jettonBalance() external view override returns (uint256) {
        return contractJettonBalance;
    }

    function jettonSold() external view override returns (uint256) {
        return totalJettonsSold;
    }

    function jettonAvailable() external view override returns (uint256) {
        return totalJettonsSold - jettonsEarned;
    }

    function supportTokenBalance() external view override returns (uint256) {
        return contractSupportBalance;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
