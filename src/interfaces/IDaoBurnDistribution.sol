// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/**
 * @dev DAO interface to provide PoC contract addresses and percentage allocation for burn distribution.
 * Percentages use BPS (basis points): BPS_DIVISOR = 10000 = 100%.
 */
interface IDaoBurnDistribution {
    function getBurnDistribution() external view returns (address[] memory pocContracts, uint256[] memory percentages);
}
