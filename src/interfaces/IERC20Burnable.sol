// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/EVM

pragma solidity 0.8.29;

/**
 * @title IERC20Burnable
 * @dev Minimal interface for ERC20 tokens that support burning from another account (e.g. OpenZeppelin ERC20Burnable).
 */
interface IERC20Burnable {
    /**
     * @dev Destroys `value` tokens from `account`, deducting from the caller's allowance.
     */
    function burnFrom(address account, uint256 value) external;
}
