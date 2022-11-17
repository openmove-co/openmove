module openmove::locked_coins {
    use aptos_framework::account::{Self};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use std::error;
    use std::signer;

    /// Represents a lock of coins until some specified unlock time. Afterward, the recipient can claim the coins.
    struct Lock<phantom CoinType> has store {
        coins: Coin<CoinType>,
        unlock_time_secs: u64,
    }

    /// Holder for a map from recipients => locks.
    /// There can be at most one lock per recipient.
    struct Locks<phantom CoinType> has key {
        locks: Table<address, Lock<CoinType>>,
        claim_events: EventHandle<ClaimEvent>,
    }

    /// Event emitted when a recipient claims unlocked coins.
    struct ClaimEvent has drop, store {
        recipient: address,
        amount: u64,
        claimed_time_secs: u64,
    }

    /// No locked coins found to claim.
    const ELOCK_NOT_FOUND: u64 = 1;
    /// Lockup has not expired yet.
    const ELOCKUP_HAS_NOT_EXPIRED: u64 = 2;
    /// Can only create one active lock per recipient at once.
    const ELOCK_ALREADY_EXISTS: u64 = 3;

    /// `Sponsor` can add locked coins for `recipient` with given unlock timestamp (in seconds).
    /// There's no restriction on unlock timestamp so sponsors could technically add coins for an unlocked time in the
    /// past, which means the coins are immediately unlocked.
    public entry fun add_locked_coins<CoinType>(
        sponsor: &signer, recipient: address, amount: u64, unlock_time_secs: u64) acquires Locks {
        let sponsor_address = signer::address_of(sponsor);
        if (!exists<Locks<CoinType>>(sponsor_address)) {
            move_to(sponsor, Locks {
                locks: table::new<address, Lock<CoinType>>(),
                claim_events: account::new_event_handle<ClaimEvent>(sponsor),
            })
        };

        let locks = borrow_global_mut<Locks<CoinType>>(sponsor_address);
        let coins = coin::withdraw<CoinType>(sponsor, amount);
        assert!(!table::contains(&locks.locks, recipient), error::already_exists(ELOCK_ALREADY_EXISTS));
        table::add(&mut locks.locks, recipient, Lock<CoinType> { coins, unlock_time_secs });
    }

    /// Recipient can claim coins that are fully unlocked (unlock time has passed).
    /// To claim, `recipient` would need the sponsor's address. In the case where each sponsor always deploys this
    /// module anew, it'd just be the module's hosted account address.
    public entry fun claim<CoinType>(recipient: &signer, sponsor: address) acquires Locks {
        assert!(exists<Locks<CoinType>>(sponsor), error::not_found(ELOCK_NOT_FOUND));
        let locks = borrow_global_mut<Locks<CoinType>>(sponsor);
        let recipient_address = signer::address_of(recipient);
        assert!(table::contains(&locks.locks, recipient_address), error::not_found(ELOCK_NOT_FOUND));
        let lock = table::borrow_mut(&mut locks.locks, recipient_address);
        let now_secs = timestamp::now_seconds();
        assert!(now_secs >= lock.unlock_time_secs, error::invalid_state(ELOCKUP_HAS_NOT_EXPIRED));
        // Delete the lock entry both to keep records clean and keep storage usage minimal.
        let Lock { coins, unlock_time_secs: _ } = table::remove(&mut locks.locks, recipient_address);
        let amount = coin::value(&coins);
        // This would fail if the recipient account is not registered to receive CoinType.
        coin::deposit(recipient_address, coins);

        event::emit_event(&mut locks.claim_events, ClaimEvent {
            recipient: recipient_address,
            amount,
            claimed_time_secs: now_secs,
        });
    }

    #[test_only]
    use std::string;
    #[test_only]
    use aptos_framework::coin::BurnCapability;
    #[test_only]
    use aptos_framework::aptos_coin::AptosCoin;

    #[test_only]
    fun setup(aptos_framework: &signer, sponsor: &signer, recipient: &signer): BurnCapability<AptosCoin> {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<AptosCoin>(
            aptos_framework,
            string::utf8(b"TC"),
            string::utf8(b"TC"),
            8,
            false,
        );
        account::create_account_for_test(signer::address_of(sponsor));
        account::create_account_for_test(signer::address_of(recipient));
        coin::register<AptosCoin>(sponsor);
        coin::register<AptosCoin>(recipient);
        let coins = coin::mint<AptosCoin>(1000, &mint_cap);
        coin::deposit(signer::address_of(sponsor), coins);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_freeze_cap(freeze_cap);
        burn_cap
    }

    #[test(aptos_framework = @0x1, sponsor = @0x123, recipient = @0x234)]
    public entry fun test_recipient_can_claim_coins(
        aptos_framework: &signer, sponsor: &signer, recipient: &signer) acquires Locks {
        let burn_cap = setup(aptos_framework, sponsor, recipient);
        let recipient_addr = signer::address_of(recipient);
        add_locked_coins<AptosCoin>(sponsor, recipient_addr, 1000, 1000);
        timestamp::fast_forward_seconds(1000);
        claim<AptosCoin>(recipient, signer::address_of(sponsor));
        assert!(coin::balance<AptosCoin>(recipient_addr) == 1000, 0);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(aptos_framework = @0x1, sponsor = @0x123, recipient = @0x234)]
    #[expected_failure(abort_code = 0x30002)]
    public entry fun test_recipient_cannot_claim_coins_if_lockup_has_not_expired(
        aptos_framework: &signer, sponsor: &signer, recipient: &signer) acquires Locks {
        let burn_cap = setup(aptos_framework, sponsor, recipient);
        let recipient_addr = signer::address_of(recipient);
        add_locked_coins<AptosCoin>(sponsor, recipient_addr, 1000, 1000);
        timestamp::fast_forward_seconds(500);
        claim<AptosCoin>(recipient, signer::address_of(sponsor));
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(aptos_framework = @0x1, sponsor = @0x123, recipient = @0x234)]
    #[expected_failure(abort_code = 0x60001)]
    public entry fun test_recipient_cannot_claim_twice(
        aptos_framework: &signer, sponsor: &signer, recipient: &signer) acquires Locks {
        let burn_cap = setup(aptos_framework, sponsor, recipient);
        let recipient_addr = signer::address_of(recipient);
        add_locked_coins<AptosCoin>(sponsor, recipient_addr, 1000, 1000);
        timestamp::fast_forward_seconds(1000);
        claim<AptosCoin>(recipient, signer::address_of(sponsor));
        claim<AptosCoin>(recipient, signer::address_of(sponsor));
        coin::destroy_burn_cap(burn_cap);
    }
}