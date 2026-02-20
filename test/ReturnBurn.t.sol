// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/EVM

pragma solidity 0.8.34;

import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {ReturnBurn} from "../src/ReturnBurn.sol";
import {ProofOfCapital} from "../src/ProofOfCapital.sol";
import {IProofOfCapital} from "../src/interfaces/IProofOfCapital.sol";
import {IDaoBurnDistribution} from "../src/interfaces/IDaoBurnDistribution.sol";
import {Constants} from "../src/utils/Constant.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockDaoBurnDistribution is IDaoBurnDistribution {
    address[] private _pocContracts;
    uint256[] private _percentages;

    constructor(address[] memory pocContracts, uint256[] memory percentages) {
        _pocContracts = pocContracts;
        _percentages = percentages;
    }

    function getBurnDistribution()
        external
        view
        override
        returns (address[] memory pocContracts, uint256[] memory percentages)
    {
        return (_pocContracts, _percentages);
    }
}

contract ReturnBurnTest is BaseTest {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    StdStorage private _stdStore;

    function testReturnBurnRevertsWhenDaoNotSet() public {
        ReturnBurn returnBurn = new ReturnBurn(IERC20(address(token)));
        vm.expectRevert(ReturnBurn.DaoNotSet.selector);
        returnBurn.processBurn(100e18);
    }

    function testReturnBurnRevertsWhenNothingToProcess() public {
        ReturnBurn returnBurn = new ReturnBurn(IERC20(address(token)));
        address[] memory pocs = new address[](0);
        uint256[] memory pcts = new uint256[](0);
        MockDaoBurnDistribution mockDao = new MockDaoBurnDistribution(pocs, pcts);
        returnBurn.setDao(address(mockDao));
        vm.expectRevert(ReturnBurn.NothingToProcess.selector);
        returnBurn.processBurn(100e18);
    }

    function testReturnBurnSetDaoRevertsWhenAlreadySet() public {
        ReturnBurn returnBurn = new ReturnBurn(IERC20(address(token)));
        address[] memory pocs = new address[](1);
        pocs[0] = address(0x1);
        uint256[] memory pcts = new uint256[](1);
        pcts[0] = Constants.PERCENTAGE_DIVISOR;
        MockDaoBurnDistribution mockDao = new MockDaoBurnDistribution(pocs, pcts);
        returnBurn.setDao(address(mockDao));
        vm.expectRevert(ReturnBurn.DaoAlreadySet.selector);
        returnBurn.setDao(address(0x2));
    }

    function testReturnBurnProcessBurnSuccess() public {
        uint256 initialSupply = token.totalSupply();
        ReturnBurn returnBurn = new ReturnBurn(IERC20(address(token)));
        assertEq(returnBurn.initialTotalSupply(), initialSupply);

        IProofOfCapital.InitParams memory params = getValidParams();
        params.RETURN_BURN_CONTRACT_ADDRESS = address(returnBurn);
        ProofOfCapital poc = new ProofOfCapital(params);

        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), address(poc), 500000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), owner, 50000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), marketMaker, 50000e18);
        address dao = address(0xDA0);
        poc.setDao(dao);
        vm.stopPrank();
        vm.prank(dao);
        poc.setMarketMaker(marketMaker, true);
        vm.prank(marketMaker);
        weth.approve(address(poc), type(uint256).max);

        uint256 slotControlDay = _stdStore.target(address(poc)).sig("controlDay()").find();
        vm.store(address(poc), bytes32(slotControlDay), bytes32(block.timestamp - 1 days));
        vm.startPrank(owner);
        poc.calculateUnaccountedOffsetBalance(poc.unaccountedOffset());
        weth.approve(address(poc), 10000e18);
        poc.depositCollateral(10000e18);
        token.approve(address(poc), 50000e18);
        poc.depositLaunch(50000e18);
        vm.stopPrank();

        vm.prank(marketMaker);
        poc.buyLaunchTokens(1000e18, 0);

        address[] memory pocs = new address[](1);
        pocs[0] = address(poc);
        uint256[] memory pcts = new uint256[](1);
        pcts[0] = Constants.PERCENTAGE_DIVISOR;
        MockDaoBurnDistribution mockDao = new MockDaoBurnDistribution(pocs, pcts);
        returnBurn.setDao(address(mockDao));

        uint256 burnedAmount = 500e18;
        uint256 mockedSupply = initialSupply - burnedAmount;
        vm.mockCall(address(token), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(mockedSupply));

        assertEq(returnBurn.getCurrentBurned(), burnedAmount, "current burned should match mock");
        assertEq(returnBurn.getUnaccountedBurned(), burnedAmount, "unaccounted should equal burned");

        uint256 ownerEarnedBefore = poc.ownerEarnedLaunchTokens();
        returnBurn.processBurn(burnedAmount);

        assertEq(returnBurn.totalAccounted(), burnedAmount, "totalAccounted should equal processed");
        assertEq(poc.ownerEarnedLaunchTokens(), ownerEarnedBefore + burnedAmount, "PoC ownerEarned should increase");
    }

    function testReturnBurnProcessBurnTwoPocsByPercentage() public {
        uint256 initialSupply = token.totalSupply();
        ReturnBurn returnBurn = new ReturnBurn(IERC20(address(token)));

        IProofOfCapital.InitParams memory params1 = getValidParams();
        params1.RETURN_BURN_CONTRACT_ADDRESS = address(returnBurn);
        ProofOfCapital poc1 = new ProofOfCapital(params1);
        IProofOfCapital.InitParams memory params2 = getValidParams();
        params2.RETURN_BURN_CONTRACT_ADDRESS = address(returnBurn);
        ProofOfCapital poc2 = new ProofOfCapital(params2);

        vm.startPrank(owner);
        SafeERC20.safeTransfer(IERC20(address(token)), address(poc1), 200000e18);
        SafeERC20.safeTransfer(IERC20(address(token)), address(poc2), 200000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), owner, 50000e18);
        SafeERC20.safeTransfer(IERC20(address(weth)), marketMaker, 50000e18);
        poc1.setDao(owner);
        poc2.setDao(owner);
        vm.stopPrank();
        vm.prank(owner);
        poc1.setMarketMaker(marketMaker, true);
        vm.prank(owner);
        poc2.setMarketMaker(marketMaker, true);
        vm.startPrank(marketMaker);
        weth.approve(address(poc1), type(uint256).max);
        weth.approve(address(poc2), type(uint256).max);
        vm.stopPrank();

        uint256 slot1 = _stdStore.target(address(poc1)).sig("controlDay()").find();
        uint256 slot2 = _stdStore.target(address(poc2)).sig("controlDay()").find();
        vm.store(address(poc1), bytes32(slot1), bytes32(block.timestamp - 1 days));
        vm.store(address(poc2), bytes32(slot2), bytes32(block.timestamp - 1 days));
        vm.startPrank(owner);
        poc1.calculateUnaccountedOffsetBalance(poc1.unaccountedOffset());
        poc2.calculateUnaccountedOffsetBalance(poc2.unaccountedOffset());
        weth.approve(address(poc1), 10000e18);
        weth.approve(address(poc2), 10000e18);
        poc1.depositCollateral(10000e18);
        poc2.depositCollateral(10000e18);
        token.approve(address(poc1), 50000e18);
        token.approve(address(poc2), 50000e18);
        poc1.depositLaunch(50000e18);
        poc2.depositLaunch(50000e18);
        vm.stopPrank();
        vm.prank(marketMaker);
        poc1.buyLaunchTokens(1000e18, 0);
        vm.prank(marketMaker);
        poc2.buyLaunchTokens(1000e18, 0);

        address[] memory pocs = new address[](2);
        pocs[0] = address(poc1);
        pocs[1] = address(poc2);
        uint256[] memory pcts = new uint256[](2);
        pcts[0] = 600; // 60%
        pcts[1] = 400; // 40%
        MockDaoBurnDistribution mockDao = new MockDaoBurnDistribution(pocs, pcts);
        returnBurn.setDao(address(mockDao));

        uint256 burnedAmount = 1000e18;
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(IERC20.totalSupply.selector),
            abi.encode(initialSupply - burnedAmount)
        );

        uint256 earned1Before = poc1.ownerEarnedLaunchTokens();
        uint256 earned2Before = poc2.ownerEarnedLaunchTokens();
        returnBurn.processBurn(burnedAmount);

        assertEq(returnBurn.totalAccounted(), burnedAmount, "totalAccounted");
        assertEq(poc1.ownerEarnedLaunchTokens(), earned1Before + 600e18, "PoC1 gets 60%");
        assertEq(poc2.ownerEarnedLaunchTokens(), earned2Before + 400e18, "PoC2 gets 40%");
    }

    function testReturnBurnGetCurrentBurnedAndUnaccounted() public {
        ReturnBurn returnBurn = new ReturnBurn(IERC20(address(token)));
        uint256 initialSupply = returnBurn.initialTotalSupply();
        assertEq(returnBurn.getCurrentBurned(), 0, "no burn initially");
        assertEq(returnBurn.getUnaccountedBurned(), 0, "no unaccounted initially");

        vm.mockCall(
            address(token), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(initialSupply - 300e18)
        );
        assertEq(returnBurn.getCurrentBurned(), 300e18, "current burned 300");
        assertEq(returnBurn.getUnaccountedBurned(), 300e18, "unaccounted 300");
    }

    function testReturnBurnRevertsInvalidPercentageSum() public {
        ReturnBurn returnBurn = new ReturnBurn(IERC20(address(token)));
        uint256 initialSupply = token.totalSupply();
        vm.mockCall(
            address(token), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(initialSupply - 100e18)
        );

        address[] memory pocs = new address[](1);
        pocs[0] = address(0x1);
        uint256[] memory pcts = new uint256[](1);
        pcts[0] = 500; // 50%, sum not 1000
        MockDaoBurnDistribution mockDao = new MockDaoBurnDistribution(pocs, pcts);
        returnBurn.setDao(address(mockDao));

        vm.expectRevert(ReturnBurn.InvalidPercentageSum.selector);
        returnBurn.processBurn(100e18);
    }

    function testReturnBurnConstructorRevertsZeroLaunchToken() public {
        vm.expectRevert(ReturnBurn.InvalidLaunchTokenAddress.selector);
        new ReturnBurn(IERC20(address(0)));
    }
}
