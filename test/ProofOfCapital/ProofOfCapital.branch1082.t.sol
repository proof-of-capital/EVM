// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {BaseTest} from "../utils/BaseTest.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProofOfCapital} from "../../src/ProofOfCapital.sol";
import {IProofOfCapital} from "../../src/interfaces/IProofOfCapital.sol";
import {Constants} from "../../src/utils/Constant.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/**
 * Branch test to reach lines 1082-1084 of ProofOfCapital by minimal mathematical scenario.
 */
contract ProofOfCapitalBranch1082Test is BaseTest {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    StdStorage private _stdStore;
    address public buyer = address(0x10);

    ProofOfCapital public poc;
    MockERC20 public tokenLocal;
    MockERC20 public wethLocal;
    address public retWallet;

    function setUp() public override {
        // overwrite default setup: deploy fresh contract with offsetLaunch = 0
        vm.warp(1672531200);

        address _owner = owner;
        retWallet = returnWallet;

        // Begin acting as owner
        vm.startPrank(_owner);

        // deploy mock tokens (owner will receive initial supply from constructor)
        tokenLocal = new MockERC20("TKN", "TKN");
        wethLocal = new MockERC20("WETH", "WETH");

        // Fund buyer with WETH for purchases
        SafeERC20.safeTransfer(IERC20(address(wethLocal)), buyer, 2000e18);

        // prepare params with offsetLaunch = 0
        IProofOfCapital.InitParams memory params = IProofOfCapital.InitParams({
            initialOwner: owner,
            launchToken: address(tokenLocal),
            marketMakerAddress: buyer,
            returnWalletAddress: retWallet,
            royaltyWalletAddress: royalty,
            lockEndTime: block.timestamp + 365 days,
            initialPricePerLaunchToken: 1e18,
            firstLevelLaunchTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierAfterTrend: 50,
            profitPercentage: 100,
            offsetLaunch: 0,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            collateralToken: address(wethLocal),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0),
            profitBeforeTrendChange: 200, // 20% before trend change (double the profit)
            daoAddress: address(0), // Will default to owner
            RETURN_BURN_CONTRACT_ADDRESS: address(0),
            collateralTokenOracle: address(0),
            collateralTokenMinOracleValue: 0
        });

        poc = new ProofOfCapital(params);

        // Provide actual launch tokens to the contract and adjust internal counter
        SafeERC20.safeTransfer(IERC20(address(tokenLocal)), address(poc), 1000e18);

        // Override storage variable `launchBalance` to reflect the same amount using stdstore helper
        uint256 slot = _stdStore.target(address(poc)).sig("launchBalance()").find();
        vm.store(address(poc), bytes32(slot), bytes32(uint256(1000e18)));

        // Approve PoC for owner's tokens (may be used later)
        tokenLocal.approve(address(poc), type(uint256).max);

        vm.stopPrank();

        // Approvals for buyer
        vm.startPrank(buyer);
        tokenLocal.approve(address(poc), type(uint256).max);
        wethLocal.approve(address(poc), type(uint256).max);
        vm.stopPrank();
    }
}
