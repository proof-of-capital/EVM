// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import "../utils/BaseTest.sol";
import {console} from "forge-std/console.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

/**
 * Branch test to reach lines 1082-1084 of ProofOfCapital by minimal mathematical scenario.
 */
contract ProofOfCapitalBranch1082Test is BaseTest {
    using stdStorage for StdStorage;

    StdStorage private _stdStore;
    address public buyer = address(0x10);

    ProofOfCapital public poc;
    MockERC20 public tokenLocal;
    MockERC20 public wethLocal;
    address public retWallet;

    function setUp() public override {
        // overwrite default setup: deploy fresh contract with offsetTokens = 0
        vm.warp(1672531200);

        address _owner = owner;
        retWallet = returnWallet;

        // Begin acting as owner
        vm.startPrank(_owner);

        // deploy mock tokens (owner will receive initial supply from constructor)
        tokenLocal = new MockERC20("TKN", "TKN");
        wethLocal = new MockERC20("WETH", "WETH");

        // Fund buyer with WETH for purchases
        wethLocal.transfer(buyer, 2000e18);

        // prepare params with offsetTokens = 0
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(tokenLocal),
            marketMakerAddress: buyer,
            returnWalletAddress: retWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(wethLocal),
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelTokenQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetTokens: 0,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            tokenSupportAddress: address(wethLocal),
            royaltyProfitPercent: 500,
            oldContractAddresses: new address[](0)
        });

        ProofOfCapital impl = new ProofOfCapital();
        bytes memory data = abi.encodeWithSelector(ProofOfCapital.initialize.selector, params);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        poc = ProofOfCapital(payable(address(proxy)));

        // Provide actual launch tokens to the contract and adjust internal counter
        tokenLocal.transfer(address(poc), 1000e18);

        // Override storage variable `contractTokenBalance` to reflect the same amount using stdstore helper
        uint256 slot = _stdStore.target(address(poc)).sig("contractTokenBalance()").find();
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

    function testReachBranch() public {
        // Step 1: buyer buys 700 tokens (support amount 700e18)
        uint256 buyAmount = 700e18;
        vm.prank(buyer);
        poc.buyTokens(buyAmount);

        console.log("totalTokensSold after buy", poc.totalTokensSold());
        console.log("remainderOfStep", poc.remainderOfStep());

        // Step 2: buyer sells 700 tokens to hit branch
        uint256 sellAmount = 700e18;
        vm.prank(buyer);
        poc.sellTokens(sellAmount);

        // Expect console log from contract; cannot assert easily but we can check state to verify branch executed
        // After branch remainderOfStep should reset to tokensPerLevel (1000e18)
        assertEq(poc.remainderOfStep(), poc.quantityTokensPerLevel());
    }
}
