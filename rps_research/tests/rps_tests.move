#[test_only]
module rps_research::rps_tests;

use rps_research::rps::{Self, Game, Config, AdminCap};
use rps_research::errors;

use sui::test_scenario::{Self as scenario, Scenario};
use sui::coin;
use sui::sui::SUI;
use sui::clock;
use std::type_name;

// Test constants
const ADMIN: address = @0xAD;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const CHARLIE: address = @0xC4A41E;

const STAKE_AMOUNT: u64 = 1_000_000_000; // 1 SUI
const MIN_STAKE: u64 = 100_000_000; // 0.1 SUI
const MAX_STAKE: u64 = 10_000_000_000; // 10 SUI
const ROUNDS_TO_WIN: u8 = 3;
const JOIN_TIMEOUT: u64 = 300_000; // 5 minutes
const ROUND_TIMEOUT: u64 = 120_000; // 2 minutes

// Helper to setup initial state with Config and AdminCap
fun setup_game_environment(scenario: &mut Scenario) {
    // Initialize the module
    scenario::next_tx(scenario, ADMIN);
    {
        rps::test_init(scenario::ctx(scenario));
    };
    
    // Setup SUI asset in config
    scenario::next_tx(scenario, ADMIN);
    {
        let admin_cap = scenario::take_from_sender<AdminCap>(scenario);
        let mut config = scenario::take_shared<Config>(scenario);
        
        rps::addOrEditSupportedAsset(
            &admin_cap,
            &mut config,
            true, // enabled
            MIN_STAKE,
            MAX_STAKE,
            200, // 2% house edge
            type_name::get<SUI>()
        );
        
        scenario::return_to_sender(scenario, admin_cap);
        scenario::return_shared(config);
    };
}

#[test]
fun test_create_game_success() {
    let mut scenario = scenario::begin(ADMIN);
    setup_game_environment(&mut scenario);
    
    // Alice creates a game
    scenario::next_tx(&mut scenario, ALICE);
    {
        let config = scenario::take_shared<Config>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::createGame(
            &config,
            stake,
            ROUNDS_TO_WIN,
            option::none(), // no whitelist
            JOIN_TIMEOUT,
            ROUND_TIMEOUT,
            &clock,
            scenario::ctx(&mut scenario)
        );
        
        scenario::return_shared(config);
        clock::destroy_for_testing(clock);
    };
    
    // Verify game was created
    scenario::next_tx(&mut scenario, ALICE);
    {
        assert!(scenario::has_most_recent_shared<Game<SUI>>(), 0);
        let game = scenario::take_shared<Game<SUI>>(&scenario);
        
        assert!(rps::game_status(&game) == rps::game_status_open(), 1);
        assert!(rps::player_a(&game) == ALICE, 2);
        assert!(option::is_none(&rps::player_b(&game)), 3);
        assert!(rps::stake_per_player(&game) == STAKE_AMOUNT, 4);
        assert!(rps::rounds_to_win(&game) == ROUNDS_TO_WIN, 5);
        assert!(rps::current_round(&game) == 0, 6);
        
        scenario::return_shared(game);
    };
    
    scenario::end(scenario);
}

#[test]
fun test_join_game_success() {
    let mut scenario = scenario::begin(ADMIN);
    setup_game_environment(&mut scenario);
    
    // Alice creates a game
    scenario::next_tx(&mut scenario, ALICE);
    {
        let config = scenario::take_shared<Config>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::createGame(
            &config,
            stake,
            ROUNDS_TO_WIN,
            option::none(),
            JOIN_TIMEOUT,
            ROUND_TIMEOUT,
            &clock,
            scenario::ctx(&mut scenario)
        );
        
        scenario::return_shared(config);
        clock::destroy_for_testing(clock);
    };
    
    // Bob joins the game
    scenario::next_tx(&mut scenario, BOB);
    {
        let mut game = scenario::take_shared<Game<SUI>>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::joinGame(
            stake,
            &mut game,
            &clock,
            scenario::ctx(&mut scenario)
        );
        
        assert!(rps::game_status(&game) == rps::game_status_active(), 0);
        assert!(option::is_some(&rps::player_b(&game)), 1);
        let player_b = rps::player_b(&game);
        assert!(*option::borrow(&player_b) == BOB, 2);
        assert!(rps::current_round(&game) == 1, 3);
        
        scenario::return_shared(game);
        clock::destroy_for_testing(clock);
    };
    
    scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = errors::EGameWhitelisted)]
