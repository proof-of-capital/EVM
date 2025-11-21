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
        // Move time so that _checkTradingAccess() returns false
        // Need to be outside control window and more than 60 days before lock end
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        // Move to after control window but before lock end - 60 days
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        // Make sure we're still more than 60 days before lock end
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        vm.prank(owner);
        proofOfCapital.registerOldContract(MOCK_OLD_CONTRACT);

        assertTrue(proofOfCapital.oldContractAddress(MOCK_OLD_CONTRACT));
    }

    // Test registration fails with zero address
    function testRegisterOldContractZeroAddress() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OldContractAddressZero.selector);
        proofOfCapital.registerOldContract(address(0));
    }

    // Test registration fails when trading is active
    function testRegisterOldContractWhenTradingActive() public {
        // Don't move time - trading should be active initially
        // (lockEndTime is in future, but controlDay might make trading active)
        // Actually, if we're before controlDay, _checkControlDay() returns false
        // But lockEndTime is far in future, so last condition is false
        // So _checkTradingAccess() should return false initially
        // Let's move to within 60 days of lock end to make trading active
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        vm.warp(lockEndTime - Constants.SIXTY_DAYS + 1); // Within 60 days
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.LockIsActive.selector);
        proofOfCapital.registerOldContract(MOCK_OLD_CONTRACT);
    }

    // Test registration fails with owner address
    function testRegisterOldContractWithOwnerAddress() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(owner);
    }

    // Test registration fails with reserve owner address
    function testRegisterOldContractWithReserveOwnerAddress() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        address reserveOwner = proofOfCapital.reserveOwner();
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(reserveOwner);
    }

    // Test registration fails with launch token address
    function testRegisterOldContractWithLaunchTokenAddress() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        address launchToken = address(token); // Using token from BaseTest
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(launchToken);
    }

    // Test registration fails with WETH address
    function testRegisterOldContractWithWethAddress() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        address wethAddress = address(weth); // Using weth from BaseTest
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(wethAddress);
    }

    // Test registration fails with token collateral address
    function testRegisterOldContractWithTokenCollateralAddress() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        address collateralAddress = proofOfCapital.collateralAddress();
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(collateralAddress);
    }

    // Test registration fails with market maker address
    function testRegisterOldContractWithMarketMakerAddress() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        address marketMaker = address(0x9999);

        // First register a market maker
        vm.prank(owner);
        proofOfCapital.setMarketMaker(marketMaker, true);

        // Try to register the same address as old contract
        vm.prank(owner);
        vm.expectRevert(IProofOfCapital.OldContractAddressConflict.selector);
        proofOfCapital.registerOldContract(marketMaker);
    }

    // Test registration fails when called by non-owner
    function testRegisterOldContractUnauthorized() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        proofOfCapital.registerOldContract(MOCK_OLD_CONTRACT);
    }

    // Test event emission
    function testRegisterOldContractEvent() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IProofOfCapital.OldContractRegistered(MOCK_OLD_CONTRACT);
        proofOfCapital.registerOldContract(MOCK_OLD_CONTRACT);
    }

    // Test multiple registrations
    function testRegisterMultipleOldContracts() public {
        // Move time so that _checkTradingAccess() returns false
        uint256 controlDay = proofOfCapital.controlDay();
        uint256 controlPeriod = proofOfCapital.controlPeriod();
        uint256 targetTime = controlDay + controlPeriod + Constants.THIRTY_DAYS + 1;
        uint256 lockEndTime = proofOfCapital.lockEndTime();
        if (targetTime >= lockEndTime - Constants.SIXTY_DAYS) {
            targetTime = lockEndTime - Constants.SIXTY_DAYS - 1;
        }
        vm.warp(targetTime);
        address oldContract1 = address(0x1111);
        address oldContract2 = address(0x2222);

        vm.startPrank(owner);

        proofOfCapital.registerOldContract(oldContract1);
        assertTrue(proofOfCapital.oldContractAddress(oldContract1));

        // Can register immediately without waiting
        proofOfCapital.registerOldContract(oldContract2);
        assertTrue(proofOfCapital.oldContractAddress(oldContract2));

        vm.stopPrank();
    }
}
