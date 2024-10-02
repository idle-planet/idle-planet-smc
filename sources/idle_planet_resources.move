module module_addr::idle_planet {
    use std::signer;
    use std::string::{Self, String};
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::randomness;
    use aptos_std::type_info;
    use module_addr::idle_planet_access;

    // Constants
    const C_MAX_CLAIMABLE_RESOURCE: u64 = 1440;
    const C_U_RATE_DENOMINATOR: u64 = 1000;
    const C_U_RATE_UPDATE_STEP: u128 = 5_000_000;
    const C_TOTAL_SPIN_RATE: u16 = 25_000;
    const C_MAX_SPIN_TICKETS: u64 = 5;
    const C_RESOURCE_MAX_LEVEL: u64 = 6;

    // Errors
    const E_PLANET_CREATED: u64 = 1;
    const E_PLANET_NOT_CREATED: u64 = 2;
    const E_RESOURCE_MAX_LEVEL: u64 = 3;
    const E_INSUFFICIENT_TICKET: u64 = 4;

    // Events
    #[event]
    struct PlanetCreatedEvent has drop, store {
        user: address,
    }

    #[event]
    struct ClaimResourceEvent has drop, store {
        user: address,
        resource: String,
        amount: u64
    }

    #[event]
    struct PlanetUpgradeEvent has drop, store {
        user: address,
        resource: String,
        p_rate: u64
    }

    #[event]
    struct SpinEvent has drop, store {
        user: address,
        random_value: u16,
        random_result: u8,
    }

    #[event]
    struct AttackEvent has drop, store {
        user: address,
        planet: address,
        resource: String,
    }

    // Storage
    struct GOLD {}
    struct STONE {}
    struct LUMBER {}
    struct FOOD {}
    struct CRYST {}
    struct UniverseResource<phantom CoinType> has key {
        u_rate: u64,
        burn_cap: coin::BurnCapability<CoinType>,
        freeze_cap: coin::FreezeCapability<CoinType>,
        mint_cap: coin::MintCapability<CoinType>,
    }

    struct MyPlanetResource<phantom CoinType> has key {
        last_claim_ts: u64, // seconds
        p_rate: u64, // per minute
    }

    struct MyPlanetSpinTicket has key {
        tickets: u64,
        last_ts: u64, // seconds
        s_rate: u64, // per hour
        attack_tickets: u8,
    }

    fun init_module(resource_account: &signer) {
        let resource_signer = idle_planet_access::get_resource_signer();

        // Initialize coins and metadatas
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<GOLD>(
            &resource_signer,
            string::utf8(b"Idle Planet Gold"),
            string::utf8(b"IPGOLD"),
            0,
            true,
        );
        coin::register<GOLD>(resource_account);
        move_to(resource_account, UniverseResource<GOLD> {
            u_rate: 1,
            burn_cap: burn_cap,
            freeze_cap: freeze_cap,
            mint_cap: mint_cap,
        });

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<LUMBER>(
            &resource_signer,
            string::utf8(b"Idle Planet Lumber"),
            string::utf8(b"IPLUMBER"),
            0,
            true,
        );
        coin::register<LUMBER>(resource_account);
        move_to(resource_account, UniverseResource<LUMBER> {
            u_rate: 1,
            burn_cap: burn_cap,
            freeze_cap: freeze_cap,
            mint_cap: mint_cap,
        });

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<STONE>(
            &resource_signer,
            string::utf8(b"Idle Planet Stone"),
            string::utf8(b"IPSTONE"),
            0,
            true,
        );
        coin::register<STONE>(resource_account);
        move_to(resource_account, UniverseResource<STONE> {
            u_rate: 1,
            burn_cap: burn_cap,
            freeze_cap: freeze_cap,
            mint_cap: mint_cap,
        });

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<FOOD>(
            &resource_signer,
            string::utf8(b"Idle Planet Food"),
            string::utf8(b"IPFOOD"),
            0,
            true,
        );
        coin::register<FOOD>(resource_account);
        move_to(resource_account, UniverseResource<FOOD> {
            u_rate: C_U_RATE_DENOMINATOR,
            burn_cap: burn_cap,
            freeze_cap: freeze_cap,
            mint_cap: mint_cap,
        });

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CRYST>(
            &resource_signer,
            string::utf8(b"Idle Planet Cryst"),
            string::utf8(b"IPCRYST"),
            0,
            true,
        );
        coin::register<CRYST>(resource_account);
        move_to(resource_account, UniverseResource<CRYST> {
            u_rate: 0,
            burn_cap: burn_cap,
            freeze_cap: freeze_cap,
            mint_cap: mint_cap,
        });
    }

    public entry fun create_planet(user: &signer) {
        let user_addr = signer::address_of(user);

        assert!(!exists<MyPlanetResource<GOLD>>(user_addr), E_PLANET_CREATED);

        let now_s = timestamp::now_seconds();

        move_to(user, MyPlanetResource<GOLD> {
            last_claim_ts: now_s,
            p_rate: 1,
        });
        move_to(user, MyPlanetResource<LUMBER> {
            last_claim_ts: now_s,
            p_rate: 1,
        });
        move_to(user, MyPlanetResource<STONE> {
            last_claim_ts: now_s,
            p_rate: 1,
        });
        move_to(user, MyPlanetResource<FOOD> {
            last_claim_ts: now_s,
            p_rate: 1,
        });
        move_to(user, MyPlanetSpinTicket {
            attack_tickets: 0,
            tickets: 3,
            last_ts: now_s,
            s_rate: 1,
        });

        // Emit event
        event::emit(PlanetCreatedEvent {
            user: user_addr,
        });
    }

    #[view]
    public fun claimable_resource<ResourceType>(user_addr: address): u64 acquires MyPlanetResource, UniverseResource {
        let universe_resource = borrow_global<UniverseResource<ResourceType>>(@module_addr);
        if (!exists<MyPlanetResource<ResourceType>>(user_addr)) {
            return 0
        };
        let my_planet_resource = borrow_global<MyPlanetResource<ResourceType>>(user_addr);
        let now_s = timestamp::now_seconds();
        let time_diff_minutes = (now_s - my_planet_resource.last_claim_ts) / 60;

        let calculate_reward = my_planet_resource.p_rate * time_diff_minutes * universe_resource.u_rate / C_U_RATE_DENOMINATOR;
        if (calculate_reward > C_MAX_CLAIMABLE_RESOURCE) {
            C_MAX_CLAIMABLE_RESOURCE
        } else {
            calculate_reward
        }
    }

    #[view]
    public fun current_spin_tickets(user_addr: address): u64 acquires MyPlanetSpinTicket {
        if (!exists<MyPlanetSpinTicket>(user_addr)) {
            return 0
        };
        let my_spin_ticket = borrow_global<MyPlanetSpinTicket>(user_addr);
        let now_s = timestamp::now_seconds();
        let time_diff_hours = (now_s - my_spin_ticket.last_ts) / 3600;

        let my_tickets = my_spin_ticket.s_rate * time_diff_hours + my_spin_ticket.tickets;
        if (my_tickets > C_MAX_SPIN_TICKETS) {
            C_MAX_SPIN_TICKETS
        } else {
            my_tickets
        }
    }
    
    public entry fun claim_resource<ResourceType>(user: &signer) acquires MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);
        assert!(exists<MyPlanetResource<ResourceType>>(user_addr), E_PLANET_NOT_CREATED);
        let claimable_reward = claimable_resource<ResourceType>(user_addr);

        let universe_resource = borrow_global_mut<UniverseResource<ResourceType>>(@module_addr);
        let my_planet_resource = borrow_global_mut<MyPlanetResource<ResourceType>>(user_addr);
        
        // Check total supply and update u_rate
        let maybe_supply = coin::coin_supply<ResourceType>();
        let supply = option::borrow<u128>(&maybe_supply);
        universe_resource.u_rate = (((*supply / C_U_RATE_UPDATE_STEP) + 1) as u64) * C_U_RATE_DENOMINATOR;

        // Update my_planet_resource
        my_planet_resource.last_claim_ts = timestamp::now_seconds();

        // Transfer reward
        mint_resource_internal<ResourceType>(claimable_reward, user);

        // Emit event
        let type = type_info::type_of<ResourceType>();
        let struct_name = type_info::struct_name(&type);
        event::emit(ClaimResourceEvent {
            user: user_addr,
            resource: string::utf8(struct_name),
            amount: claimable_reward
        });
    }

    public entry fun upgrade_food(user: &signer) acquires MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);
        let my_planet_resource = borrow_global<MyPlanetResource<FOOD>>(user_addr);
        
        // Calculate metarial need for upgrade
        let material_amount = C_MAX_CLAIMABLE_RESOURCE * my_planet_resource.p_rate * 7;
        let coin = coin::withdraw<GOLD>(user, material_amount);

        // burn material coin
        let universe_resource = borrow_global<UniverseResource<GOLD>>(@module_addr);
        coin::burn(coin, &universe_resource.burn_cap);
        
        upgrade_resource_internal<FOOD>(user_addr);
    }

    public entry fun upgrade_gold(user: &signer) acquires MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);
        let my_planet_resource = borrow_global<MyPlanetResource<GOLD>>(user_addr);
        
        // Calculate metarial need for upgrade
        let material_amount = C_MAX_CLAIMABLE_RESOURCE * my_planet_resource.p_rate * 7;
        let coin = coin::withdraw<STONE>(user, material_amount);

        // burn material coin
        let universe_resource = borrow_global<UniverseResource<STONE>>(@module_addr);
        coin::burn(coin, &universe_resource.burn_cap);
        
        upgrade_resource_internal<GOLD>(user_addr);
    }

    public entry fun upgrade_stone(user: &signer) acquires MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);
        let my_planet_resource = borrow_global<MyPlanetResource<STONE>>(user_addr);
        
        // Calculate metarial need for upgrade
        let material_amount = C_MAX_CLAIMABLE_RESOURCE * my_planet_resource.p_rate * 7;
        let coin = coin::withdraw<LUMBER>(user, material_amount);

        // burn material coin
        let universe_resource = borrow_global<UniverseResource<LUMBER>>(@module_addr);
        coin::burn(coin, &universe_resource.burn_cap);
        
        upgrade_resource_internal<STONE>(user_addr);
    }

    public entry fun upgrade_lumber(user: &signer) acquires MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);
        let my_planet_resource = borrow_global<MyPlanetResource<LUMBER>>(user_addr);
        
        // Calculate metarial need for upgrade
        let material_amount = C_MAX_CLAIMABLE_RESOURCE * my_planet_resource.p_rate * 7;
        let coin = coin::withdraw<FOOD>(user, material_amount);

        // burn material coin
        let universe_resource = borrow_global<UniverseResource<FOOD>>(@module_addr);
        coin::burn(coin, &universe_resource.burn_cap);

        upgrade_resource_internal<LUMBER>(user_addr);
    }

    #[randomness]
    entry fun spin_wheel(user: &signer) acquires MyPlanetSpinTicket, UniverseResource, MyPlanetResource {
        let random_value = randomness::u16_range(0, C_TOTAL_SPIN_RATE);
        let random_result = handle_spin_result_internal(user, random_value);

        event::emit(SpinEvent {
            user: signer::address_of(user),
            random_value: random_value,
            random_result: random_result
        });
    }

    public entry fun attack_other_planet<ResourceType>(user: &signer, planet: address) acquires MyPlanetSpinTicket, MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);

        // Consume attack ticket
        let my_planet_spin = borrow_global_mut<MyPlanetSpinTicket>(user_addr);
        assert!(my_planet_spin.attack_tickets > 0, E_INSUFFICIENT_TICKET);
        my_planet_spin.attack_tickets = my_planet_spin.attack_tickets - 1;

        // Steal 100% of pending resource amount of the planet
        let attack_reward = claimable_resource<ResourceType>(planet);
        mint_resource_internal<ResourceType>(attack_reward, user);
        // Destroy 100% of pending resource amount of the planet and downgrade one resource level
        let attacked_planet_resource = borrow_global_mut<MyPlanetResource<ResourceType>>(planet);
        attacked_planet_resource.last_claim_ts = timestamp::now_seconds();
        attacked_planet_resource.p_rate = attacked_planet_resource.p_rate + 1;

        let type = type_info::type_of<ResourceType>();
        let struct_name = type_info::struct_name(&type);
        event::emit(AttackEvent {
            user: user_addr,
            planet: planet,
            resource: string::utf8(struct_name),
        });
    }

    fun handle_spin_result_internal(user: &signer, random_value: u16): u8 acquires MyPlanetSpinTicket, UniverseResource, MyPlanetResource {
        let user_addr = signer::address_of(user);

        // Consume ticket
        let my_spin_ticket = borrow_global_mut<MyPlanetSpinTicket>(user_addr);
        assert!(my_spin_ticket.tickets > 0, E_INSUFFICIENT_TICKET);
        my_spin_ticket.tickets = my_spin_ticket.tickets - 1;
        my_spin_ticket.last_ts = timestamp::now_seconds();

        // NO_LUCK
        if (random_value < 8000) {
            return 0
        };
        random_value = random_value - 8000;
        // FREE_GOLD
        if (random_value < 2000) {
            mint_resource_internal<GOLD>(C_MAX_CLAIMABLE_RESOURCE / 10, user);
            return 1
        };
        random_value = random_value - 2000;

        // FREE_LUMBER
        if (random_value < 2000) {
            mint_resource_internal<LUMBER>(C_MAX_CLAIMABLE_RESOURCE / 10, user);
            return 2
        };
        random_value = random_value - 2000;

        // FREE_STONE
        if (random_value < 2000) {
            mint_resource_internal<STONE>(C_MAX_CLAIMABLE_RESOURCE / 10, user);
            return 3
        };
        random_value = random_value - 2000;

        // FREE_FOOD
        if (random_value < 2000) {
            mint_resource_internal<FOOD>(C_MAX_CLAIMABLE_RESOURCE / 10, user);
            return 4
        };
        random_value = random_value - 2000;

        // FREE_CRYST
        if (random_value < 200) {
            mint_resource_internal<CRYST>(1, user);
            return 5
        };
        random_value = random_value - 200;

        // ATTACK_TICKET
        if (random_value < 6000) {
            my_spin_ticket.attack_tickets = my_spin_ticket.attack_tickets + 1;
            return 6
        };
        random_value = random_value - 6000;

        // FREE_UPGRADE_GOLD
        if (random_value < 200) {
            upgrade_resource_internal<GOLD>(user_addr);
            return 7
        };
        random_value = random_value - 200;
        // FREE_UPGRADE_LUMBER
        if (random_value < 200) {
            upgrade_resource_internal<LUMBER>(user_addr);
            return 8
        };
        random_value = random_value - 200;
        // FREE_UPGRADE_STONE
        if (random_value < 200) {
            upgrade_resource_internal<STONE>(user_addr);
            return 9
        };
        random_value = random_value - 200;
        // FREE_UPGRADE_FOOD
        if (random_value < 200) {
            upgrade_resource_internal<FOOD>(user_addr);
            return 10
        };
        // SPIN_TICKET
        my_spin_ticket.tickets = my_spin_ticket.tickets + 1;
        return 11
    }

    fun mint_resource_internal<ResourceType>(amount: u64, receiver: &signer) acquires UniverseResource {
        let user_addr = signer::address_of(receiver);
        let universe_resource = borrow_global<UniverseResource<ResourceType>>(@module_addr);
        let reward_coin = coin::mint<ResourceType>(amount, &universe_resource.mint_cap);
        if (!coin::is_account_registered<ResourceType>(user_addr)) {
            coin::register<ResourceType>(receiver);
        };
        coin::deposit(user_addr, reward_coin);
    }

    fun upgrade_resource_internal<ResourceType>(user_addr: address) acquires MyPlanetResource {
        let my_planet_resource = borrow_global_mut<MyPlanetResource<ResourceType>>(user_addr);
        assert!(my_planet_resource.p_rate < C_RESOURCE_MAX_LEVEL, E_RESOURCE_MAX_LEVEL);

        my_planet_resource.p_rate = my_planet_resource.p_rate + 1;
        // Emit event
        let type = type_info::type_of<ResourceType>();
        let struct_name = type_info::struct_name(&type);
        event::emit(PlanetUpgradeEvent {
            user: user_addr,
            resource: string::utf8(struct_name),
            p_rate: my_planet_resource.p_rate
        });
    }
}
