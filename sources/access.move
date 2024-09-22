module module_addr::idle_planet_access {
    use aptos_framework::account;
    use aptos_framework::resource_account;
    use aptos_framework::code;
    use aptos_framework::signer;

    friend module_addr::idle_planet;

    // Error
    const ERROR_NOT_ADMIN: u64 = 1;

    struct AccessControl has key {
        signer_cap: account::SignerCapability,
        admin: address,
    }

    fun init_module(resource_signer: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(resource_signer, @admin);
        move_to(resource_signer, AccessControl {
            signer_cap,
            admin: @admin,
        });
    }

    public entry fun upgrade(sender: &signer, metadata_serialized: vector<u8>, code: vector<vector<u8>>) acquires AccessControl {
        is_admin(sender);
        let resource_signer = get_resource_signer();
        code::publish_package_txn(&resource_signer, metadata_serialized, code);
    }

    public(friend) fun get_resource_signer(): signer acquires AccessControl {
        let access_control = borrow_global<AccessControl>(@module_addr);
        account::create_signer_with_capability(&access_control.signer_cap)
    }

    public fun is_admin(sender: &signer) acquires AccessControl {
        let sender_addr = signer::address_of(sender);
        let access_control = borrow_global<AccessControl>(@module_addr);
        assert!(sender_addr == access_control.admin, ERROR_NOT_ADMIN);
    }
}