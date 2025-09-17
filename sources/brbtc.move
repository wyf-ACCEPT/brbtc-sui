module brbtc::brbtc {
    //---------------------------------------------- Dependencies ----------------------------------------------//
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::url;
    use brbtc::access_control::{Self as ac, AccessConfig, AdminCap, MinterCap, BurnerCap};

    //---------------------------------------------- Errors ----------------------------------------------//
    const ENOT_UPGRADE: u64 = 0;
    const EWRONG_VERSION: u64 = 1;
    const ECAP_REVOKED: u64 = 2;
    const ENO_CHANGE: u64 = 3;

    //---------------------------------------------- Constants ----------------------------------------------//
    //Todo: to be modified before deploy
    const SYMBOL: vector<u8> = b"BRBTC";
    const NAME: vector<u8> = b"BRBTC";
    const DESC: vector<u8> = b"BRBTC";
    const ICON: vector<u8> = b"https://raw.githubusercontent.com/Bedrock-Technology/bedrock-static/main/logo/brBTC.svg";
    const DECIMAL: u8 = 8;

    //version
    const VERSION: u8 = 0;

    //---------------------------------------------- Structs ----------------------------------------------//
    public struct BRBTC has drop {}

    public struct TreasuryCapManager has key{
        id: UID,
        version: u8,
        treasury: TreasuryCap<BRBTC>,
        revoked_minters: vector<ID>,
        revoked_burners: vector<ID>,
    }

    //---------------------------------------------- Init ----------------------------------------------//
    fun init(otw: BRBTC, ctx: &mut TxContext) {
        // Creates a new currency using `create_currency`, but with an extra capability that
        // allows for specific addresses to have their coins frozen. Those addresses cannot interact
        // with the coin as input objects.
        let (treasury_cap, deny_cap, meta_data) = coin::create_regulated_currency_v2(
            otw,
            DECIMAL,
            SYMBOL,
            NAME,
            DESC,
            option::some(url::new_unsafe_from_bytes(ICON)),
            true,
            ctx,
        );

        let treasury_manager = TreasuryCapManager{
            id: object::new(ctx),
            version: VERSION,
            treasury: treasury_cap,
            revoked_minters: vector::empty(),
            revoked_burners: vector::empty()
        };

        let sender = tx_context::sender(ctx);
        transfer::share_object(treasury_manager);
        transfer::public_transfer(deny_cap, sender);
        transfer::public_freeze_object(meta_data);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(BRBTC{}, ctx);
    }

    //--------------------------------------------------- Config ---------------------------------------------------//
    /// Set pause or unpause on protocol
    public entry fun set_pause(
        pause: bool, 
        config: &mut AccessConfig,
        ctx: &mut TxContext
    ) {
        ac::assert_pause_admin(config, tx_context::sender(ctx));
        ac::set_pause(config, pause);
    }

    /// Get the pause status on protocol
    public fun is_paused(config: &AccessConfig): bool { ac::is_paused(config) }

    public entry fun revoke_minter_cap(
        minter_cap_id: ID,
        treasury_manager: &mut TreasuryCapManager,
        config: &mut AccessConfig,
        _: &AdminCap,
    ) {
        assert!(
            !treasury_manager.revoked_minters.contains(&minter_cap_id),
            ENO_CHANGE,
        );
        treasury_manager.revoked_minters.push_back(minter_cap_id);
        ac::minter_cap_revoked(minter_cap_id, config);
    }

    public entry fun revoke_burner_cap(
        burner_cap_id: ID,
        treasury_manager: &mut TreasuryCapManager,
        config: &mut AccessConfig,
        _: &AdminCap,
    ) {
        assert!(
            !treasury_manager.revoked_burners.contains(&burner_cap_id),
            ENO_CHANGE,
        );
        treasury_manager.revoked_burners.push_back(burner_cap_id);
        ac::burner_cap_revoked(burner_cap_id, config);
    }
    //---------------------------------------------- Entry Functions ----------------------------------------------//
    public fun mint(
        value: u64, 
        treasury_manager: &mut TreasuryCapManager, 
        minter_cap: &MinterCap,
        config: &AccessConfig,
        ctx: &mut TxContext
    ): Coin<BRBTC> {
        ac::assert_not_paused(config);
        check_version(treasury_manager.version);
        assert!(
            !treasury_manager.revoked_minters.contains(&ac::get_minter_cap_id(minter_cap)),
            ECAP_REVOKED,
        );
        coin::mint(&mut treasury_manager.treasury, value, ctx)
    }

    public fun burn(
        coin: Coin<BRBTC>,
        treasury_manager: &mut TreasuryCapManager, 
        burner_cap: &BurnerCap,
        config: &AccessConfig,
    ): u64 { 
        ac::assert_not_paused(config);
        check_version(treasury_manager.version);
        assert!(
            !treasury_manager.revoked_burners.contains(&ac::get_burner_cap_id(burner_cap)),
            ECAP_REVOKED,
        );
        coin::burn(&mut treasury_manager.treasury, coin)
    }

    //---------------------------------------------- Get Functions ----------------------------------------------//
    public fun revoked_minters(treasury: &TreasuryCapManager): vector<ID> {
        treasury.revoked_minters
    }

    public fun revoked_burners(treasury: &TreasuryCapManager): vector<ID> {
        treasury.revoked_burners
    }

    //---------------------------------------------- Private Functions ----------------------------------------------//
    entry fun migrate(t: &mut TreasuryCapManager, _: &AdminCap) {
        assert!(t.version < VERSION, ENOT_UPGRADE);
        t.version = VERSION;
    }

    fun check_version(version: u8){
        assert!(version == VERSION, EWRONG_VERSION)
    }

}
