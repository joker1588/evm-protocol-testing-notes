# Case Study PoC Tests

This directory contains desensitized Proof of Concept (PoC) tests extracted from real vulnerability reports. All tests are standalone and can run without mainnet forks.

## Available Tests

### 1. [VaultSilentFailure.t.sol](./VaultSilentFailure.t.sol)
**Severity**: High  
**Vulnerability**: Silent failure in vault deposits leading to fund loss  
**Description**: Demonstrates how a vault that returns 0 shares instead of reverting (or handles it silently) allows an attacker to steal user funds that get stuck in a peripheral contract.  
**Command**: `forge test --match-contract VaultSilentFailureTest -vv`

### 2. [OrderbookCollateralLock.t.sol](./OrderbookCollateralLock.t.sol)
**Severity**: High  
**Vulnerability**: Funds locking during price improvement  
**Description**: Shows how surplus collateral is permanently locked when an order manages to execute at a better price than the limit price, but the system fails to unlock the difference.  
**Command**: `forge test --match-contract OrderbookCollateralLockTest -vv`

### 3. [LendingIsolationBypass.t.sol](./LendingIsolationBypass.t.sol)
**Severity**: Critical  
**Vulnerability**: Debt ceiling bypass via precision loss  
**Description**: Demonstrates how rounding errors in debt accounting allow an attacker to borrow funds without increasing the recorded debt, effectively bypassing the isolation mode debt ceiling.  
**Command**: `forge test --match-contract LendingIsolationBypassTest -vv`

### 4. [RegistryPermissionBypass.t.sol](./RegistryPermissionBypass.t.sol)
**Severity**: Critical  
**Vulnerability**: Permission bypass via expiry handling  
**Description**: Shows how a parent domain owner can hijack a trustless subdomain by waiting for it to expire, exploiting a check that is skipped for expired domains.  
**Command**: `forge test --match-contract RegistryPermissionBypassTest -vv`

### 5. [CollateralCapacityBypass.t.sol](./CollateralCapacityBypass.t.sol)
**Severity**: High  
**Vulnerability**: Collateral capacity limit bypass  
**Description**: Demonstrates how `addCollateral` function bypasses capacity checks that `createLoan` correctly enforces.  
**Command**: `forge test --match-contract CollateralCapacityBypassTest -vv`

### 6. [RewardStreamsFreezing.t.sol](./RewardStreamsFreezing.t.sol)
**Severity**: High  
**Vulnerability**: Yield freezing due to precision loss  
**Description**: Shows how high-frequency updates combined with large token supplies cause reward accumulation to round down to zero, permanently freezing yields.  
**Command**: `forge test --match-contract RewardStreamsFreezingTest -vv`

### 7. [FeeOnTransferIssue.t.sol](./FeeOnTransferIssue.t.sol)
**Severity**: Medium  
**Vulnerability**: Accounting inconsistency with fee-on-transfer tokens  
**Description**: Shows how lending pools that don't check actual received amounts create accounting deficits.  
**Command**: `forge test --match-contract FeeOnTransferIssueTest -vv`

### 8. [OracleDepegDoS.t.sol](./OracleDepegDoS.t.sol)
**Severity**: Medium  
**Vulnerability**: Oracle depeg causing denial of service  
**Description**: Demonstrates how overly strict price range checks cause protocol freeze during depeg events.  
**Command**: `forge test --match-contract OracleDepegDoSTest -vv`

---

## Running Validation

Run all tests to confirm vulnerability reproduction:

```bash
# Run all tests
forge test --match-path "test/case-studies/*.sol" -vv

# Expected: All tests PASS (confirming the vulnerability exists)
```

## Security Note

⚠️ **Educational Purpose Only**

These tests are for educational purposes to understand vulnerability patterns. Never deploy vulnerable code to production. All code has been desensitized and simplified.

---

**Last Updated**: 2026-02-08
