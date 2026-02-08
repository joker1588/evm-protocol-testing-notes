// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title OrderbookCollateralLock Test
 * @notice Demonstrates locked funds when executing orders with price improvement
 * @dev Simplified standalone version of orderbook matching logic
 */
contract OrderbookCollateralLockTest is Test {
    MockPortfolio portfolio;
    GenericTradePairs tradePairs;
    
    address maker = address(0x1);
    address taker = address(0x2);
    
    string constant QUOTE = "USDT";
    string constant BASE = "BTC";
    
    function setUp() public {
        portfolio = new MockPortfolio();
        tradePairs = new GenericTradePairs(address(portfolio));
        
        // Fund Maker with Quote token (for buying)
        portfolio.deposit(maker, QUOTE, 1000e18); // $1000
    }
    
    function testSurplusCollateralLock() public {
        // 1. Maker places Limit Buy for 1 BTC @ $100
        // Blocks $100 in portfolio
        uint256 quantity = 1e18; // 1 BTC
        uint256 limitPrice = 100e18; // $100
        
        vm.startPrank(maker);
        tradePairs.placeOrder(maker, QUOTE, limitPrice, quantity);
        vm.stopPrank();
        
        // Verify lock
        (uint256 total, uint256 avail) = portfolio.getBalance(maker, QUOTE);
        console.log("=== Initial State ===");
        console.log("Maker Total Balance:", total / 1e18);
        console.log("Maker Available:", avail / 1e18);
        console.log("Locked:", (total - avail) / 1e18);
        
        assertEq(total, 1000e18);
        assertEq(avail, 900e18); // 1000 - 100
        
        // 2. Match with Taker Sell Order
        // BUT Taker is willing to sell at $90 (Price Improvement!)
        // Execution price = $90
        uint256 execPrice = 90e18;
        
        console.log("\n=== Executing Trade ===");
        console.log("Limit Price: $100");
        console.log("Execution Price: $90 (Better!)");
        
        tradePairs.matchOrder(maker, execPrice, quantity);
        
        // 3. Verify Balances
        // Maker spent $90. Should have $910 remaining ($900 avail + $10 refund)
        (uint256 totalAfter, uint256 availAfter) = portfolio.getBalance(maker, QUOTE);
        
        console.log("\n=== After Trade ===");
        console.log("Maker Total:", totalAfter / 1e18);
        console.log("Maker Available:", availAfter / 1e18);
        
        // Total reduced by execution cost ($90)
        assertEq(totalAfter, 910e18, "Total balance correct (1000 - 90)");
        
        // VULNERABILITY: Available balance is 900, NOT 910
        // The $10 surplus (100 - 90) is still locked!
        // It failed to return to 'available'
        
        // In a correct system: availAfter == 910e18
        // In vulnerable system: availAfter == 900e18
        
        if (availAfter == 900e18) {
            console.log("VULNERABILITY CONFIRMED: Surplus $10 is LOCKED");
            console.log("Funds exist in Total but are missing from Available");
        }
        
        assertEq(availAfter, 900e18, "VULNERABILITY: Surplus locked");
    }
}

contract MockPortfolio {
    struct Balance {
        uint256 total;
        uint256 available;
    }
    
    mapping(address => mapping(string => Balance)) public balances;
    
    function deposit(address user, string memory token, uint256 amount) external {
        balances[user][token].total += amount;
        balances[user][token].available += amount;
    }
    
    function lock(address user, string memory token, uint256 amount) external {
        require(balances[user][token].available >= amount, "Insufficient available");
        balances[user][token].available -= amount;
    }
    
    function trade(address user, string memory token, uint256 cost) external {
        // Deduct from TOTAL
        // Assumes funds were already LOCKED from Available
        require(balances[user][token].total >= cost, "Insufficient total");
        balances[user][token].total -= cost;
        
        // Logic note: 'available' was already reduced by 'limitPrice' during lock
        // If cost < limitPrice, we should refund difference... but we don't here
    }
    
    function getBalance(address user, string memory token) external view returns (uint256, uint256) {
        return (balances[user][token].total, balances[user][token].available);
    }
}

contract GenericTradePairs {
    MockPortfolio public portfolio;
    
    struct Order {
        uint256 price;
        uint256 quantity;
    }
    
    mapping(address => Order) public orders;
    
    constructor(address _portfolio) {
        portfolio = MockPortfolio(_portfolio);
    }
    
    function placeOrder(address maker, string memory token, uint256 price, uint256 quantity) external {
        // Lock full limit amount
        uint256 cost = price * quantity / 1e18; // simplified
        portfolio.lock(maker, token, cost);
        
        orders[maker] = Order(price, quantity);
    }
    
    function matchOrder(address maker, uint256 execPrice, uint256 quantity) external {
        Order memory order = orders[maker];
        
        // Calculate actual cost
        uint256 actualCost = execPrice * quantity / 1e18;
        
        // Execute trade in portfolio
        portfolio.trade(maker, "USDT", actualCost);
        
        // VULNERABILITY: Missing refund logic
        // Should check: if (order.price > execPrice) refund(diff)
        /*
        if (order.price > execPrice) {
            uint256 refund = (order.price - execPrice) * quantity / 1e18;
            portfolio.unlock(maker, refund); // This is missing!
        }
        */
    }
}
