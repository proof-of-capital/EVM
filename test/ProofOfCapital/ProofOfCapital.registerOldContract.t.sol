// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

pragma solidity 0.8.29;

import "../utils/BaseTest.sol";
import "../../src/interfaces/IProofOfCapital.sol";
import "../../src/utils/Constant.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ProofOfCapitalRegisterOldContractTest is BaseTest {
    address public constant MOCK_OLD_CONTRACT = address(0x1234567890123456789012345678901234567890);
    address public alice = address(0x5);

    function setUp() public override {
        super.setUp();
        // Move time far from lock end to deactivate trading
        // vm.warp(proofOfCapital.lockEndTime() - 1 days);
    }
    
    // Test successful registration of old contract
    function testRegisterOldContract() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        vm.prank(owner);
        proofOfCapital.registerOldContract(MOCK_OLD_CONTRACT);
        
        assertTrue(proofOfCapital.oldContractAddress(MOCK_OLD_CONTRACT));
    }

    // Test registration fails with zero address
    function testRegisterOldContractZeroAddress() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressZero.selector);
        proofOfCapital.registerOldContract(address(0));
    }

    // Test registration fails when trading is active
    function testRegisterOldContractWhenTradingActive() public {

        
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.LockIsActive.selector);
        proofOfCapital.registerOldContract(MOCK_OLD_CONTRACT);
    }

    // Test registration fails with owner address
    function testRegisterOldContractWithOwnerAddress() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(owner);
    }

    // Test registration fails with reserve owner address
    function testRegisterOldContractWithReserveOwnerAddress() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        address reserveOwner = proofOfCapital.reserveOwner();
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(reserveOwner);
    }

    // Test registration fails with launch token address
    function testRegisterOldContractWithLaunchTokenAddress() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        address launchToken = address(token); // Using token from BaseTest
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(launchToken);
    }

    // Test registration fails with WETH address
    function testRegisterOldContractWithWethAddress() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        address wethAddress = address(weth); // Using weth from BaseTest
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(wethAddress);
    }

    // Test registration fails with token support address
    function testRegisterOldContractWithTokenSupportAddress() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        address tokenSupportAddress = proofOfCapital.tokenSupportAddress();
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(tokenSupportAddress);
    }

    // Test registration fails with market maker address
    function testRegisterOldContractWithMarketMakerAddress() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        address marketMaker = address(0x9999);
        
        // First register a market maker
        vm.prank(owner);
        proofOfCapital.setMarketMaker(marketMaker, true);
        
        // Try to register the same address as old contract
        vm.prank(owner);
        vm.expectRevert(ProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(marketMaker);
    }

    // Test registration fails when called by non-owner
    function testRegisterOldContractUnauthorized() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        proofOfCapital.registerOldContract(MOCK_OLD_CONTRACT);
    }

    // Test event emission
    function testRegisterOldContractEvent() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ProofOfCapital.OldContractRegistered(MOCK_OLD_CONTRACT);
        proofOfCapital.registerOldContract(MOCK_OLD_CONTRACT);
    }

    // Test multiple registrations
    function testRegisterMultipleOldContracts() public {
        vm.warp(proofOfCapital.lockEndTime() - 1 days);
        address oldContract1 = address(0x1111);
        address oldContract2 = address(0x2222);
        
        vm.startPrank(owner);
        
        proofOfCapital.registerOldContract(oldContract1);
        assertTrue(proofOfCapital.oldContractAddress(oldContract1));
        
        proofOfCapital.registerOldContract(oldContract2);
        assertTrue(proofOfCapital.oldContractAddress(oldContract2));
        
        vm.stopPrank();
    }
} 