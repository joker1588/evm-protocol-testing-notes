# Case Study: Fee-on-Transfer Token Accounting Issue

## Vulnerability Type
**Severity**: Medium  
**Category**: Accounting Inconsistency / Token Compatibility

## Summary

Lending pools have accounting inconsistency when handling Fee-on-Transfer tokens. When users deposit or borrow Fee-on-Transfer tokens, protocol records amount doesn't match actual received amount, leading to accounting errors and potential fund loss.

## Vulnerability Details

### Fee-on-Transfer Token Characteristics

Some ERC20 tokens charge fees on transfer (e.g., transfer 100 tokens, recipient receives only 98 tokens, 2 tokens as fee).

### Problematic Code Pattern

```solidity
function deposit(uint256 amount) external {
    // Record user deposited amount
    balances[msg.sender] += amount;
    
    // Actual transfer (may be less than amount)
    token.transferFrom(msg.sender, address(this), amount);
    
    // Issue: balances records amount, but contract actually received less than amount
}
```

### Accounting Inconsistency

- **Recorded balance**: 100 tokens
- **Actual balance**: 98 tokens
- **Difference**: 2 tokens (inflated)

When multiple users have this inflation, protocol's total liabilities exceed actual assets, causing last withdrawer to fail.

## Impact

1. **Protocol Insolvency**: Recorded liabilities > actual assets
2. **Last Withdrawer Loss**: Last user attempting withdrawal fails due to insufficient balance
3. **Exploitable**: Attacker can amplify this through multiple small deposits/withdrawals

## Proof of Concept

### Test Code

```solidity
contract FeeOnTransferToken is ERC20 {
    uint256 public constant FEE_PERCENT = 2; // 2% fee
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = amount * FEE_PERCENT / 100;
        uint256 actualAmount = amount - fee;
        
        super.transfer(to, actualAmount);
        super.transfer(address(0), fee); // Burn fee
        
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = amount * FEE_PERCENT / 100;
        uint256 actualAmount = amount - fee;
        
        super.transferFrom(from, to, actualAmount);
        super.transferFrom(from, address(0), fee);
        
        return true;
    }
}

function testFeeOnTransferAccounting() public {
    FeeOnTransferToken feeToken = new FeeOnTransferToken();
    GenericLendingPool pool = new GenericLendingPool(address(feeToken));
    
    // Alice deposits 100 tokens
    feeToken.mint(alice, 100e18);
    vm.startPrank(alice);
    feeToken.approve(address(pool), 100e18);
    pool.deposit(100e18);
    vm.stopPrank();
    
    // Check accounting
    uint256 aliceBalance = pool.balanceOf(alice);
    uint256 poolActualBalance = feeToken.balanceOf(address(pool));
    
    console.log("Alice recorded balance:", aliceBalance);
    console.log("Pool actual balance:", poolActualBalance);
    
    // Alice recorded: 100
    // Pool actual: 98 (due to 2% fee)
    assertEq(aliceBalance, 100e18);
    assertEq(poolActualBalance, 98e18);
    
    // Bob also deposits 100
    feeToken.mint(bob, 100e18);
    vm.startPrank(bob);
    feeToken.approve(address(pool), 100e18);
    pool.deposit(100e18);
    vm.stopPrank();
    
    // Total recorded: 200
    // Total actual: 196
    uint256 totalRecorded = pool.totalSupply();
    uint256 totalActual = feeToken.balanceOf(address(pool));
    
    assertEq(totalRecorded, 200e18);
    assertEq(totalActual, 196e18);
    
    // Alice tries to withdraw all
    vm.prank(alice);
    vm.expectRevert(); // Will fail, not enough tokens in pool
    pool.withdraw(100e18);
}
```

## Remediation

### Solution 1: Check Actual Received Amount

```solidity
function deposit(uint256 amount) external {
    uint256 balanceBefore = token.balanceOf(address(this));
    token.transferFrom(msg.sender, address(this), amount);
    uint256 balanceAfter = token.balanceOf(address(this));
    
    uint256 actualReceived = balanceAfter - balanceBefore;
    balances[msg.sender] += actualReceived; // Use actual received amount
}
```

### Solution 2: Disallow Fee-on-Transfer Tokens

```solidity
function deposit(uint256 amount) external {
    uint256 balanceBefore = token.balanceOf(address(this));
    token.transferFrom(msg.sender, address(this), amount);
    uint256 balanceAfter = token.balanceOf(address(this));
    
    require(balanceAfter - balanceBefore == amount, "Fee-on-transfer not supported");
    balances[msg.sender] += amount;
}
```

## Key Takeaways

1. **Token Compatibility**: Not all ERC20 tokens are standard
2. **Balance Checking**: Check balance changes before/after transfers
3. **Accounting Consistency**: Recorded amounts must match actual amounts
4. **Special Token Types**:
   - Fee-on-transfer tokens
   - Rebase tokens
   - Multi-address tokens

## Related Concepts

- ERC20 token variants
- Accounting invariants
- Balance tracking
- Token whitelisting

---

**Tags**: #fee-on-transfer #accounting #token-compatibility
