// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM

pragma solidity 0.8.29;

import {IRoyalty} from "../../src/interfaces/IRoyalty.sol";

/**
 * @title MockRoyalty
 * @dev Mock contract for testing royalty notifications
 */
contract MockRoyalty is IRoyalty {
    // Track notifications received
    mapping(address => bool) public lastProfitModeReceived;
    mapping(address => uint256) public notificationCount;

    // Option to simulate failure
    bool public shouldRevert;

    /**
     * @dev Set whether the contract should revert on notification
     * @param _shouldRevert True to revert, false to succeed
     */
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /**
     * @dev Notifies the royalty contract about profit mode change
     * @param pocContract Address of the ProofOfCapital contract
     * @param profitInTime New profit mode flag
     */
    function notifyProfitModeChanged(address pocContract, bool profitInTime) external override {
        if (shouldRevert) {
            revert("MockRoyalty: forced revert");
        }

        lastProfitModeReceived[pocContract] = profitInTime;
        notificationCount[pocContract]++;
    }

    /**
     * @dev Get the last profit mode received for a contract
     * @param pocContract Address of the ProofOfCapital contract
     * @return Last profit mode received
     */
    function getLastProfitMode(address pocContract) external view returns (bool) {
        return lastProfitModeReceived[pocContract];
    }

    /**
     * @dev Get the number of notifications received for a contract
     * @param pocContract Address of the ProofOfCapital contract
     * @return Number of notifications received
     */
    function getNotificationCount(address pocContract) external view returns (uint256) {
        return notificationCount[pocContract];
    }
}

