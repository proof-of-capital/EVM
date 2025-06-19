// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVMpragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/ProofOfCapital.sol";
import "../../src/interfaces/IProofOfCapital.sol";
import "../../src/utils/Constant.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockWETH.sol";

contract BaseTest is Test {
    ProofOfCapital public proofOfCapital;
    MockERC20 public token;
    MockERC20 public weth;
    
    address public owner = address(0x1);
    address public royalty = address(0x2);
    address public returnWallet = address(0x3);
    address public marketMaker = address(0x4);
    
    function setUp() public virtual {
        // Set realistic timestamp to avoid underflow issues
        vm.warp(1672531200); // January 1, 2023
        
        vm.startPrank(owner);
        
        // Deploy mock tokens
        token = new MockERC20("TestToken", "TT");
        weth = new MockERC20("WETH", "WETH");
        
        // Deploy implementation
        ProofOfCapital implementation = new ProofOfCapital();
        
        // Prepare initialization parameters
        ProofOfCapital.InitParams memory params = ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(weth),
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 10000e18, // Add offset to enable trading
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0)
        });
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        proofOfCapital = ProofOfCapital(payable(address(proxy)));
        
        vm.stopPrank();
    }
    
    // Helper function to get valid initialization parameters
    function getValidParams() internal view returns (ProofOfCapital.InitParams memory) {
        return ProofOfCapital.InitParams({
            launchToken: address(token),
            marketMakerAddress: marketMaker,
            returnWalletAddress: returnWallet,
            royaltyWalletAddress: royalty,
            wethAddress: address(weth),
            lockEndTime: block.timestamp + 365 days,
            initialPricePerToken: 1e18,
            firstLevelJettonQuantity: 1000e18,
            priceIncrementMultiplier: 50,
            levelIncreaseMultiplier: 100,
            trendChangeStep: 5,
            levelDecreaseMultiplierafterTrend: 50,
            profitPercentage: 100,
            offsetJettons: 10000e18,
            controlPeriod: Constants.MIN_CONTROL_PERIOD,
            jettonSupportAddress: address(weth),
            royaltyProfitPercent: 500, // 50%
            oldContractAddresses: new address[](0)
        });
    }
    
    // Helper function to deploy contract with custom parameters
    function deployWithParams(ProofOfCapital.InitParams memory params) internal returns (ProofOfCapital) {
        ProofOfCapital implementation = new ProofOfCapital();
        
        bytes memory initData = abi.encodeWithSelector(
            ProofOfCapital.initialize.selector,
            params
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return ProofOfCapital(payable(address(proxy)));
    }
    
    // Helper function to create support balance in contract
    function createSupportBalance(uint256 amount) internal {
        vm.startPrank(owner);
        token.transfer(returnWallet, amount * 2); // Give enough for selling back
        vm.stopPrank();
        
        vm.startPrank(returnWallet);
        token.approve(address(proofOfCapital), amount * 2);
        proofOfCapital.sellTokens(amount); // This increases contractJettonBalance
        vm.stopPrank();
    }
} 