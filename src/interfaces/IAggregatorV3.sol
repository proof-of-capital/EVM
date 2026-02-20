// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title Chainlink AggregatorV3Interface
/// @notice Interface for Chainlink price feed aggregator
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

