module openmove::acl {
    use std::error;

    use aptos_framework::table::{Self, Table};

    /// @dev When attempting to add/remove a role >= 128.
    const EROLE_NUMBER_TOO_LARGE: u64 = 0;

    /// @dev Maps addresses to `u128`s with each bit representing the presence of (or lack of) each role.
    struct ACL has store {
        permissions: Table<address, u128>
    }

    /// @notice Create a new ACL (access control list).
    public fun new(): ACL {
        ACL { permissions: table::new() }
    }

    /// @notice Check if a member has a role in the ACL.
    public fun has_role(acl: &ACL, member: address, role: u8): bool {
        assert!(role < 128, error::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        table::contains(&acl.permissions, member) && *table::borrow(&acl.permissions, member) & (1 << role) > 0
    }

    /// @notice Set all roles for a member in the ACL.
    /// @param permissions Permissions for a member, represented as a `u128` with each bit representing the presence of (or lack of) each role.
    public fun set_roles(acl: &mut ACL, member: address, permissions: u128) {
        if (table::contains(&acl.permissions, member)) *table::borrow_mut(&mut acl.permissions, member) = permissions
        else table::add(&mut acl.permissions, member, permissions);
    }

    /// @notice Add a role for a member in the ACL.
    public fun add_role(acl: &mut ACL, member: address, role: u8) {
        assert!(role < 128, error::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        if (table::contains(&acl.permissions, member)) {
            let perms = table::borrow_mut(&mut acl.permissions, member);
            *perms = *perms | (1 << role);
        } else {
            table::add(&mut acl.permissions, member, 1 << role);
        }
    }

    /// @notice Revoke a role for a member in the ACL.
    public fun remove_role(acl: &mut ACL, member: address, role: u8) {
        assert!(role < 128, error::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        if (table::contains(&acl.permissions, member)) {
            let perms = table::borrow_mut(&mut acl.permissions, member);
            *perms = *perms - (1 << role);
        }
    }

    #[test_only]
    struct TestACL has key {
        acl: ACL
    }

    #[test(dummy = @0x1234)]
    fun test_end_to_end(dummy: signer) {
        let acl = new();
        add_role(&mut acl, @0x1234, 12);
        add_role(&mut acl, @0x1234, 99);
        add_role(&mut acl, @0x1234, 88);
        add_role(&mut acl, @0x1234, 123);
        add_role(&mut acl, @0x1234, 2);
        add_role(&mut acl, @0x1234, 1);
        remove_role(&mut acl, @0x1234, 2);
        set_roles(&mut acl, @0x5678, (1 << 123) | (1 << 2) | (1 << 1));
        let i = 0;
        while (i < 128) {
            let has = has_role(&acl, @0x1234, i);
            assert!(if (i == 12 || i == 99 || i == 88 || i == 123 || i == 1) has else !has, 0);
            has = has_role(&acl, @0x5678, i);
            assert!(if (i == 123 || i == 2 || i == 1) has else !has, 1);
            i = i + 1;
        };

        // can't drop so must store
        move_to(&dummy, TestACL { acl });
    }
}