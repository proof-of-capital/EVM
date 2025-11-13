// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

// Simple recipient contract that exposes a deposit function matching the
// IProofOfCapital interface. The implementation intentionally does nothing –
// it only needs to exist so that external calls in the main contract do not
// revert during tests.
contract MockRecipient {
    // Accepts an amount of support tokens from the caller. The body is empty
    // because tests do not rely on any specific behaviour, only on the fact
    // that the call does not revert.
    function deposit(
        uint256 /*amount*/
    )
        external
        payable {}
}
