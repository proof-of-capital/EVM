// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/EVM

pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProofOfCapital} from "./interfaces/IProofOfCapital.sol";
import {IDaoBurnDistribution} from "./interfaces/IDaoBurnDistribution.sol";
import {Constants} from "./utils/Constant.sol";

/**
 * @title ReturnBurn
 * @dev Tracks launch token burns via totalSupply delta and distributes accounting across PoC contracts.
 * Does not hold or transfer tokens; only reads totalSupply and calls accountReturnBurn on each PoC.
 */
contract ReturnBurn {
    // Custom errors
    error DaoNotSet();
    error DaoAlreadySet();
    error InvalidDaoAddress();
    error NothingToProcess();
    error InsufficientBurned();
    error InvalidDistribution();
    error InvalidDistributionLength();
    error InvalidPercentageSum();
    error InvalidLaunchTokenAddress();

    event DaoSet(address indexed daoAddress);
    event ProcessedBurn(address indexed caller, uint256 amount, uint256 totalAccounted);

    IERC20 public immutable launchToken;
    uint256 public immutable initialTotalSupply;

    address public daoAddress;
    uint256 public totalAccounted;

    constructor(IERC20 _launchToken) {
        require(address(_launchToken) != address(0), InvalidLaunchTokenAddress());
        launchToken = _launchToken;
        initialTotalSupply = _launchToken.totalSupply();
    }

    /**
     * @dev Set DAO address once. DAO provides PoC list and percentage allocation via getBurnDistribution().
     */
    function setDao(address _daoAddress) external {
        require(daoAddress == address(0), DaoAlreadySet());
        require(_daoAddress != address(0), InvalidDaoAddress());
        daoAddress = _daoAddress;
        emit DaoSet(_daoAddress);
    }

    /**
     * @dev Current burned amount = initial supply minus current supply (no underflow).
     */
    function getCurrentBurned() public view returns (uint256) {
        uint256 current = launchToken.totalSupply();
        return initialTotalSupply > current ? initialTotalSupply - current : 0;
    }

    /**
     * @dev Burned amount not yet accounted across PoC contracts.
     */
    function getUnaccountedBurned() public view returns (uint256) {
        uint256 burned = getCurrentBurned();
        return burned > totalAccounted ? burned - totalAccounted : 0;
    }

    /**
     * @dev Process up to `amount` of burned tokens: fetch distribution from DAO and call accountReturnBurn on each PoC.
     * Last PoC receives the remainder to avoid dust from rounding.
     */
    function processBurn(uint256 amount) external {
        require(daoAddress != address(0), DaoNotSet());

        uint256 burned = getCurrentBurned();
        uint256 unaccounted = burned > totalAccounted ? burned - totalAccounted : 0;
        uint256 toProcess = amount > unaccounted ? unaccounted : amount;

        require(toProcess > 0, NothingToProcess());

        (address[] memory pocContracts, uint256[] memory percentages) =
            IDaoBurnDistribution(daoAddress).getBurnDistribution();

        require(pocContracts.length == percentages.length, InvalidDistributionLength());
        require(pocContracts.length > 0, InvalidDistribution());

        uint256 sumPercentages = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            sumPercentages += percentages[i];
        }
        require(sumPercentages == Constants.PERCENTAGE_DIVISOR, InvalidPercentageSum());

        uint256 allocated = 0;
        for (uint256 i = 0; i < pocContracts.length; i++) {
            uint256 portion;
            if (i == pocContracts.length - 1) {
                portion = toProcess - allocated;
            } else {
                portion = (toProcess * percentages[i]) / Constants.PERCENTAGE_DIVISOR;
                allocated += portion;
            }
            if (portion > 0) {
                IProofOfCapital(pocContracts[i]).accountReturnBurn(portion);
            }
        }

        totalAccounted += toProcess;
        emit ProcessedBurn(msg.sender, toProcess, totalAccounted);
    }
}
