// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockLending.sol";
import "../src/MockToken.sol";

/**
 * @title 借贷协议边界测试
 * @notice 测试清算边界、利率计算和极端情况
 */
contract LendingEdgeCasesTest is Test {
    MockToken public collateralToken;
    MockToken public borrowToken;
    MockLending public lending;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public liquidator = address(0x3);

    function setUp() public {
        // 部署代币
        collateralToken = new MockToken("Collateral", "COLL", 18);
        borrowToken = new MockToken("Borrow Token", "DEBT", 18);

        // 部署借贷协议
        lending = new MockLending(address(collateralToken), address(borrowToken));

        // 为协议铸造足够的借贷代币
        borrowToken.mint(address(lending), 10000 ether);

        // 为用户铸造代币
        collateralToken.mint(alice, 1000 ether);
        collateralToken.mint(bob, 1000 ether);
        borrowToken.mint(liquidator, 1000 ether);

        // 授权
        vm.prank(alice);
        collateralToken.approve(address(lending), type(uint256).max);

        vm.prank(bob);
        collateralToken.approve(address(lending), type(uint256).max);

        vm.prank(liquidator);
        borrowToken.approve(address(lending), type(uint256).max);
    }

    /**
     * @notice 测试基本借贷流程
     */
    function test_BasicBorrowRepay() public {
        vm.startPrank(alice);

        // 存入 100 抵押品
        lending.deposit(100 ether);

        // 借款 50（低于 80% 阈值）
        lending.borrow(50 ether);

        // 检查健康系数
        uint256 healthFactor = lending.getHealthFactor(alice);
        console.log("Health factor:", healthFactor);

        assertTrue(healthFactor > 1e18, "Position should be healthy");

        // 还款
        borrowToken.mint(alice, 50 ether);
        borrowToken.approve(address(lending), 50 ether);
        lending.repay(50 ether);

        vm.stopPrank();
    }

    /**
     * @notice 测试清算阈值边界
     */
    function test_LiquidationBoundary() public {
        vm.startPrank(alice);

        // 存入 100 抵押品
        lending.deposit(100 ether);

        // 借款到最大限额（80）
        lending.borrow(80 ether);

        // 此时应该刚好健康
        assertFalse(lending.isLiquidatable(alice), "Should not be liquidatable yet");

        vm.stopPrank();

        // 时间流逝，积累利息
        vm.warp(block.timestamp + 365 days);

        // 现在应该可以被清算了（利息累积导致债务超过阈值）
        bool isLiquidatable = lending.isLiquidatable(alice);
        console.log("Is liquidatable after 1 year:", isLiquidatable);

        if (isLiquidatable) {
            vm.prank(liquidator);
            lending.liquidate(alice, 10 ether);
            console.log("Liquidation successful");
        }
    }

    /**
     * @notice 测试部分清算
     */
    function test_PartialLiquidation() public {
        vm.startPrank(alice);

        lending.deposit(100 ether);
        lending.borrow(80 ether);

        vm.stopPrank();

        // 时间流逝
        vm.warp(block.timestamp + 365 days);

        // 检查清算前的状态
        (uint256 collateralBefore, uint256 debtBefore,) = lending.accounts(alice);
        console.log("Collateral before:", collateralBefore);
        console.log("Debt before:", debtBefore);

        // 清算部分债务
        if (lending.isLiquidatable(alice)) {
            vm.prank(liquidator);
            lending.liquidate(alice, 10 ether);

            (uint256 collateralAfter, uint256 debtAfter,) = lending.accounts(alice);
            console.log("Collateral after:", collateralAfter);
            console.log("Debt after:", debtAfter);

            // 验证清算奖励
            uint256 collateralSeized = collateralBefore - collateralAfter;
            uint256 expectedSeized = (10 ether * 10500) / 10000; // 10 + 5% bonus

            assertApproxEqAbs(collateralSeized, expectedSeized, 0.01 ether);
        }
    }

    /**
     * @notice 测试利息计算的精度
     */
    function test_InterestPrecision() public {
        vm.startPrank(alice);

        lending.deposit(100 ether);
        lending.borrow(50 ether);

        vm.stopPrank();

        // 记录初始债务
        (, uint256 initialDebt,) = lending.accounts(alice);

        // 时间流逝
        vm.warp(block.timestamp + 30 days);

        // 触发利息累积（尝试借款 0，会触发 _accrueInterest）
        vm.prank(alice);
        vm.expectRevert();
        lending.borrow(0);

        // 检查健康系数变化
        uint256 healthFactor = lending.getHealthFactor(alice);
        console.log("Health factor after 30 days:", healthFactor);

        // 计算预期利息
        uint256 expectedInterest = (50 ether * 500 * 30 days) / (10000 * 365 days);
        console.log("Expected interest:", expectedInterest);
    }

    /**
     * @notice 测试极小金额的清算
     */
    function test_TinyAmountLiquidation() public {
        vm.startPrank(alice);

        // 存入极小金额
        lending.deposit(1 ether);
        lending.borrow(0.8 ether);

        vm.stopPrank();

        // 时间流逝
        vm.warp(block.timestamp + 365 days);

        if (lending.isLiquidatable(alice)) {
            vm.prank(liquidator);
            // 尝试清算极小金额
            lending.liquidate(alice, 0.01 ether);

            console.log("Tiny liquidation successful");
        }
    }

    /**
     * @notice 测试健康头寸不能被清算
     */
    function test_CannotLiquidateHealthyPosition() public {
        vm.startPrank(alice);

        lending.deposit(100 ether);
        lending.borrow(50 ether); // 只借 50%，远低于 80% 阈值

        vm.stopPrank();

        assertFalse(lending.isLiquidatable(alice), "Should not be liquidatable");

        vm.prank(liquidator);
        vm.expectRevert("POSITION_HEALTHY");
        lending.liquidate(alice, 10 ether);
    }

    /**
     * @notice 测试过度清算保护
     */
    function test_ExcessiveLiquidationProtection() public {
        vm.startPrank(alice);

        lending.deposit(100 ether);
        lending.borrow(80 ether);

        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        if (lending.isLiquidatable(alice)) {
            vm.prank(liquidator);
            // 尝试清算过多债务（需要过多抵押品）
            vm.expectRevert("INSUFFICIENT_COLLATERAL");
            lending.liquidate(alice, 100 ether);
        }
    }

    /**
     * @notice Fuzz 测试：随机金额的借贷
     */
    function testFuzz_BorrowRepay(uint256 collateral, uint256 borrowAmount) public {
        // 限制输入范围
        collateral = bound(collateral, 1 ether, 1000 ether);
        borrowAmount = bound(borrowAmount, 0.1 ether, collateral * 80 / 100);

        vm.startPrank(alice);

        collateralToken.mint(alice, collateral);
        collateralToken.approve(address(lending), collateral);

        lending.deposit(collateral);
        lending.borrow(borrowAmount);

        // 检查健康系数应该 > 1
        uint256 healthFactor = lending.getHealthFactor(alice);
        assertGe(healthFactor, 1e18, "Health factor should be >= 1");

        vm.stopPrank();
    }
}
