# Case Study: Silent Vault Deposit Failure Leading to Fund Loss

## Vulnerability Type
**Severity**: High  
**Category**: Fund Loss / Error Handling Flaw

## Summary

A critical vulnerability exists in the `GenericFundsLib.depositAssets` function, which silently catches and ignores `ZeroShares` errors during asset deposits. This behavior, combined with `MockSwap`'s mechanism of calculating input amounts based on current contract balance, leads to severe consequences: when a user's deposit operation fails due to excessively high share prices (e.g., from an inflation attack), their assets are transferred to the `MockSwap` contract but fail to deposit into the underlying Vault. Since the deposit failure is ignored, users receive no credit, and these assets are effectively "stranded" in the `MockSwap` contract, where they can be claimed by subsequent attackers through new deposit operations.

## Vulnerability Details

### Problematic Code

In `GenericFundsLib.sol`'s `depositAssets` function:

```solidity
function depositAssets(...) internal returns (uint256) {
    // ... (debt repayment logic) ...

    if (amount > 0) {
        try IVault(supplyVault).deposit(amount, userAccount) {}
        catch (bytes memory reason) {
            // Vulnerability: Catches ZeroShares error but doesn't revert, sets deposit amount to 0 and continues
            if (!(keccak256(reason) == keccak256(abi.encodePacked(E_ZeroShares.selector))
                    || keccak256(reason) == keccak256(abi.encodePacked(ZeroShares.selector)))) 
                revert DepositFailure(reason);
            amount = 0; 
        }
        deposited += amount;
    }
    return deposited;
}
```

### Trigger Conditions

When `deposit` fails due to `ZeroShares` (i.e., deposit amount too small to mint 1 share, typically occurring when Vault suffers inflation attack causing extremely high share prices), `amount` is reset to 0, but the transaction doesn't revert.

In `MockSwap.sol` and `SwapLib.sol`, the swap logic first transfers user funds into `MockSwap`, then attempts deposit. If deposit silently fails, funds remain stuck in `MockSwap` contract balance. Subsequent `SwapLib.finish` or next swap operation recalculates balance, allowing attackers to exploit these stranded funds.

## Impact

- **Permanent Fund Loss**: Victim's funds are transferred but not accounted for, resulting in complete loss
- **Fund Theft Risk**: Attackers can send sufficient assets (exceeding `ZeroShares` threshold) to successfully deposit, thereby utilizing victim's stranded funds in the contract for swaps and profiting
- **Inflation Attack Vector**: Attackers can deliberately donate assets to Vault to inflate share price, artificially creating conditions that trigger `ZeroShares` errors, targeting small traders

## Attack Flow

### Test Environment Configuration
- **Network**: Local Testnet
- **Vault**:
  - vTOKEN: Standard Vault implementation
  - vASSET: Uses `MockVault` to simulate high share price state after inflation attack (deposits < 1000 ASSET trigger `ZeroShares`)

### Attack Steps

**1. Victim Operation**: Attempts to swap 500 ASSET

- Funds (500 ASSET) transferred to `MockSwap`
- `deposit` operation triggers `ZeroShares` due to amount being less than Mock's 1000 ASSET threshold
- `GenericFundsLib` ignores error, swap completes with 0 input
- **Result**: Victim loses 500 ASSET, funds stranded in contract

**2. Attacker Operation**: Sends 2000 ASSET for swap

- Funds (2000 ASSET) transferred to `MockSwap`
- Contract current balance is 2500 ASSET (victim 500 + attacker 2000)
- `deposit` operation succeeds (2500 > 1000)
- Attacker receives full credit for 2500 ASSET
- Swap executes, attacker receives corresponding value of output tokens (TOKEN)

### Test Log Output

```
[PASS] test_ZeroShares_Stealing() (gas: 1436600)
Logs:
  vTOKEN Vault: 0x1
  Mock vASSET: 0x2
  MockSwap System Deployed
  Victim swap finished (Funds stuck)
  Pool ASSET Balance (Stuck): 500000000
  Expected Output: 826446280991735537
  Attacker TOKEN Gained: 826446280991735537
```

Test confirms attacker successfully exploited victim's 500 ASSET to gain additional TOKEN.

## Remediation

### Core Principle

Never silently swallow deposit failure errors. If swap logic depends on successful deposit (i.e., `amount > 0`), deposit failure must revert transaction to protect user funds.

### Code Modification Suggestion

Remove special exemption logic for `ZeroShares`, let all deposit errors cause revert.

```diff
        try IVault(supplyVault).deposit(amount, userAccount) {}
        catch (bytes memory reason) {
-           if (!(keccak256(reason) == keccak256(abi.encodePacked(E_ZeroShares.selector))
-                   || keccak256(reason) == keccak256(abi.encodePacked(ZeroShares.selector)))) 
-               revert DepositFailure(reason);
-           amount = 0;
+           revert DepositFailure(reason);
        }
```

### Alternative Solution

If error catching is truly needed, ensure user funds aren't deducted, but this is difficult to implement in current swap architecture, so direct revert is the safest choice.

## Key Takeaways

1. **Importance of Error Handling**: Never silently ignore errors that may lead to fund loss
2. **State Consistency**: Fund transfers and state updates must be atomic
3. **Balance Calculation Risks**: Calculations based on contract balance are susceptible to manipulation
4. **Inflation Attack Protection**: Vault implementations must guard against share price manipulation

## Related Cases

Refer to `vault-rounding.md` for detailed analysis of inflation attacks.

---

**Tags**: #vault #silent-failure #zero-shares #inflation-attack #funds-loss
