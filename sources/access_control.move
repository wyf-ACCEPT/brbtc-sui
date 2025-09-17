#[allow(lint(custom_state_change, self_transfer))]
module brbtc::access_control{

    //---------------------------------------------- Dependencies ----------------------------------------------//
    use sui::event;
    use sui::table::{Self, Table};

    //---------------------------------------------- Errors ----------------------------------------------//
    const EPAUSED: u64 = 0;
    const ENO_CHANGE: u64 = 1;
    const EUNAUTHORIZED: u64 = 2;
    const EINVALID_ADDRESS: u64 = 3;
    const ENOT_ACCEPTED_YET: u64 = 4;

    //---------------------------------------------- Structs ----------------------------------------------//
    public struct AccessConfig has key{
        id: UID,
        proposed_admin: Option<AdminChange>,
        paused: bool,
        pause_admin: vector<address>,
        minter_caps: Table<ID, address>,
        burner_caps: Table<ID, address>,
    }

    public struct AdminCap has key{
        id: UID
    }

    public struct AdminChange has store, drop {
        proposed_admin: address,
        accepted: bool,
    }

    public struct MinterCap has key, store {
        id: UID,
    }

    public struct BurnerCap has key, store {
        id: UID,
    }

    //---------------------------------------------- Events ----------------------------------------------//
    public struct AdminCapTransferred has copy, drop {
        cap_id: address,
        from: address,
        to: address
    }

    public struct ProposedAdminChange has copy, drop {
        new_admin: address,
        old_admin: address,
    }

    public struct PauseAdminSet has copy, drop {
        pause_admin: address,
        add: bool,
    }

    public struct MinterCapIssued has copy, drop {
        minter: address,
        minter_cap_id: ID,
    }

    public struct MinterCapRevoked has copy, drop {
        minter_cap_id: ID,
    }

    public struct MinterCapDestroyed has copy, drop {
        minter_cap_id: ID,
    }

    public struct BurnerCapIssued has copy, drop {
        burner: address,
        burner_cap_id: ID,
    }

    public struct BurnerCapRevoked has copy, drop {
        burner_cap_id: ID,
    }

    public struct BurnerCapDestroyed has copy, drop {
        burner_cap_id: ID,
    }

    public struct PauseSet has copy, drop {
        paused: bool,
    }

    //---------------------------------------------- Init ----------------------------------------------//
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let admin_cap = AdminCap { id: object::new(ctx) };
        
        event::emit(AdminCapTransferred {
            cap_id: object::uid_to_address(&admin_cap.id),
            from: @0x0,
            to: sender
        });
        
        transfer::transfer(admin_cap, sender);

        let ac = AccessConfig{
            id: object::new(ctx),
            proposed_admin: option::none(),
            paused: false,
            pause_admin: vector[sender],
            minter_caps: table::new(ctx),
            burner_caps: table::new(ctx),
        };
        transfer::share_object(ac);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    //---------------------------------------------- Admin Config ----------------------------------------------//
    public entry fun propose_admin_change(
        config: &mut AccessConfig,
        new_admin: address,
        _: &AdminCap,
        ctx: &mut TxContext
    ){
        let sender = tx_context::sender(ctx);
        assert!(new_admin != @0x0, EINVALID_ADDRESS);
        assert!(new_admin != sender, ENO_CHANGE);
        let proposal = AdminChange{
            proposed_admin: new_admin,
            accepted: false,
        };
        config.proposed_admin = option::some(proposal);
        event::emit(ProposedAdminChange{
            new_admin,
            old_admin: sender
        })
    }

    public entry fun accept_admin(
        config: &mut AccessConfig,
        ctx: &mut TxContext
    ){
        let sender = tx_context::sender(ctx);
        let proposal = option::borrow_mut(&mut config.proposed_admin);
        assert!(sender == proposal.proposed_admin, EUNAUTHORIZED);
        proposal.accepted = true;
    }

    public entry fun execute_admin_change_proposal(
        config: &mut AccessConfig,
        admin_cap: AdminCap,
        ctx: &mut TxContext
    ){
        let sender = tx_context::sender(ctx);
        let proposal = option::borrow(&config.proposed_admin);
        let new_admin = proposal.proposed_admin;
        assert!(proposal.accepted == true, ENOT_ACCEPTED_YET);
        config.proposed_admin = option::none();
        let cap_id =  object::uid_to_address(&admin_cap.id);
        transfer::transfer(admin_cap, new_admin);
        event::emit(AdminCapTransferred{
            cap_id,
            from: sender,
            to: new_admin
        })
    }

    public entry fun retract_admin_change_proposal(
        config: &mut AccessConfig,
        _: &AdminCap,
    ){
        config.proposed_admin = option::none();
    }

    #[test_only]
    public fun proposal_is_active(config: &AccessConfig): bool{
        !option::is_none(&config.proposed_admin)
    }

    #[test_only]
    public fun get_proposed_admin_accept_status(config: &AccessConfig): bool{
        option::borrow(&config.proposed_admin).accepted
    }

