# Vault Rounding Issues Research Notes

## Core Problem

Share-based vaults may experience rounding issues during share calculations that can lead to user asset loss.

### Share Calculation Formula

```solidity
shares = (assets * totalSupply) / totalAssets
```

**Issue**: Solidity integer division rounds down, causing precision loss.

## Inflation Attack Scenario

**Attack Steps**:
1. Attacker deposits 1 wei
2. Directly transfers large amount of assets (bypassing deposit)
3. Share price is inflated
4. Subsequent users may receive 0 shares

## Defense Measures

1. **Minimum Share Requirement**
2. **Virtual Assets/Shares**
3. **Initial Share Locking**
4. **Round Up (User-Favorable)**

## Testing Points

- [ ] Inflation attack scenarios
- [ ] Tiny amount deposits
- [ ] Share price monotonicity
- [ ] Asset-liability consistency

---
**Tags**: #rounding #erc4626 #vault
