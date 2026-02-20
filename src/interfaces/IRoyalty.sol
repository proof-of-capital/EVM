// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM

pragma solidity 0.8.34;

/**
 * @title IRoyalty
 * @dev Interface for Royalty contract that receives notifications from ProofOfCapital
 */
interface IRoyalty {
    /**
     * @dev Notifies the royalty contract about profit mode change
     * @param pocContract Address of the ProofOfCapital contract
     * @param profitInTime New profit mode flag (true = profit can be withdrawn anytime, false = only after lock ends)
     */
    function notifyProfitModeChanged(address pocContract, bool profitInTime) external;
}

