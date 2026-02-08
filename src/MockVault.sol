// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockToken.sol";

/**
 * @title MockVault
 * @notice 简化的金库合约，用于测试份额制金库逻辑
 * @dev 实现基于 ERC4626 的存取逻辑，用于测试舍入和会计问题
 */
contract MockVault {
    MockToken public asset;
    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    constructor(address _asset, string memory _name, string memory _symbol) {
        asset = MockToken(_asset);
        name = _name;
        symbol = _symbol;
        decimals = MockToken(_asset).decimals();
    }

    /**
     * @notice 计算资产对应的份额数量
     * @dev 注意：这里可能存在舍入问题
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : (assets * supply) / totalAssets();
    }

    /**
     * @notice 计算份额对应的资产数量
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : (shares * totalAssets()) / supply;
    }

    /**
     * @notice 金库中的总资产
     */
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice 存款功能
     * @param assets 存入的资产数量
     * @param receiver 接收份额的地址
     */
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = convertToShares(assets);
        require(shares > 0, "ZERO_SHARES");

        asset.transferFrom(msg.sender, address(this), assets);

        balanceOf[receiver] += shares;
        totalSupply += shares;

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice 提款功能
     * @param shares 销毁的份额数量
     * @param receiver 接收资产的地址
     * @param owner 份额所有者
     */
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        if (msg.sender != owner) {
            revert("NOT_AUTHORIZED");
        }

        assets = convertToAssets(shares);

        balanceOf[owner] -= shares;
        totalSupply -= shares;

        asset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice 预览存款可获得的份额
     */
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @notice 预览赎回可获得的资产
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }
}
