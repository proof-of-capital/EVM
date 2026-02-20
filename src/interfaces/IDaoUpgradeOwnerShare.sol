// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/**
 * @dev DAO interface to upgrade owner share by receiving earned launch tokens.
 */
interface IDaoUpgradeOwnerShare {
    function upgradeOwnerShare(uint256 amount) external;
}

