// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title OracleDepegDoS Test
 * @notice Demonstrates DoS when oracle reports out-of-range price
 * @dev This is a simplified, desensitized version of a real vulnerability
 */
contract OracleDepegDoSTest is Test {
    MockOracle oracle;
    SimpleLending lending;
    MockERC20 collateralToken;
    MockERC20 debtToken;
    
    address user = address(0x1);
    address liquidator = address(0x2);
    
    uint256 constant MIN_PRICE = 0.95e8; // $0.95
    uint256 constant MAX_PRICE = 1.05e8; // $1.05
    
    function setUp() public {
        collateralToken = new MockERC20("Collateral", "COL", 18);
        debtToken = new MockERC20("Debt", "DEBT", 18);
        
        oracle = new MockOracle();
        lending = new SimpleLending(
            address(oracle),
            address(collateralToken),
            address(debtToken),
            MIN_PRICE,
            MAX_PRICE
        );
        
        // Setup liquidity
        debtToken.mint(address(lending), 1000000e18);
        
        // User gets collateral
        collateralToken.mint(user, 1000e18);
    }
    
    function testNormalOperation() public {
        // Normal price: $1.00
        oracle.setPrice(1e8);
        
        vm.startPrank(user);
        collateralToken.approve(address(lending), 1000e18);
        
        // Deposit and borrow works fine
        lending.deposit(100e18);
        lending.borrow(80e18); // 80% LTV
        
        vm.stopPrank();
        
        console.log("=== Normal Operation ===");
        console.log("Price: $1.00");
        console.log("User deposited: 100");
        console.log("User borrowed: 80");
        console.log("Status: OK");
    }
    
    function testOracleDepegCausesDoS() public {
        // Setup: User has position
        oracle.setPrice(1e8);
        
        vm.startPrank(user);
        collateralToken.approve(address(lending), 1000e18);
        lending.deposit(100e18);
        lending.borrow(80e18);
        vm.stopPrank();
        
        console.log("=== Initial State ===");
        console.log("Price: $1.00");
        console.log("Position: 100 collateral, 80 debt");
        console.log("Health: OK");
        
        // Depeg event: Price drops to $0.85
        oracle.setPrice(0.85e8);
        
        console.log("\n=== After Depeg ===");
        console.log("Price: $0.85 (below MIN_PRICE $0.95)");
        console.log("Position should be liquidatable!");
        
        // VULNERABILITY: Liquidation fails due to price check
        vm.prank(liquidator);
        vm.expectRevert("Price out of range");
        lending.liquidate(user);
        
        console.log("VULNERABILITY: Cannot liquidate unhealthy position!");
        
        // User also cannot repay or withdraw
        vm.startPrank(user);
        
        vm.expectRevert("Price out of range");
        lending.repay(10e18);
        
        vm.expectRevert("Price out of range");
        lending.withdraw(10e18);
        
        vm.stopPrank();
        
        console.log("VULNERABILITY: User funds are locked!");
        console.log("Protocol is completely frozen due to oracle depeg");
    }
    
    function testProtocolAccumulatesBadDebt() public {
        // Setup multiple users with positions
        for (uint i = 0; i < 5; i++) {
            address u = address(uint160(0x100 + i));
            collateralToken.mint(u, 100e18);
            
            oracle.setPrice(1e8);
            vm.startPrank(u);
            collateralToken.approve(address(lending), 100e18);
            lending.deposit(100e18);
            lending.borrow(80e18);
            vm.stopPrank();
        }
        
        console.log("=== 5 Users with Positions ===");
        console.log("Each: 100 collateral, 80 debt");
        console.log("Total debt: 400");
        
        // Price crashes to $0.50
        oracle.setPrice(0.50e8);
        
        console.log("\n=== Price Crashes to $0.50 ===");
        console.log("All positions are severely underwater!");
        console.log("Collateral value: 500 * $0.50 = $250");
        console.log("Total debt: $400");
        console.log("Protocol is insolvent by $150");
        
        // But cannot liquidate any position
        for (uint i = 0; i < 5; i++) {
            address u = address(uint160(0x100 + i));
            vm.prank(liquidator);
            vm.expectRevert("Price out of range");
            lending.liquidate(u);
        }
        
        console.log("\nVULNERABILITY: Protocol accumulates bad debt!");
        console.log("Cannot liquidate = Protocol becomes insolvent");
    }
}

/**
 * @title MockOracle
 * @notice Simple oracle for testing
 */
contract MockOracle {
    int256 public price;
    
    function setPrice(int256 _price) external {
        price = _price;
    }
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
}

/**
 * @title SimpleLending
 * @notice Vulnerable lending protocol with strict price range check
 */
contract SimpleLending {
    address public oracle;
    address public collateralToken;
    address public debtToken;
    uint256 public minPrice;
    uint256 public maxPrice;
    
    mapping(address => uint256) public collateralBalance;
    mapping(address => uint256) public debtBalance;
    
    constructor(
        address _oracle,
        address _collateral,
        address _debt,
        uint256 _minPrice,
        uint256 _maxPrice
    ) {
        oracle = _oracle;
        collateralToken = _collateral;
        debtToken = _debt;
        minPrice = _minPrice;
        maxPrice = _maxPrice;
    }
    
    function getPrice() public view returns (uint256) {
        (, int256 price,,,) = IOracle(oracle).latestRoundData();
        
        require(price > 0, "Invalid price");
        
        // VULNERABILITY: Overly strict range check
        require(
            uint256(price) >= minPrice && uint256(price) <= maxPrice,
            "Price out of range"
        );
        
        return uint256(price);
    }
    
    function deposit(uint256 amount) external {
        getPrice(); // Check price
        
        IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);
        collateralBalance[msg.sender] += amount;
    }
    
    function borrow(uint256 amount) external {
        uint256 price = getPrice();
        
        uint256 collateralValue = collateralBalance[msg.sender] * price / 1e8;
        uint256 maxBorrow = collateralValue * 80 / 100; // 80% LTV
        
        require(debtBalance[msg.sender] + amount <= maxBorrow, "Insufficient collateral");
        
        debtBalance[msg.sender] += amount;
        IERC20(debtToken).transfer(msg.sender, amount);
    }
    
    function repay(uint256 amount) external {
        getPrice(); // Price check blocks repayment during depeg!
        
        IERC20(debtToken).transferFrom(msg.sender, address(this), amount);
        debtBalance[msg.sender] -= amount;
    }
    
    function withdraw(uint256 amount) external {
        getPrice(); // Price check blocks withdrawal during depeg!
        
        collateralBalance[msg.sender] -= amount;
        IERC20(collateralToken).transfer(msg.sender, amount);
    }
    
    function liquidate(address user) external {
        uint256 price = getPrice(); // Price check blocks liquidation during depeg!
        
        uint256 collateralValue = collateralBalance[user] * price / 1e8;
        uint256 liquidationThreshold = collateralValue * 90 / 100;
        
        require(debtBalance[user] > liquidationThreshold, "Position healthy");
        
        // Liquidation logic...
    }
}

interface IOracle {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

interface IERC20 {
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
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
