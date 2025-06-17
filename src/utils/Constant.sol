// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
