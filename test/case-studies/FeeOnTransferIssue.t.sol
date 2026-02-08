// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title FeeOnTransferIssue Test
 * @notice Demonstrates accounting inconsistency with fee-on-transfer tokens
 * @dev This is a simplified, desensitized version of a real vulnerability
 */
contract FeeOnTransferIssueTest is Test {
    FeeOnTransferToken feeToken;
    SimpleLendingPool pool;
    
    address alice = address(0x1);
    address bob = address(0x2);
    
    uint256 constant FEE_PERCENT = 2; // 2% fee on transfer
    
    function setUp() public {
        feeToken = new FeeOnTransferToken("FeeToken", "FEE", 18, FEE_PERCENT);
        pool = new SimpleLendingPool(address(feeToken));
    }
    
    function testFeeOnTransferAccountingIssue() public {
        // Alice deposits 100 tokens
        feeToken.mint(alice, 100e18);
        
        vm.startPrank(alice);
        feeToken.approve(address(pool), 100e18);
        pool.deposit(100e18);
        vm.stopPrank();
        
        console.log("=== After Alice Deposit ===");
        console.log("Alice recorded balance:", pool.balanceOf(alice) / 1e18);
        console.log("Pool actual balance:", feeToken.balanceOf(address(pool)) / 1e18);
        
        // Alice recorded: 100
        // Pool actual: 98 (2% fee taken)
        assertEq(pool.balanceOf(alice), 100e18, "Alice should have 100 recorded");
        assertEq(feeToken.balanceOf(address(pool)), 98e18, "Pool should have 98 actual");
        
        // Bob also deposits 100 tokens
        feeToken.mint(bob, 100e18);
        
        vm.startPrank(bob);
        feeToken.approve(address(pool), 100e18);
        pool.deposit(100e18);
        vm.stopPrank();
        
        console.log("\n=== After Bob Deposit ===");
        console.log("Total recorded:", pool.totalDeposits() / 1e18);
        console.log("Total actual:", feeToken.balanceOf(address(pool)) / 1e18);
        
        // Total recorded: 200
        // Total actual: 196 (98 + 98)
        assertEq(pool.totalDeposits(), 200e18);
        assertEq(feeToken.balanceOf(address(pool)), 196e18);
        
        // Alice tries to withdraw all 100
        console.log("\n=== Alice Attempts Full Withdrawal ===");
        
        vm.startPrank(alice);
        vm.expectRevert(); // Will fail - not enough tokens
        pool.withdraw(100e18);
        vm.stopPrank();
        
        console.log("VULNERABILITY: Alice cannot withdraw her full recorded balance!");
        console.log("The 4 token deficit (2% * 200) is permanently lost");
    }
    
    function testLastWithdrawerLoses() public {
        // Setup: Multiple users deposit
        address[] memory users = new address[](5);
        for (uint i = 0; i < 5; i++) {
            users[i] = address(uint160(0x100 + i));
            feeToken.mint(users[i], 100e18);
            
            vm.startPrank(users[i]);
            feeToken.approve(address(pool), 100e18);
            pool.deposit(100e18);
            vm.stopPrank();
        }
        
        console.log("=== After 5 Users Deposit 100 Each ===");
        console.log("Total recorded:", pool.totalDeposits() / 1e18);
        console.log("Total actual:", feeToken.balanceOf(address(pool)) / 1e18);
        
        // Recorded: 500, Actual: 490 (2% * 500 = 10 lost)
        assertEq(pool.totalDeposits(), 500e18);
        assertEq(feeToken.balanceOf(address(pool)), 490e18);
        
        // First 4 users can withdraw (with fees)
        for (uint i = 0; i < 4; i++) {
            vm.prank(users[i]);
            pool.withdraw(100e18);
        }
        
        console.log("\n=== After 4 Users Withdraw ===");
        console.log("Remaining recorded:", pool.totalDeposits() / 1e18);
        console.log("Remaining actual:", feeToken.balanceOf(address(pool)) / 1e18);
        
        // Last user cannot withdraw full amount
        vm.startPrank(users[4]);
        vm.expectRevert();
        pool.withdraw(100e18);
        vm.stopPrank();
        
        console.log("\nVULNERABILITY: Last user is stuck!");
    }
}

/**
 * @title FeeOnTransferToken
 * @notice ERC20 token that charges fee on transfers
 */
contract FeeOnTransferToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    uint256 public feePercent;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _feePercent) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        feePercent = _feePercent;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        uint256 fee = amount * feePercent / 100;
        uint256 actualAmount = amount - fee;
        
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += actualAmount;
        // Fee is burned
        totalSupply -= fee;
        
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        
        uint256 fee = amount * feePercent / 100;
        uint256 actualAmount = amount - fee;
        
        balanceOf[from] -= amount;
        balanceOf[to] += actualAmount;
        totalSupply -= fee;
        
        return true;
    }
}

/**
 * @title SimpleLendingPool
 * @notice Vulnerable lending pool that doesn't handle fee-on-transfer tokens
 */
contract SimpleLendingPool {
    address public token;
    mapping(address => uint256) public balanceOf;
    uint256 public totalDeposits;
    
    constructor(address _token) {
        token = _token;
    }
    
    function deposit(uint256 amount) external {
        // VULNERABILITY: Records amount without checking actual received
        balanceOf[msg.sender] += amount;
        totalDeposits += amount;
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        // Actual received is less than amount due to fee!
    }
    
    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        
        balanceOf[msg.sender] -= amount;
        totalDeposits -= amount;
        
        // This will fail if pool doesn't have enough actual tokens
        IERC20(token).transfer(msg.sender, amount);
    }
}

interface IERC20 {
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}
