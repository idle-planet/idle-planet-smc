module module_addr::idle_planet {
    use std::signer;
    use std::string::{Self, String};
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_std::type_info;
    use module_addr::idle_planet_access;

    // Constants
    const C_MAX_CLAIMABLE_RESOURCE: u64 = 1440;
    const C_U_RATE_DENOMINATOR: u64 = 1000;
    const C_U_RATE_UPDATE_STEP: u128 = 5_000_000;

    // Errors
    const E_PLANET_CREATED: u64 = 1;
    const E_PLANET_NOT_CREATED: u64 = 2;

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

    // Storage
    struct GOLD {}
    struct STONE {}
    struct LUMBER {}
    struct FOOD {}
    struct UniverseResource<phantom CoinType> has key {
        u_rate: u64,
        burn_cap: coin::BurnCapability<CoinType>,
        freeze_cap: coin::FreezeCapability<CoinType>,
        mint_cap: coin::MintCapability<CoinType>,
    }

    struct MyPlanetResource<phantom CoinType> has key {
        last_claim_ts: u64, // seconds
        p_rate: u64,
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

        // Emit event
        event::emit(PlanetCreatedEvent {
            user: user_addr,
        });
    }

    #[view]
    public fun claimable_resource<ResourceType>(user_addr: address): u64 acquires MyPlanetResource, UniverseResource {
        let universe_resource = borrow_global<UniverseResource<ResourceType>>(@module_addr);
        if (!exists<MyPlanetResource<ResourceType>>(user_addr)) {
            return 0;
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
        let reward_coin = coin::mint<ResourceType>(claimable_reward, &universe_resource.mint_cap);
        if (!coin::is_account_registered<ResourceType>(user_addr)) {
            coin::register<ResourceType>(user);
        };
        coin::deposit(user_addr, reward_coin);

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
        let my_planet_resource = borrow_global_mut<MyPlanetResource<FOOD>>(user_addr);
        
        // Calculate metarial need for upgrade
        let material_amount = C_MAX_CLAIMABLE_RESOURCE * my_planet_resource.p_rate * 7;
        let coin = coin::withdraw<GOLD>(user, material_amount);

        // burn material coin
        let universe_resource = borrow_global<UniverseResource<GOLD>>(@module_addr);
        coin::burn(coin, &universe_resource.burn_cap);
        my_planet_resource.p_rate = my_planet_resource.p_rate + 1;

        // Emit event
        let type = type_info::type_of<FOOD>();
        let struct_name = type_info::struct_name(&type);
        event::emit(PlanetUpgradeEvent {
            user: user_addr,
            resource: string::utf8(struct_name),
            p_rate: my_planet_resource.p_rate
        });
    }

    public entry fun upgrade_gold(user: &signer) acquires MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);
        let my_planet_resource = borrow_global_mut<MyPlanetResource<GOLD>>(user_addr);
        
        // Calculate metarial need for upgrade
        let material_amount = C_MAX_CLAIMABLE_RESOURCE * my_planet_resource.p_rate * 7;
        let coin = coin::withdraw<STONE>(user, material_amount);

        // burn material coin
        let universe_resource = borrow_global<UniverseResource<STONE>>(@module_addr);
        coin::burn(coin, &universe_resource.burn_cap);
        my_planet_resource.p_rate = my_planet_resource.p_rate + 1;

        // Emit event
        let type = type_info::type_of<GOLD>();
        let struct_name = type_info::struct_name(&type);
        event::emit(PlanetUpgradeEvent {
            user: user_addr,
            resource: string::utf8(struct_name),
            p_rate: my_planet_resource.p_rate
        });
    }

    public entry fun upgrade_stone(user: &signer) acquires MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);
        let my_planet_resource = borrow_global_mut<MyPlanetResource<STONE>>(user_addr);
        
        // Calculate metarial need for upgrade
        let material_amount = C_MAX_CLAIMABLE_RESOURCE * my_planet_resource.p_rate * 7;
        let coin = coin::withdraw<LUMBER>(user, material_amount);

        // burn material coin
        let universe_resource = borrow_global<UniverseResource<LUMBER>>(@module_addr);
        coin::burn(coin, &universe_resource.burn_cap);
        my_planet_resource.p_rate = my_planet_resource.p_rate + 1;

        // Emit event
        let type = type_info::type_of<STONE>();
        let struct_name = type_info::struct_name(&type);
        event::emit(PlanetUpgradeEvent {
            user: user_addr,
            resource: string::utf8(struct_name),
            p_rate: my_planet_resource.p_rate
        });
    }

    public entry fun upgrade_lumber(user: &signer) acquires MyPlanetResource, UniverseResource {
        let user_addr = signer::address_of(user);
        let my_planet_resource = borrow_global_mut<MyPlanetResource<LUMBER>>(user_addr);
        
        // Calculate metarial need for upgrade
        let material_amount = C_MAX_CLAIMABLE_RESOURCE * my_planet_resource.p_rate * 7;
        let coin = coin::withdraw<FOOD>(user, material_amount);

        // burn material coin
        let universe_resource = borrow_global<UniverseResource<FOOD>>(@module_addr);
        coin::burn(coin, &universe_resource.burn_cap);
        my_planet_resource.p_rate = my_planet_resource.p_rate + 1;

        // Emit event
        let type = type_info::type_of<LUMBER>();
        let struct_name = type_info::struct_name(&type);
        event::emit(PlanetUpgradeEvent {
            user: user_addr,
            resource: string::utf8(struct_name),
            p_rate: my_planet_resource.p_rate
        });
    }
}