    #[test_only]
    public fun get_proposed_admin(config: &AccessConfig): address{
        option::borrow(&config.proposed_admin).proposed_admin
    }

    //---------------------------------------------- Pause Config ----------------------------------------------//
    /// Pause or unpause
    public(package) fun set_pause(config: &mut AccessConfig, pause: bool){
        assert!(is_paused(config) != pause, ENO_CHANGE);
        config.paused = pause;
        event::emit(PauseSet { paused: pause });
    }

    /// Check if protocol is paused
    public(package) fun is_paused(config: &AccessConfig): bool {
        config.paused
    }

    /// Revert if protocol is paused
    public(package) fun assert_not_paused(config: &AccessConfig) {
        assert!(!is_paused(config), EPAUSED);
    }

    public entry fun set_pause_admin(
        config: &mut AccessConfig,
        pause_admin: address, 
        add: bool,
        _: &AdminCap
    ) {
        if(add){
            assert!(!vector::contains(&config.pause_admin, &pause_admin), ENO_CHANGE);
            vector::push_back(&mut config.pause_admin, pause_admin);
        }else{
            let (found, idx) = vector::index_of(&config.pause_admin, &pause_admin);
            assert!(found, ENO_CHANGE);
            vector::remove(&mut config.pause_admin, idx);
        };
        event::emit(PauseAdminSet { pause_admin, add });
    }

    public fun has_pause_admin(config: &AccessConfig): bool {
        vector::length(&get_pause_admin(config)) != 0
    }

    public fun get_pause_admin(config: &AccessConfig): vector<address> {
        config.pause_admin
    }

    /// Asserts that a user address is the Minter
    public fun assert_pause_admin(config: &AccessConfig, user: address) {
        assert!(vector::contains(&get_pause_admin(config), &user), EUNAUTHORIZED);
    }

    //---------------------------------------------- Minter Functions ----------------------------------------------//
    public(package) fun get_minter_cap_id(minter_cap: &MinterCap): ID{
        object::uid_to_inner(&minter_cap.id)
    }

    /// Add or the minter address
    public entry fun issue_minter_cap(
        minter: address, 
        config: &mut AccessConfig,
        _: &AdminCap,
        ctx: &mut TxContext
    ){
        let minter_cap = MinterCap {
            id: object::new(ctx),
        };
        let minter_cap_id = object::uid_to_inner(&minter_cap.id);
        table::add(&mut config.minter_caps, minter_cap_id, minter);
        transfer::transfer(minter_cap, minter);
        event::emit(MinterCapIssued { minter, minter_cap_id });
        
    }

    public(package) fun minter_cap_revoked(
        minter_cap_id: ID, 
        config: &mut AccessConfig,
    ){
        if(table::contains(&config.minter_caps, minter_cap_id)){
            table::remove(&mut config.minter_caps, minter_cap_id);
        };
        event::emit(MinterCapRevoked { minter_cap_id });
    }

    public entry fun destroy_minter_cap(
        minter_cap: MinterCap,
        config: &mut AccessConfig,
    ) {
        let MinterCap {id} = minter_cap;
        let minter_cap_id = object::uid_to_inner(&id);
        if(table::contains(&config.minter_caps, minter_cap_id)){
            table::remove(&mut config.minter_caps, minter_cap_id);
        };
        object::delete(id);
        event::emit(MinterCapDestroyed { minter_cap_id });
    }

    //---------------------------------------------- Burner Functions ----------------------------------------------//
    public(package) fun get_burner_cap_id(burner_cap: &BurnerCap): ID{
        object::uid_to_inner(&burner_cap.id)
    }

    /// Add or the burner address
    public entry fun issue_burner_cap(
        burner: address, 
        config: &mut AccessConfig,
        _: &AdminCap,
        ctx: &mut TxContext
    ){
        let burner_cap = BurnerCap {
            id: object::new(ctx),
        };
        let burner_cap_id = object::uid_to_inner(&burner_cap.id);
        table::add(&mut config.burner_caps, burner_cap_id, burner);
        transfer::transfer(burner_cap, burner);
        event::emit(BurnerCapIssued { burner, burner_cap_id });
        
    }

    public(package) fun burner_cap_revoked(
        burner_cap_id: ID, 
        config: &mut AccessConfig
    ){
        if(table::contains(&config.burner_caps, burner_cap_id)){
            table::remove(&mut config.burner_caps, burner_cap_id);
        };
        event::emit(BurnerCapRevoked { burner_cap_id });
    }

    public entry fun destroy_burner_cap(
        burner_cap: BurnerCap,
        config: &mut AccessConfig
    ) {
        let BurnerCap {id} = burner_cap;
        let burner_cap_id = object::uid_to_inner(&id);
        if(table::contains(&config.burner_caps, burner_cap_id)){
            table::remove(&mut config.burner_caps, burner_cap_id);
        };
        object::delete(id);
        event::emit(BurnerCapDestroyed { burner_cap_id });
    }

}
