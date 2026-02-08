// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title RewardStreamsFreezing Test
 * @notice Demonstrates yield freezing due to precision loss in high supply tokens
 * @dev Simplified standalone version of linear interpolation logic
 */
contract RewardStreamsFreezingTest is Test {
    MockRewardStream stream;
    
    // High supply token (simulating 100M total supply with 18 decimals)
    // 100_000_000 * 1e18 = 1e26
    uint256 constant TOTAL_STAKED = 1e26;
    uint256 constant SCALER = 2e19; // From report
    uint256 constant EPOCH_DURATION = 1 weeks; // 604800 seconds
    
    function setUp() public {
        stream = new MockRewardStream(SCALER, EPOCH_DURATION);
        
        // Initialize with huge stake
        stream.setTotalStaked(TOTAL_STAKED);
    }
    
    function testPrecisionLossFreezing() public {
        // 1. Setup small reward (10 Tokens)
        // 10 * 1e6 (USDC decimals)
        uint256 rewardAmount = 10e6;
        
        console.log("=== Parameters ===");
        console.log("Total Staked:", TOTAL_STAKED);
        console.log("Reward Amount:", rewardAmount);
        console.log("Epoch Duration:", EPOCH_DURATION);
        console.log("L2 Block Time: 2 seconds");
        
        // Rate = Amount / Duration
        // Rate = 10e6 / 604800 ≈ 16.5 wei per second
        
        // 2. Simulate L2 fast updates (every 2 seconds)
        uint256 timeDelta = 2; // 2 seconds
        uint256 expectedRewardPerDelta = rewardAmount * timeDelta / EPOCH_DURATION; // ~33 wei
        
        console.log("Reward per 2s delta:", expectedRewardPerDelta);
        
        // 3. Update Accumulator logic
        // acc += delta * SCALER / totalStaked
        // acc += 33 * 2e19 / 1e26
        // acc += 6.6e20 / 1e26
        // acc += 0.0000066 -> 0 (Integer Division)
        
        uint256 storedAccBefore = stream.accumulator();
        stream.update(timeDelta, expectedRewardPerDelta);
        uint256 storedAccAfter = stream.accumulator();
        
        console.log("\n=== After Update ===");
        console.log("Accumulator Before:", storedAccBefore);
        console.log("Accumulator After:", storedAccAfter);
        
        // Vulnerability: Accumulator didn't change
        assertEq(storedAccBefore, storedAccAfter, "VULNERABILITY: Accumulator frozen!");
        
        // 4. Run for extended period (e.g. 1 week of updates)
        // Even if we run this 300,000 times, acc stays 0
        for(uint i=0; i<100; i++) {
            stream.update(timeDelta, expectedRewardPerDelta);
        }
        
        assertEq(stream.accumulator(), 0, "Still zero after 100 updates");
        console.log("VULNERABILITY CONFIRMED: Yield permanently frozen due to precision loss");
    }
}

contract MockRewardStream {
    uint256 public accumulator;
    uint256 public totalStaked;
    uint256 public scaler;
    uint256 public duration;
    
    constructor(uint256 _scaler, uint256 _duration) {
        scaler = _scaler;
        duration = _duration;
    }
    
    function setTotalStaked(uint256 amount) external {
        totalStaked = amount;
    }
    
    function update(uint256 timeDelta, uint256 rewardAmountForPeriod) external {
        // Vulnerable calculation from report:
        // accumulator += uint160(delta * SCALER / EPOCH_DURATION / currentTotalEligible);
        
        // Note: report formula was generic representation. 
        // More specifically: rate * delta * scaler / staked
        // Or: rewardAmountForPeriod * scaler / staked
        
        if (totalStaked == 0) return;
        
        uint256 increase = (rewardAmountForPeriod * scaler) / totalStaked;
        accumulator += increase;
    }
}