fun test_join_game_whitelisted_fail() {
    let mut scenario = scenario::begin(ADMIN);
    setup_game_environment(&mut scenario);
    
    // Alice creates a whitelisted game for BOB only
    scenario::next_tx(&mut scenario, ALICE);
    {
        let config = scenario::take_shared<Config>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::createGame(
            &config,
            stake,
            ROUNDS_TO_WIN,
            option::some(BOB), // whitelisted for BOB only
            JOIN_TIMEOUT,
            ROUND_TIMEOUT,
            &clock,
            scenario::ctx(&mut scenario)
        );
        
        scenario::return_shared(config);
        clock::destroy_for_testing(clock);
    };
    
    // Charlie tries to join but should fail
    scenario::next_tx(&mut scenario, CHARLIE);
    {
        let mut game = scenario::take_shared<Game<SUI>>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::joinGame(stake, &mut game, &clock, scenario::ctx(&mut scenario));
        
        scenario::return_shared(game);
        clock::destroy_for_testing(clock);
    };
    
    scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = errors::EStakeTooLow)]
fun test_create_game_stake_too_low() {
    let mut scenario = scenario::begin(ADMIN);
    setup_game_environment(&mut scenario);
    
    scenario::next_tx(&mut scenario, ALICE);
    {
        let config = scenario::take_shared<Config>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(MIN_STAKE - 1, scenario::ctx(&mut scenario)); // Below minimum
        
        rps::createGame(
            &config,
            stake,
            ROUNDS_TO_WIN,
            option::none(),
            JOIN_TIMEOUT,
            ROUND_TIMEOUT,
            &clock,
            scenario::ctx(&mut scenario)
        );
        
        scenario::return_shared(config);
        clock::destroy_for_testing(clock);
    };
    
    scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = errors::EStakeTooHigh)]
fun test_create_game_stake_too_high() {
    let mut scenario = scenario::begin(ADMIN);
    setup_game_environment(&mut scenario);
    
    scenario::next_tx(&mut scenario, ALICE);
    {
        let config = scenario::take_shared<Config>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(MAX_STAKE + 1, scenario::ctx(&mut scenario)); // Above maximum
        
        rps::createGame(
            &config,
            stake,
            ROUNDS_TO_WIN,
            option::none(),
            JOIN_TIMEOUT,
            ROUND_TIMEOUT,
            &clock,
            scenario::ctx(&mut scenario)
        );
        
        scenario::return_shared(config);
        clock::destroy_for_testing(clock);
    };
    
    scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = errors::EGameUnequalStake)]
fun test_join_game_wrong_stake() {
    let mut scenario = scenario::begin(ADMIN);
    setup_game_environment(&mut scenario);
    
    // Alice creates a game
    scenario::next_tx(&mut scenario, ALICE);
    {
        let config = scenario::take_shared<Config>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::createGame(
            &config,
            stake,
            ROUNDS_TO_WIN,
            option::none(),
            JOIN_TIMEOUT,
            ROUND_TIMEOUT,
            &clock,
            scenario::ctx(&mut scenario)
        );
        
        scenario::return_shared(config);
        clock::destroy_for_testing(clock);
    };
    
    // Bob tries to join with wrong stake amount
    scenario::next_tx(&mut scenario, BOB);
    {
        let mut game = scenario::take_shared<Game<SUI>>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT + 1, scenario::ctx(&mut scenario)); // Wrong amount
        
        rps::joinGame(stake, &mut game, &clock, scenario::ctx(&mut scenario));
        
        scenario::return_shared(game);
        clock::destroy_for_testing(clock);
    };
    
    scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = errors::EGameNotOpen)]
fun test_join_game_already_active() {
    let mut scenario = scenario::begin(ADMIN);
    setup_game_environment(&mut scenario);
    
    // Alice creates a game
    scenario::next_tx(&mut scenario, ALICE);
    {
        let config = scenario::take_shared<Config>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::createGame(
            &config,
            stake,
            ROUNDS_TO_WIN,
            option::none(),
            JOIN_TIMEOUT,
            ROUND_TIMEOUT,
            &clock,
            scenario::ctx(&mut scenario)
        );
        
        scenario::return_shared(config);
        clock::destroy_for_testing(clock);
    };
    
    // Bob joins the game
    scenario::next_tx(&mut scenario, BOB);
    {
        let mut game = scenario::take_shared<Game<SUI>>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::joinGame(stake, &mut game, &clock, scenario::ctx(&mut scenario));
        
        scenario::return_shared(game);
        clock::destroy_for_testing(clock);
    };
    
    // Charlie tries to join an already active game
    scenario::next_tx(&mut scenario, CHARLIE);
    {
        let mut game = scenario::take_shared<Game<SUI>>(&scenario);
        let clock = clock::create_for_testing(scenario::ctx(&mut scenario));
        let stake = coin::mint_for_testing<SUI>(STAKE_AMOUNT, scenario::ctx(&mut scenario));
        
        rps::joinGame(stake, &mut game, &clock, scenario::ctx(&mut scenario));
        
        scenario::return_shared(game);
        clock::destroy_for_testing(clock);
    };
    
    scenario::end(scenario);
}

// Note: Tests for playRound and revealRound require actual Seal encryption
// which will be implemented with proper Seal KMS integration in the next step.
// For now, we have comprehensive tests for game creation and joining logic.