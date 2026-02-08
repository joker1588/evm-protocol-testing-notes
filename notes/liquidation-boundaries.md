# Liquidation Boundary Analysis Notes

## Liquidation Mechanism Overview

Lending protocols maintain system solvency through liquidation, triggered when user debt exceeds the liquidation threshold relative to collateral value.

## Key Parameters

- **Liquidation Threshold (LT)**: 80% (8000/10000)
- **Liquidation Bonus**: 5% (500/10000)
- **Health Factor**: `(collateral * LT) / debt`

## Boundary Conditions

### 1. Critical Health Factor

```solidity
// Just healthy
healthFactor = 1.0 (1e18)

// Liquidatable
healthFactor < 1.0
```

### 2. Interest Accumulation Leading to Liquidation

Initially healthy positions may become unhealthy after interest accumulation over time.

**Testing Points**:
- Verify interest calculation precision
- Impact of time passage on health factor

### 3. Partial Liquidation

Liquidators can choose to liquidate partial debt rather than the full amount.

**Risks**:
- Incorrect liquidation bonus calculation
- Remaining position still unhealthy

### 4. Edge Cases

- **Tiny Amount Liquidation**: 1 wei level liquidations
- **Large Amount Liquidation**: Near uint256.max liquidations
- **Price Volatility Boundaries**: Liquidations during extreme price movements

## Common Vulnerabilities

### Vulnerability Type A: Incorrect Liquidation Bonus Calculation

```solidity
// Incorrect example
collateralSeized = debtCovered // No bonus

// Correct example
collateralSeized = debtCovered * (1 + bonus)
```

### Vulnerability Type B: Incorrect Health Factor Calculation

Failure to properly calculate accumulated interest prevents liquidation of unhealthy positions.

### Vulnerability Type C: Insufficient Liquidation Protection

Allowing over-liquidation where liquidators can seize excess collateral.

## Testing Strategy

### Unit Tests

```solidity
function test_LiquidationBoundary() {
    // 1. Set up critical state
    // 2. Time passes
    // 3. Verify liquidatable
    // 4. Execute liquidation
    // 5. Verify results
}
```

### Fuzz Testing

Randomize:
- Collateral amount
- Borrow amount
- Time passage
- Liquidation amount

### Invariants

- Health factor should improve after liquidation
- Liquidator receives collateral = debt * (1 + bonus)
- System total assets ≥ total liabilities

## Real-World Examples (Educational)

### Example: Generic Lending V1

**Issue**: Interest calculation uses incorrect time units  
**Impact**: Debt grows too slowly, preventing timely liquidation  
**Fix**: Correct time unit calculation

## Best Practices

1. **Progressive Liquidation**: Allow partial liquidations
2. **Reasonable Liquidation Bonus**: Between 5-10%
3. **Health Factor Buffer**: Recommend maintaining healthFactor > 1.2
4. **Real-time Interest Accrual**: Update interest on every operation

---
**Tags**: #liquidation #lending #health-factor
