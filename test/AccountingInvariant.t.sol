// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockVault.sol";
import "../src/MockToken.sol";

/**
 * @title 会计不变量测试
 * @notice 使用 Foundry 不变量测试验证系统的核心会计属性
 */
contract AccountingInvariantTest is Test {
    MockToken public asset;
    MockVault public vault;
    VaultHandler public handler;

    function setUp() public {
        asset = new MockToken("Asset", "ASSET", 18);
        vault = new MockVault(address(asset), "Vault", "vASSET");
        handler = new VaultHandler(asset, vault);

        // 为 handler 铸造资产
        asset.mint(address(handler), type(uint128).max);
        
        // 设置不变量测试目标
        targetContract(address(handler));
    }

    /**
     * @notice 不变量：总份额对应的资产应该 <= 金库总资产
     */
    function invariant_TotalSharesValue() public view {
        uint256 totalShares = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        if (totalShares > 0) {
            uint256 shareValue = vault.convertToAssets(totalShares);
            assertLe(shareValue, totalAssets, "Share value exceeds total assets");
        }
    }

    /**
     * @notice 不变量：金库总资产 >= 所有用户份额的总价值
     */
    function invariant_SolvencyCheck() public view {
        uint256 totalShares = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        // 金库必须能够偿付所有份额
        if (totalShares > 0) {
            uint256 totalValue = vault.convertToAssets(totalShares);
            assertGe(totalAssets, totalValue, "Vault is insolvent");
        }
    }

    /**
     * @notice 不变量：份额价格应该单调非递减（除非发生损失）
     */
    function invariant_SharePriceMonotonic() public view {
        uint256 currentPrice = handler.lastSharePrice();
        uint256 newPrice = vault.totalSupply() > 0
            ? (vault.totalAssets() * 1e18) / vault.totalSupply()
            : 1e18;

        // 允许小幅度舍入误差
        if (currentPrice > 0) {
            assertGe(newPrice + 10, currentPrice, "Share price decreased unexpectedly");
        }
    }

    /**
     * @notice 不变量：用户份额总和 = 总供应量
     */
    function invariant_ShareAccountingConsistency() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 handlerShares = vault.balanceOf(address(handler));

        assertEq(handlerShares, totalSupply, "Share accounting inconsistent");
    }

    /**
     * @notice 不变量：金库资产余额 >= 协议记录的总资产
     */
    function invariant_AssetBalance() public view {
        uint256 actualBalance = asset.balanceOf(address(vault));
        uint256 totalAssets = vault.totalAssets();

        assertEq(actualBalance, totalAssets, "Asset balance mismatch");
    }

    /**
     * @notice 测试后统计
     */
    function logStats() public view {
        console.log("=== Invariant Test Stats ===");
        console.log("Total deposits:", handler.totalDeposits());
        console.log("Total withdrawals:", handler.totalWithdrawals());
        console.log("Final total assets:", vault.totalAssets());
        console.log("Final total shares:", vault.totalSupply());
        console.log("Call summary:");
        console.log("  - Deposits:", handler.depositCount());
        console.log("  - Withdrawals:", handler.withdrawCount());
    }
}

/**
 * @title VaultHandler
 * @notice 处理器合约，用于不变量测试中的随机操作
 */
contract VaultHandler is Test {
    MockToken public asset;
    MockVault public vault;

    uint256 public depositCount;
    uint256 public withdrawCount;
    uint256 public totalDeposits;
    uint256 public totalWithdrawals;
    uint256 public lastSharePrice = 1e18;

    constructor(MockToken _asset, MockVault _vault) {
        asset = _asset;
        vault = _vault;
        asset.approve(address(vault), type(uint256).max);
    }

    /**
     * @notice 随机存款操作
     */
    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 1000 ether);

        try vault.deposit(amount, address(this)) returns (uint256 shares) {
            depositCount++;
            totalDeposits += amount;

            // 更新份额价格
            if (vault.totalSupply() > 0) {
                lastSharePrice = (vault.totalAssets() * 1e18) / vault.totalSupply();
            }
        } catch {
            // 存款失败，忽略
        }
    }

    /**
     * @notice 随机取款操作
     */
    function withdraw(uint256 sharesPct) public {
        uint256 shares = vault.balanceOf(address(this));
        if (shares == 0) return;

        sharesPct = bound(sharesPct, 1, 100);
        uint256 sharesToWithdraw = (shares * sharesPct) / 100;

        if (sharesToWithdraw == 0) return;

        try vault.redeem(sharesToWithdraw, address(this), address(this)) returns (uint256 assets) {
            withdrawCount++;
            totalWithdrawals += assets;

            // 更新份额价格
            if (vault.totalSupply() > 0) {
                lastSharePrice = (vault.totalAssets() * 1e18) / vault.totalSupply();
            }
        } catch {
            // 取款失败，忽略
        }
    }

    /**
     * @notice 模拟金库收益
     */
    function simulateYield(uint256 amount) public {
        amount = bound(amount, 0, 100 ether);
        asset.mint(address(vault), amount);

        // 更新份额价格
        if (vault.totalSupply() > 0) {
            lastSharePrice = (vault.totalAssets() * 1e18) / vault.totalSupply();
        }
    }

    /**
     * @notice 模拟金库损失（谨慎使用）
     */
    function simulateLoss(uint256 amount) public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        if (vaultBalance == 0) return;

        amount = bound(amount, 0, vaultBalance / 10); // 最多损失 10%
        asset.burn(address(vault), amount);

        // 更新份额价格
        if (vault.totalSupply() > 0) {
            lastSharePrice = (vault.totalAssets() * 1e18) / vault.totalSupply();
        }
    }
}
