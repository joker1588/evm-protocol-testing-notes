// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockVault.sol";
import "../src/MockToken.sol";

/**
 * @title VaultLogic 测试
 * @notice 测试金库核心逻辑，重点关注份额计算和舍入问题
 */
contract VaultLogicTest is Test {
    MockToken public asset;
    MockVault public vault;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    function setUp() public {
        // 部署代币和金库
        asset = new MockToken("Mock Asset", "ASSET", 18);
        vault = new MockVault(address(asset), "Vault Shares", "vASSET");

        // 为测试用户铸造代币
        asset.mint(alice, 1000 ether);
        asset.mint(bob, 1000 ether);
        asset.mint(charlie, 1000 ether);

        // 授权
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(charlie);
        asset.approve(address(vault), type(uint256).max);
    }

    /**
     * @notice 测试基本的存取功能
     */
    function test_BasicDepositWithdraw() public {
        vm.startPrank(alice);

        // Alice 存入 100 ASSET
        uint256 shares = vault.deposit(100 ether, alice);
        assertEq(shares, 100 ether, "First deposit should be 1:1");
        assertEq(vault.balanceOf(alice), 100 ether);

        // Alice 赎回所有份额
        uint256 assets = vault.redeem(shares, alice, alice);
        assertEq(assets, 100 ether, "Should redeem same amount");
        assertEq(vault.balanceOf(alice), 0);

        vm.stopPrank();
    }

    /**
     * @notice 测试舍入导致的份额损失
     */
    function test_RoundingShareLoss() public {
        // Alice 首先存入，建立份额池
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // 模拟金库产生收益（直接转入资产）
        asset.mint(address(vault), 50 ether);

        // Bob 存入小额资产
        vm.startPrank(bob);
        uint256 bobDeposit = 1 ether;
        uint256 bobShares = vault.deposit(bobDeposit, bob);

        // 由于舍入，Bob 可能获得更少的份额
        uint256 expectedShares = vault.previewDeposit(bobDeposit);
        assertEq(bobShares, expectedShares);

        // Bob 立即赎回
        uint256 bobAssets = vault.redeem(bobShares, bob, bob);

        // 检查 Bob 是否遭受舍入损失
        console.log("Bob deposited:", bobDeposit);
        console.log("Bob received shares:", bobShares);
        console.log("Bob redeemed assets:", bobAssets);

        // 在某些情况下，bobAssets < bobDeposit
        if (bobAssets < bobDeposit) {
            console.log("Rounding loss detected:", bobDeposit - bobAssets);
        }

        vm.stopPrank();
    }

    /**
     * @notice 测试通胀攻击场景
     */
    function test_InflationAttack() public {
        // 攻击者部署策略：
        // 1. 首先存入最小量
        vm.startPrank(alice);
        vault.deposit(1, alice);

        // 2. 直接向金库转入大量资产，制造高 share 价格
        asset.mint(address(vault), 1000 ether);
        vm.stopPrank();

        // 受害者尝试存入
        vm.startPrank(bob);
        uint256 bobDeposit = 100 ether;

        // 检查 Bob 能获得的份额
        uint256 bobShares = vault.previewDeposit(bobDeposit);
        console.log("Bob deposit:", bobDeposit);
        console.log("Bob shares:", bobShares);

        // 如果 bobShares == 0，攻击成功
        if (bobShares == 0) {
            console.log("ATTACK SUCCESS: Bob gets 0 shares!");
        } else {
            vault.deposit(bobDeposit, bob);
            uint256 bobAssets = vault.previewRedeem(bobShares);
            console.log("Bob can redeem:", bobAssets);

            if (bobAssets < bobDeposit) {
                console.log("Bob suffers loss:", bobDeposit - bobAssets);
            }
        }

        vm.stopPrank();
    }

    /**
     * @notice 测试多用户存取的会计一致性
     */
    function test_MultiUserAccounting() public {
        // Alice 存入
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // Bob 存入
        vm.prank(bob);
        vault.deposit(200 ether, bob);

        // 模拟收益
        asset.mint(address(vault), 30 ether);

        // Charlie 存入
        vm.prank(charlie);
        vault.deposit(150 ether, charlie);

        // 检查总资产和总份额的关系
        uint256 totalAssets = vault.totalAssets();
        uint256 totalShares = vault.totalSupply();

        console.log("Total assets:", totalAssets);
        console.log("Total shares:", totalShares);

        // 所有人赎回
        vm.prank(alice);
        uint256 aliceAssets = vault.redeem(vault.balanceOf(alice), alice, alice);

        vm.prank(bob);
        uint256 bobAssets = vault.redeem(vault.balanceOf(bob), bob, bob);

        vm.prank(charlie);
        uint256 charlieAssets = vault.redeem(vault.balanceOf(charlie), charlie, charlie);

        console.log("Alice redeemed:", aliceAssets);
        console.log("Bob redeemed:", bobAssets);
        console.log("Charlie redeemed:", charlieAssets);

        // 检查剩余资产（应该接近 0，可能有小额舍入残留）
        uint256 remaining = vault.totalAssets();
        console.log("Remaining dust:", remaining);

        assertTrue(remaining < 100, "Too much dust remaining");
    }
}
