// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockRecipient {
    using SafeERC20 for IERC20;

    function deposit(
        uint256 /*amount*/
    )
        external
        payable {}

    function depositTokens(
        uint256 /*amount*/
    )
        external {}
}
