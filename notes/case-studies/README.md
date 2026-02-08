# DeFi Protocol Vulnerability Case Studies Index

This directory contains desensitized real DeFi protocol vulnerability case studies for learning and research purposes. All cases have been fully anonymized, removing project names, platform information, and other sensitive data.

## 📚 Case List

### 1. [Silent Vault Deposit Failure](./vault-silent-failure.md)
**Severity**: High  
**Vulnerability Type**: Fund Loss / Error Handling Flaw  
**Key Takeaways**:
- Importance of error handling
- State consistency
- Balance calculation risks
- Inflation attack protection

**Tags**: `#vault` `#silent-failure` `#zero-shares` `#inflation-attack`

---

### 2. [Orderbook Collateral Lock](./collateral-lock.md)
**Severity**: High  
**Vulnerability Type**: Fund Locking / Logic Error  
**Key Takeaways**:
- Price improvement handling
- Mode consistency
- Balance management
- Test coverage

**Tags**: `#orderbook` `#collateral-lock` `#price-improvement` `#dex`

---

### 3. [Lending Isolation Mode Bypass](./lending-isolation-bypass.md)
**Severity**: Critical  
**Vulnerability Type**: Debt Ceiling Bypass / Precision Loss  
**Key Takeaways**:
- Precision loss risks
- Accounting consistency
- Invariant protection
- Small transaction handling

**Tags**: `#lending` `#isolation-mode` `#precision-loss` `#debt-ceiling-bypass`

---

### 4. [Registry Permission Bypass](./registry-permission-bypass.md)
**Severity**: Critical  
**Vulnerability Type**: Permission Bypass / NFT Theft  
**Key Takeaways**:
- Permission design flaws
- Expiry handling risks
- Fuse mechanisms
- Time-lock risks

**Tags**: `#registry` `#permission-bypass` `#nft-theft` `#expiry-exploit`

---

### 5. [Collateral Capacity Limit Bypass](./collateral-capacity-bypass.md)
**Severity**: High  
**Vulnerability Type**: Capacity Limit Bypass / Uncontrolled Risk Exposure  
**Key Takeaways**:
- Importance of capacity limits
- Consistency checks
- Risk management
- Code path coverage

**Tags**: `#collateral-capacity` `#supply-cap` `#risk-management` `#solvency`

---

### 6. [Reward Distribution Precision Loss](./reward-freezing.md)
**Severity**: High  
**Vulnerability Type**: Precision Loss / Fund Freezing  
**Key Takeaways**:
- Precision loss risks
- L2 specifics
- Token supply impact
- Accumulator design

**Tags**: `#reward-streams` `#precision-loss` `#yield-freezing` `#l2`

---

### 7. [Fee-on-Transfer Token Issue](./fee-on-transfer-issue.md)
**Severity**: Medium  
**Vulnerability Type**: Accounting Inconsistency / Token Compatibility  
**Key Takeaways**:
- Token compatibility
- Balance checking
- Accounting consistency
- Special token types

**Tags**: `#fee-on-transfer` `#accounting` `#token-compatibility`

---

### 8. [Oracle De-peg DoS](./oracle-depeg-dos.md)
**Severity**: Medium  
**Vulnerability Type**: Denial of Service / Oracle Dependency  
**Key Takeaways**:
- Oracle trust
- Exception handling
- Liquidation priority
- Range check risks

**Tags**: `#oracle` `#depeg` `#dos` `#circuit-breaker`

---

## 🎯 Classification by Vulnerability Type

### Fund Loss
- [Silent Vault Deposit Failure](./vault-silent-failure.md)
- [Orderbook Collateral Lock](./collateral-lock.md)
- [Reward Distribution Precision Loss](./reward-freezing.md)

### Precision Loss
- [Lending Isolation Mode Bypass](./lending-isolation-bypass.md)
- [Reward Distribution Precision Loss](./reward-freezing.md)

### Permission Control
- [Registry Permission Bypass](./registry-permission-bypass.md)

### Risk Management
- [Collateral Capacity Limit Bypass](./collateral-capacity-bypass.md)

### Token Compatibility
- [Fee-on-Transfer Token Issue](./fee-on-transfer-issue.md)

### Oracle Related
- [Oracle De-peg DoS](./oracle-depeg-dos.md)

---

## 🔍 Classification by Protocol Type

### Vault / Treasury
- [Silent Vault Deposit Failure](./vault-silent-failure.md)

### DEX / Exchange
- [Orderbook Collateral Lock](./collateral-lock.md)

### Lending Protocol
- [Lending Isolation Mode Bypass](./lending-isolation-bypass.md)
- [Collateral Capacity Limit Bypass](./collateral-capacity-bypass.md)
- [Fee-on-Transfer Token Issue](./fee-on-transfer-issue.md)
- [Oracle De-peg DoS](./oracle-depeg-dos.md)

### Registry / NFT
- [Registry Permission Bypass](./registry-permission-bypass.md)

### Reward Distribution
- [Reward Distribution Precision Loss](./reward-freezing.md)

---

## 📖 Suggested Learning Paths

### Beginner Path
1. [Fee-on-Transfer Token Issue](./fee-on-transfer-issue.md) - Understanding token compatibility
2. [Silent Vault Deposit Failure](./vault-silent-failure.md) - Learning error handling
3. [Oracle De-peg DoS](./oracle-depeg-dos.md) - Understanding oracle risks

### Intermediate Path
1. [Lending Isolation Mode Bypass](./lending-isolation-bypass.md) - Precision loss attacks
2. [Orderbook Collateral Lock](./collateral-lock.md) - Complex logic vulnerabilities
3. [Reward Distribution Precision Loss](./reward-freezing.md) - L2 specifics

### Advanced Path
1. [Registry Permission Bypass](./registry-permission-bypass.md) - Permission system design
2. [Collateral Capacity Limit Bypass](./collateral-capacity-bypass.md) - Risk management

---

## 🛡️ Universal Security Principles

Key security principles extracted from these cases:

### 1. Error Handling
- ✅ Never silently ignore errors that may lead to fund loss
- ✅ On failure, should revert rather than continue execution

### 2. Precision Handling
- ✅ Be aware of integer division rounding issues
- ✅ For high-frequency operations, consider precision loss accumulation
- ✅ Use remainder tracking or minimum intervals

### 3. State Consistency
- ✅ Fund transfers and state updates must be atomic
- ✅ Recorded amounts must match actual amounts
- ✅ Maintain critical invariants

### 4. Code Path Coverage
- ✅ All paths modifying critical state must have same checks
- ✅ Different modes should have consistent logic
- ✅ Test all boundary cases

### 5. External Dependencies
- ✅ If trusting oracle, must accept its data
- ✅ Handle special token types (fee-on-transfer, rebase, etc.)
- ✅ Degrade during anomalies rather than completely stop

---

## 📝 Usage Instructions

### How to Use These Cases

1. **Learn**: Read cases to understand vulnerability principles
2. **Practice**: Run PoC code to verify vulnerabilities
3. **Reflect**: Think about how to avoid similar issues in your code
4. **Apply**: Apply learned principles to auditing and development

### Related Resources

- [Vault Rounding Issues](../vault-rounding.md)
- [Liquidation Boundary Analysis](../liquidation-boundaries.md)
- [Share Accounting System](../share-accounting.md)

---

## ⚠️ Disclaimer

All cases have been fully anonymized and are for educational purposes only. No real project information, platform names, or confidential disclosures are included.

---

**Last Updated**: 2026-02-08
