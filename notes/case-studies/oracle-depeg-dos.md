# Case Study: Oracle De-peg Leading to DoS

## Vulnerability Type
**Severity**: Medium  
**Category**: Denial of Service / Oracle Dependency

## Summary

Protocol relies on oracle for price data, but when oracle reports price outside expected range (de-peg), protocol's core functions are denied service due to overly strict validation.

## Vulnerability Details

### Problematic Code

```solidity
function getPrice() public view returns (uint256) {
    (uint80 roundId, int256 price, , uint256 updatedAt, ) = oracle.latestRoundData();
    
    require(price > 0, "Invalid price");
    require(block.timestamp - updatedAt < MAX_DELAY, "Stale price");
    
    // Issue: Overly strict range check
    require(price >= MIN_PRICE && price <= MAX_PRICE, "Price out of range");
    
    return uint256(price);
}
```

### Trigger Conditions

When stablecoin or other asset experiences de-peg event:
- Oracle correctly reports actual price (e.g., ASSET de-pegs to $0.85)
- Protocol rejects this price (because below MIN_PRICE = $0.95)
- All price-dependent functions (borrowing, liquidation, withdrawal) are DoS'd

## Impact

### 1. Liquidation Failure

When collateral price drops, it's precisely when liquidation is most needed, but price check blocks liquidation:

```solidity
function liquidate(address user) external {
    uint256 collateralPrice = oracle.getPrice(); // Reverts!
    // Cannot execute liquidation
}
```

### 2. User Funds Locked

Users cannot withdraw or adjust positions:

```solidity
function withdraw(uint256 amount) external {
    uint256 price = oracle.getPrice(); // Reverts!
    // User funds locked
}
```

### 3. Protocol Insolvency Risk

- Cannot liquidate unhealthy positions
- Bad debt accumulates
- Protocol becomes insolvent

## Real Scenario Example

### ASSET De-peg Event

1. **T0**: ASSET price = $1.00, protocol operates normally
2. **T1**: Market panic, ASSET begins de-pegging
3. **T2**: ASSET price = $0.90
   - Oracle correctly reports $0.90
   - Protocol rejects this price (< MIN_PRICE)
   - All functions stop
4. **T3**: Many positions become unhealthy, but cannot be liquidated
5. **T4**: Protocol accumulates bad debt, eventually becomes insolvent

## Proof of Concept

```solidity
function testOracleDepegDoS() public {
    GenericOracle oracle = new GenericOracle();
    GenericLending lending = new GenericLending(address(oracle));
    
    // 1. Normal case
    oracle.setPrice(1e8); // $1.00
    uint256 price1 = lending.getCollateralPrice();
    assertEq(price1, 1e8);
    
    // 2. User deposits collateral and borrows
    vm.startPrank(user);
    lending.deposit(100e18);
    lending.borrow(80e18); // 80% LTV
    vm.stopPrank();
    
    // 3. De-peg event
    oracle.setPrice(0.85e8); // $0.85 (below MIN_PRICE = $0.95)
    
    // 4. Liquidation fails
    vm.prank(liquidator);
    vm.expectRevert("Price out of range");
    lending.liquidate(user);
    
    // 5. User also cannot operate
    vm.prank(user);
    vm.expectRevert("Price out of range");
    lending.repay(10e18);
    
    // 6. Protocol completely frozen
    console.log("Protocol is frozen due to oracle depeg");
}
```

## Remediation

### Solution 1: Remove Range Check

```solidity
function getPrice() public view returns (uint256) {
    (uint80 roundId, int256 price, , uint256 updatedAt, ) = oracle.latestRoundData();
    
    require(price > 0, "Invalid price");
    require(block.timestamp - updatedAt < MAX_DELAY, "Stale price");
    
    // Remove range check, trust oracle
    return uint256(price);
}
```

### Solution 2: Degraded Mode

```solidity
function getPrice() public view returns (uint256) {
    (uint80 roundId, int256 price, , uint256 updatedAt, ) = oracle.latestRoundData();
    
    require(price > 0, "Invalid price");
    require(block.timestamp - updatedAt < MAX_DELAY, "Stale price");
    
    // If price abnormal, enter degraded mode
    if (price < MIN_PRICE || price > MAX_PRICE) {
        emit DegradedMode(price);
        // Still return price, but mark as degraded
    }
    
    return uint256(price);
}
```

### Solution 3: Circuit Breaker

```solidity
bool public circuitBreakerTripped;

function getPrice() public view returns (uint256) {
    (uint80 roundId, int256 price, , uint256 updatedAt, ) = oracle.latestRoundData();
    
    require(price > 0, "Invalid price");
    require(block.timestamp - updatedAt < MAX_DELAY, "Stale price");
    
    if (price < MIN_PRICE || price > MAX_PRICE) {
        if (!circuitBreakerTripped) {
            // First anomaly: trip breaker, but allow operation
            circuitBreakerTripped = true;
            emit CircuitBreakerTripped(price);
        }
    }
    
    return uint256(price);
}
```

## Key Takeaways

1. **Oracle Trust**: If using oracle, must trust its data
2. **Exception Handling**: Protocol should degrade during anomalies, not completely stop
3. **Liquidation Priority**: Liquidation function must work under any circumstances
4. **Range Check Risks**: Overly strict validation can be counterproductive

## Related Concepts

- Oracle design
- De-peg events
- Denial of Service (DoS)
- Circuit breaker pattern
- Degraded mode

---

**Tags**: #oracle #depeg #dos #circuit-breaker
