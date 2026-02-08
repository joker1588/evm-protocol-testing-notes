# Case Study: Collateral Capacity Limit Bypass

## Vulnerability Type
**Severity**: High  
**Category**: Capacity Limit Bypass / Uncontrolled Risk Exposure

## Summary

`GenericGearingToken` contract enforces `collateralCapacity` to limit total amount of specific collateral tokens protocol is willing to accept. This acts as "Debt Ceiling" or "Exposure Limit" for that asset.

However, `addCollateral` function (for adding collateral to existing loans) lacks capacity check, allowing users to deposit collateral exceeding configured `collateralCapacity`. While `issueFt` (new loan creation) correctly enforces this limit, `addCollateral` doesn't.

## Vulnerability Details

### Root Cause

In `_checkBeforeMint` (called by `issueFt`), capacity is verified:

```solidity
function _checkBeforeMint(uint128, bytes memory collateralData) internal virtual override {
    // Correctly checks if current balance + new amount exceeds capacity
    if (IERC20(_config.collateral).balanceOf(address(this)) + _decodeAmount(collateralData) > collateralCapacity) {
        revert CollateralCapacityExceeded();
    }
}
```

However, in `_addCollateral` (for existing loans), this check is entirely missing.

### Risk Amplification

Without capacity check, protocol cannot enforce intended debt ceiling for this asset. Any subsequent borrowing, liquidation, or risk calculation assumes cap holds, potentially leading to massive undercollateralization if collateral asset fails or de-pegs.

## Impact

In DeFi lending, **Collateral Capacity** (or Supply Caps) is primary defense against:

1. **Infinite Mint Attacks**: If collateral token has infinite mint vulnerability or malicious issuer, cap limits protocol's loss to cap amount
2. **Illiquidity / De-peg Risk**: Protocols limit exposure to volatile/illiquid assets (e.g., "Max $1M exposure to Token X")

### Exploit Chain

1. **Bypass**: Attacker bypasses $1M cap for "RiskyToken" and deposits $100M worth
2. **Borrow**: Attacker borrows $80M worth of stablecoins (assuming 80% LTV)
3. **Insolvency Event**: "RiskyToken" price crashes by 50%
   - **Intended Outcome**: Protocol holds $1M RiskyToken (now $0.5M), owes $0.8M stablecoin. Loss = $0.3M
   - **Actual Outcome**: Protocol holds $100M RiskyToken (now $50M), owes $80M stablecoin. Loss = $30M

**Conclusion**: Vulnerability magnifies protocol's insolvency risk from "Governance Controlled Loss" to "Unbounded Loss".

## Proof of Concept

### Test Code

```solidity
function testCollateralCapacityBypass() public {
    vm.startPrank(user);
    
    uint256 initialCollateral = 100e18;
    uint128 debtAmount = 50e18;
    
    (,, IGearingToken gt,,) = market.tokens();
    collateral.approve(address(gt), type(uint256).max);
    
    // 1. Mint valid loan (within capacity)
    // Capacity: 1000, Used: 100. OK.
    bytes memory collateralData = abi.encode(initialCollateral);
    (uint256 loanId, ) = market.issueFt(user, debtAmount, collateralData);
    
    assertEq(collateral.balanceOf(address(gt)), initialCollateral);
    
    // 2. Bypass capacity via addCollateral
    // Add 2000 tokens. Total will be 2100. Capacity is 1000.
    // This SHOULD fail if checked, but will pass due to bug.
    uint256 addAmount = 2000e18;
    bytes memory addData = abi.encode(addAmount);
    
    console.log("Current Collateral:", initialCollateral);
    console.log("Adding Collateral:", addAmount);
    console.log("Max Capacity:", COLLATERAL_CAPACITY);
    
    // This call SUCCESSFULLY executes despite exceeding capacity
    gt.addCollateral(loanId, addData);
    
    // 3. Verify limit exceeded
    (,, bytes memory newLoanColData) = gt.loanInfo(loanId);
    uint256 newStoredCollateral = abi.decode(newLoanColData, (uint256));
    
    console.log("New Collateral:", newStoredCollateral);
    
    assertGt(newStoredCollateral, COLLATERAL_CAPACITY, "Collateral Capacity Bypassed!");
    
    // 4. Verify can borrow against excess collateral
    uint128 borrowAmount = 1000e18;
    market.issueFtByExistedGt(user, borrowAmount, loanId);
    
    vm.stopPrank();
}
```

## Remediation

Apply capacity check in `_addCollateral`.

```solidity
function _addCollateral(LoanInfo memory loan, bytes memory collateralData)
    internal
    virtual
    override
    returns (bytes memory)
{
    // FIX: Add Capacity Check
    // Note: In AbstractGearingTokenV2.addCollateral, _transferCollateralFrom executes
    // BEFORE _addCollateral. Therefore, balanceOf(address(this)) already includes
    // newly deposited amount.
    if (IERC20(_config.collateral).balanceOf(address(this)) > collateralCapacity) {
        revert CollateralCapacityExceeded();
    }
    
    uint256 amount = _decodeAmount(loan.collateralData) + _decodeAmount(collateralData);
    return _encodeAmount(amount);
}
```

## Key Takeaways

1. **Importance of Capacity Limits**: Supply caps are critical mechanism for controlling protocol risk exposure
2. **Consistency Checks**: All paths modifying collateral must enforce same limits
3. **Risk Management**: Bypassing capacity limits directly undermines protocol's solvency guarantees
4. **Code Path Coverage**: Must review all functions that can modify restricted resources

## Related Concepts

- Collateral Capacity (Supply Cap)
- Risk Exposure Management
- Loan-to-Value (LTV)
- Protocol Solvency

---

**Tags**: #collateral-capacity #supply-cap #risk-management #solvency
