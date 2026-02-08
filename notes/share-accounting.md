# Share Accounting System Notes

## Share System Principles

DeFi protocols commonly use shares to represent user ownership percentage in a pool.

### Core Formulas

```solidity
userShare = userAssets / totalAssets * totalShares
userAssets = userShares / totalShares * totalAssets
```

## Accounting Invariants

### Invariant 1: Total Asset Consistency

```solidity
sum(allUserAssets) <= totalPoolAssets
```

Due to rounding, sum of user assets may be slightly less than total pool assets.

### Invariant 2: Share Conservation

```solidity
sum(allUserShares) == totalSupply
```

Shares must be precisely conserved and cannot be created or destroyed arbitrarily.

### Invariant 3: Share Price Monotonicity

```solidity
newSharePrice >= oldSharePrice
```

Without losses, share price should be monotonically increasing (yield accumulation).

## Accounting Attack Vectors

### 1. Rounding Abuse

Attackers accumulate rounding errors through multiple small operations for profit.

**Example**:
```solidity
// Repeatedly deposit and withdraw tiny amounts
for (i = 0; i < 1000; i++) {
    deposit(1 wei);
    withdraw(shares);
}
```

### 2. First Depositor Advantage

First depositor may receive disproportionate shares.

### 3. Share Dilution

Diluting other users' shares by directly transferring assets (bypassing normal flow).

## Testing Methods

### Invariant Testing Framework

```solidity
contract Handler {
    function deposit(uint256 amount) public;
    function withdraw(uint256 shares) public;
    function simulateYield(uint256 amount) public;
}

contract InvariantTest {
    function invariant_shareConservation() public view;
    function invariant_solvency() public view;
    function invariant_sharePriceMonotonic() public view;
}
```

### Key Test Scenarios

1. **Multi-user Concurrent Operations**
2. **Extreme Amounts (1 wei to max uint256)**
3. **Yield/Loss Simulation**
4. **Long-running Tests**

## Common Errors

### Error 1: Unsynchronized Updates

```solidity
// Incorrect
totalAssets += newAssets;
// Forgot to update other related state
```

### Error 2: Overflow/Underflow

```solidity
// Incorrect
userShares -= amount; // May underflow
```

**Fix**: Use Solidity 0.8+ automatic checks or SafeMath.

### Error 3: Race Conditions

State inconsistency between multiple operations.

## Audit Checklist

- [ ] All share operations correctly update totalSupply
- [ ] Asset transfers and share minting/burning are synchronized
- [ ] Rounding direction favors protocol
- [ ] Prevent share inflation attacks
- [ ] Handle extreme values (0, max)
- [ ] Time-dependent calculations are accurate

## Debugging Techniques

### 1. Log Key Variables

```solidity
console.log("Total assets:", totalAssets);
console.log("Total shares:", totalSupply);
console.log("Share price:", (totalAssets * 1e18) / totalSupply);
```

### 2. Snapshot Comparison

Compare system state before and after tests:
- Total asset changes
- Total share changes
- User balance changes

### 3. Invariant Assertions

Check invariants after critical operations:

```solidity
modifier checkInvariant() {
    _;
    assert(totalSupply == sumOfAllShares);
}
```

## Best Practices

1. **Atomic Operations**: Asset and share updates in same transaction
2. **Event Logging**: Record all share changes
3. **Rounding Protection**: Use up/down rounding to protect different directions
4. **Boundary Checks**: Prevent 0 shares or 0 assets
5. **Test Coverage**: Invariant + fuzz + unit tests

---
**Tags**: #accounting #shares #invariant #testing
