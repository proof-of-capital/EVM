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

/**
 * @title Constants
 * @dev Constants used in ProofOfCapital contract
 */
library Constants {
    // Time constants (in seconds)
    uint256 public constant TWO_YEARS = 365 days * 2; // 2 years
    uint256 public constant HALF_YEAR = 365 days / 2; // half year
    uint256 public constant THREE_MONTHS = 30 days * 3; // 3 months
    uint256 public constant MIN_CONTROL_PERIOD = 6 hours; // 6 hours minimum control period
    uint256 public constant MAX_CONTROL_PERIOD = 30 days; // 30 days maximum control period
    uint256 public constant TEN_MINUTES = 10 minutes; // 10 minutes for testing
    uint256 public constant THREE_WEEKS = 3 weeks; // 3 weeks
    uint256 public constant THIRTY_DAYS = 30 days; // 30 days

    // Percentage constants
    uint256 public constant PERCENTAGE_DIVISOR = 1000; // For percentage calculations (0.1% precision)
    uint256 public constant MAX_ROYALTY_PERCENT = 1000; // 100% maximum royalty
    uint256 public constant MIN_ROYALTY_PERCENT = 1; // 0.1% minimum royalty

    // Price calculation constants
    uint256 public constant PRICE_PRECISION = 1e18; // 18 decimal precision for price calculations
}
