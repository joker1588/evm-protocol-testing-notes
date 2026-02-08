// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockToken.sol";

/**
 * @title MockLending
 * @notice 简化的借贷协议，用于测试清算和利率计算逻辑
 * @dev 包含存款、借款、清算功能
 */
contract MockLending {
    MockToken public collateralToken;
    MockToken public borrowToken;

    // 配置参数
    uint256 public constant LIQUIDATION_THRESHOLD = 8000; // 80%
    uint256 public constant LIQUIDATION_BONUS = 500; // 5%
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant INTEREST_RATE = 500; // 5% 年化

    struct UserAccount {
        uint256 collateral;
        uint256 borrowed;
        uint256 lastUpdateTime;
    }

    mapping(address => UserAccount) public accounts;

    event Deposit(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed user, uint256 debtCovered, uint256 collateralSeized);

    constructor(address _collateralToken, address _borrowToken) {
        collateralToken = MockToken(_collateralToken);
        borrowToken = MockToken(_borrowToken);
    }

    /**
     * @notice 存入抵押品
     */
    function deposit(uint256 amount) external {
        collateralToken.transferFrom(msg.sender, address(this), amount);
        accounts[msg.sender].collateral += amount;
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice 借款
     * @param amount 借款数量
     */
    function borrow(uint256 amount) external {
        UserAccount storage account = accounts[msg.sender];
        _accrueInterest(account);

        uint256 maxBorrow = (account.collateral * LIQUIDATION_THRESHOLD) / BASIS_POINTS;
        require(account.borrowed + amount <= maxBorrow, "INSUFFICIENT_COLLATERAL");

        account.borrowed += amount;
        account.lastUpdateTime = block.timestamp;

        borrowToken.transfer(msg.sender, amount);
        emit Borrow(msg.sender, amount);
    }

    /**
     * @notice 还款
     */
    function repay(uint256 amount) external {
        UserAccount storage account = accounts[msg.sender];
        _accrueInterest(account);

        uint256 repayAmount = amount > account.borrowed ? account.borrowed : amount;
        account.borrowed -= repayAmount;
        account.lastUpdateTime = block.timestamp;

        borrowToken.transferFrom(msg.sender, address(this), repayAmount);
        emit Repay(msg.sender, repayAmount);
    }

    /**
     * @notice 清算不健康的头寸
     * @param user 被清算用户
     * @param debtToCover 覆盖的债务数量
     */
    function liquidate(address user, uint256 debtToCover) external {
        UserAccount storage account = accounts[user];
        _accrueInterest(account);

        require(isLiquidatable(user), "POSITION_HEALTHY");

        uint256 collateralToSeize = (debtToCover * (BASIS_POINTS + LIQUIDATION_BONUS)) / BASIS_POINTS;
        require(collateralToSeize <= account.collateral, "INSUFFICIENT_COLLATERAL");

        account.borrowed -= debtToCover;
        account.collateral -= collateralToSeize;
        account.lastUpdateTime = block.timestamp;

        borrowToken.transferFrom(msg.sender, address(this), debtToCover);
        collateralToken.transfer(msg.sender, collateralToSeize);

        emit Liquidate(msg.sender, user, debtToCover, collateralToSeize);
    }

    /**
     * @notice 检查头寸是否可被清算
     */
    function isLiquidatable(address user) public view returns (bool) {
        UserAccount memory account = accounts[user];
        if (account.borrowed == 0) return false;

        uint256 debt = _calculateDebt(account);
        uint256 liquidationThreshold = (account.collateral * LIQUIDATION_THRESHOLD) / BASIS_POINTS;

        return debt > liquidationThreshold;
    }

    /**
     * @notice 获取账户健康系数
     */
    function getHealthFactor(address user) public view returns (uint256) {
        UserAccount memory account = accounts[user];
        if (account.borrowed == 0) return type(uint256).max;

        uint256 debt = _calculateDebt(account);
        uint256 collateralValue = (account.collateral * LIQUIDATION_THRESHOLD) / BASIS_POINTS;

        return (collateralValue * 1e18) / debt;
    }

    /**
     * @notice 计算当前债务（含利息）
     */
    function _calculateDebt(UserAccount memory account) internal view returns (uint256) {
        if (account.borrowed == 0) return 0;

        uint256 timeElapsed = block.timestamp - account.lastUpdateTime;
        uint256 interest = (account.borrowed * INTEREST_RATE * timeElapsed) / (BASIS_POINTS * 365 days);

        return account.borrowed + interest;
    }

    /**
     * @notice 累积利息
     */
    function _accrueInterest(UserAccount storage account) internal {
        if (account.borrowed == 0) return;

        uint256 debt = _calculateDebt(account);
        account.borrowed = debt;
        account.lastUpdateTime = block.timestamp;
    }
}
