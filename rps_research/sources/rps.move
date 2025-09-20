module rps_research::rps;

use rps_research::errors;
use rps_research::events;

use std::type_name::{Self, TypeName};

use sui::table::{Self, Table};
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::clock::Clock;

use seal::bf_hmac_encryption::{
    Self,
    EncryptedObject,
    VerifiedDerivedKey,
    PublicKey
};

/// Structs

// admin capability to change configurations
public struct AdminCap has key, store {
    id: UID
}

// global config struct defining policies
public struct Config has key {
    id: UID,
    allowedAssets: Table<TypeName, AssetConfig>,
    minTimeout: u64,
    maxTimeout: u64
}

public struct AssetConfig has store, drop {
    enabled: bool,
    min_stake: u64,
    max_stake: u64,
    house_edge: u16 // basis points (e.g., 200 = 2%)
}

public enum GameStatus has store, copy, drop {
    OPEN,
    ACTIVE,
    CANCELLED,
    COMPLETED
}

// represents a game between players
public struct Game<phantom T> has key, store {
    id: UID,
    game_status: GameStatus,
    whitelist: Option<address>,
    player_a: address,
    player_b: Option<address>,
    winner: Option<address>,
    stake: Balance<T>, // combined stake from both players
    stake_per_player: u64, // amount each player must stake
    points_a: u8, //points collected in rounds so far
    points_b: u8,
    rounds: vector<Round>, // contains each played round; accessible by index
    rounds_to_win: u8, //number of rounds to win this game
    current_round: u8, //current round being played
    round_timeout: u64,
    next_timeout: u64, // this timeout resets to the current time when a round is completed
    created_at: u64
}

public enum Action has store, copy, drop {
    SCISSORS,
    STONE,
    PAPER
}

// represents a round in a game
public struct Round has store {
    commitment_a: Option<EncryptedObject>, // secret commitments
    commitment_b: Option<EncryptedObject>,
    move_a: Option<Action>, // revealed moves once both players committed
    move_b: Option<Action>
}

/// Init function - called when package is published
#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx);
}

fun init(ctx: &mut TxContext) {
    // Create admin capability
    let admin_cap = AdminCap {
        id: object::new(ctx)
    };
    
    // Create config with default values
    let config = Config {
        id: object::new(ctx),
        allowedAssets: table::new(ctx),
        minTimeout: 60_000, // 1 minute minimum
        maxTimeout: 3_600_000 // 1 hour maximum
    };
    
    // Transfer admin cap to deployer
    transfer::transfer(admin_cap, ctx.sender());
    
    // Share the config object
    transfer::share_object(config);
}

/// Functions
public fun createGame<T>(
    config: &Config,
    stake: Coin<T>,
    rounds: u8,
    whitelist: Option<address>,
    join_timeout: u64,
    round_timeout: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let type_name = type_name::get<T>();
    if (!table::contains(&config.allowedAssets, type_name)) {
        errors::asset_not_allowed();
    };
    let asset_config: &AssetConfig = table::borrow(&config.allowedAssets, type_name);

    if (!asset_config.enabled) {
        errors::asset_disabled();
    };

    // Check stake bounds
    let stake_amount = stake.value();
    if (stake_amount < asset_config.min_stake) {
        errors::stake_too_low();
    } else if (stake_amount > asset_config.max_stake) {
        errors::stake_too_high();
    };

    // Check timeout bounds
    if (round_timeout < config.minTimeout) {
        errors::timeout_too_low();
    } else if (round_timeout > config.maxTimeout) {
        errors::timeout_too_high();
    };

    let current_time = clock.timestamp_ms();
    let game_id = object::new(ctx);
    let game_id_copy = object::uid_to_inner(&game_id);

    // Create the game
    let game = Game<T> {
        id: game_id,
        game_status: GameStatus::OPEN,
        whitelist: whitelist,
        player_a: ctx.sender(),
        player_b: option::none(),
        winner: option::none(),
        stake: coin::into_balance(stake),
        stake_per_player: stake_amount,
        points_a: 0,
        points_b: 0,
        rounds: vector::empty(),
        rounds_to_win: rounds,
        current_round: 0,
        round_timeout: round_timeout,
        next_timeout: current_time + join_timeout,
        created_at: current_time
    };

    // Emit game created event
    events::emit_game_created(
        game_id_copy,
        ctx.sender(),
        stake_amount,
        type_name,
        rounds,
        whitelist,
        current_time + join_timeout
    );

    // Share the game object
    transfer::share_object(game);
}

public fun joinGame<T>(
    stake: Coin<T>,
    game: &mut Game<T>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    //Checks
    if (game.game_status != GameStatus::OPEN) {
        errors::game_not_open();
    };
    let current_time = clock.timestamp_ms();

    if (current_time > game.next_timeout) {
        errors::game_timed_out(); //should the game be closed here?
    };

    let player_b_addr : address = ctx.sender();
    if (game.whitelist.is_some() && game.whitelist.borrow() != player_b_addr) {
        errors::game_whitelisted();
    };

    if(stake.value() != game.stake_per_player) {
        errors::game_unequal_stake();
    };

    //Update Game
    game.player_b = option::some(ctx.sender());
    game.next_timeout = current_time + game.round_timeout;
    game.current_round = 1;
    game.game_status = GameStatus::ACTIVE;
    // Merge player B's stake into the combined stake
    balance::join(&mut game.stake, coin::into_balance(stake));
    
    // Create the first round
    let first_round = Round {
        commitment_a: option::none(),
        commitment_b: option::none(),
        move_a: option::none(),
        move_b: option::none()
    };
    vector::push_back(&mut game.rounds, first_round);
}

// user can play the current round of the game
// later: revealing the previous round can be integrated
public fun playRound<T>(
    game: &mut Game<T>,
    action: EncryptedObject,
    clock: &Clock, 
    ctx: &mut TxContext
) {
    // Check game is active
    if (game.game_status != GameStatus::ACTIVE) {
        errors::game_not_active();
    };

    let current_time = clock.timestamp_ms();

    // Check round has not timed out
    if (current_time > game.next_timeout) {
        errors::round_timed_out();
    };

    let player_a_address: address = game.player_a;
    let player_b_address: address = *game.player_b.borrow();
    let current_player: address = ctx.sender();

    // Check sender is one of the players
    if (!(current_player == player_a_address || current_player == player_b_address)) {
        errors::invalid_player();
    };

    // Get the current round (it should already exist)
    let round_index = (game.current_round - 1) as u64;
    let current_round_ref = vector::borrow_mut(&mut game.rounds, round_index);

    // Check if player has already committed for this round and store commitment
    if (current_player == player_a_address) {
        if (current_round_ref.commitment_a.is_some()) {
            errors::already_played();
        };
        current_round_ref.commitment_a = option::some(action);
    } else {
        if (current_round_ref.commitment_b.is_some()) {
            errors::already_played();
        };
        current_round_ref.commitment_b = option::some(action);
    };

    // Emit commitment event
    let game_id = object::uid_to_inner(&game.id);
    events::emit_round_commitment(
        game_id,
        current_player,
        game.current_round
    );
}

public fun revealRound<T>(
    game: &mut Game<T>,
    derived_keys_a: vector<VerifiedDerivedKey>,
    derived_keys_b: vector<VerifiedDerivedKey>,
    public_keys: vector<PublicKey>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Check game is active
    if (game.game_status != GameStatus::ACTIVE) {
        errors::game_not_active();
    };

    // We need to reveal the previous round (current_round - 1)
    if (game.current_round == 0) {
        abort 0 // No round to reveal yet
    };
    
    let round_to_reveal = (game.current_round - 1) as u64;
    let round = vector::borrow_mut(&mut game.rounds, round_to_reveal);
    
    // Check that both players have committed for this round
    if (round.commitment_a.is_none() || round.commitment_b.is_none()) {
        errors::round_not_complete();
    };

    // Get the commitments
    let commitment_a = round.commitment_a.borrow();
    let commitment_b = round.commitment_b.borrow();
    
    // Decrypt commitments
    // Seal's decrypt function automatically verifies that:
    // 1. The VerifiedDerivedKey's package_id and id match the EncryptedObject
    // 2. The keys are from valid key servers in the EncryptedObject
    // 3. Sufficient keys are provided (threshold met)
    let decrypted_a = bf_hmac_encryption::decrypt(
        commitment_a,
        &derived_keys_a,
        &public_keys
    );
    
    let decrypted_b = bf_hmac_encryption::decrypt(
        commitment_b,
        &derived_keys_b,
        &public_keys
    );

    // Check if either decryption failed
    // This can happen if:
    // - Wrong keys provided (for different commitment)
    // - Insufficient keys (threshold not met)
    // - Invalid keys
    if (decrypted_a.is_none() || decrypted_b.is_none()) {
        errors::invalid_decryption_key();
    };

    // Parse decrypted values as Actions
    let decrypted_a_bytes = option::destroy_some(decrypted_a);
    let decrypted_b_bytes = option::destroy_some(decrypted_b);
    
    // Validate and parse actions (if invalid format, that player loses)
    let action_a_opt = parse_action(&decrypted_a_bytes);
    let action_b_opt = parse_action(&decrypted_b_bytes);
    
    if (action_a_opt.is_none() && action_b_opt.is_none()) {
        // Both invalid - shouldn't happen
        errors::invalid_commitment();
    } else if (action_a_opt.is_none()) {
        // Player A sent invalid action - Player B wins
        let player_b = *option::borrow(&game.player_b);
        finalizeGame(game, player_b, ctx);
        return
    } else if (action_b_opt.is_none()) {
        // Player B sent invalid action - Player A wins
        let player_a = game.player_a;
        finalizeGame(game, player_a, ctx);
        return
    };
    
    let action_a = option::destroy_some(action_a_opt);
    let action_b = option::destroy_some(action_b_opt);
    
    // Store revealed moves
    round.move_a = option::some(action_a);
    round.move_b = option::some(action_b);

    // Evaluate round winner
    let round_winner = evaluate_round(action_a, action_b);
    
    // Update points based on round winner
    let mut round_winner_address: Option<address> = option::none();
    if (round_winner == 1) {
        // Player A wins this round
        game.points_a = game.points_a + 1;
        round_winner_address = option::some(game.player_a);
    } else if (round_winner == 2) {
        // Player B wins this round
        game.points_b = game.points_b + 1;
        round_winner_address = option::some(*option::borrow(&game.player_b));
    };
    // round_winner == 0 means tie, no points awarded

    // Emit round revealed event
    let game_id = object::uid_to_inner(&game.id);
    events::emit_round_revealed(
        game_id,
        game.current_round - 1,
        action_to_u8(action_a),
        action_to_u8(action_b),
        round_winner_address
    );

    // Check if game is over
    if (game.points_a >= game.rounds_to_win) {
        // Player A wins the game
        let player_a = game.player_a;
        finalizeGame(game, player_a, ctx);
    } else if (game.points_b >= game.rounds_to_win) {
        // Player B wins the game
        let player_b = *option::borrow(&game.player_b);
        finalizeGame(game, player_b, ctx);
    } else {
        // Game continues - create next round
        game.current_round = game.current_round + 1;
        game.next_timeout = clock.timestamp_ms() + game.round_timeout;
        
        let new_round = Round {
            commitment_a: option::none(),
            commitment_b: option::none(),
            move_a: option::none(),
            move_b: option::none()
        };
        vector::push_back(&mut game.rounds, new_round);
    }
}

// Helper function to parse bytes into Action
fun parse_action(bytes: &vector<u8>): Option<Action> {
    if (vector::length(bytes) != 1) {
        return option::none()
    };
    
    let action_byte = *vector::borrow(bytes, 0);
    
    if (action_byte == 0) {
        option::some(Action::SCISSORS)
    } else if (action_byte == 1) {
        option::some(Action::STONE)
    } else if (action_byte == 2) {
        option::some(Action::PAPER)
    } else {
        option::none()
    }
}

// Convert Action to u8 for events
fun action_to_u8(action: Action): u8 {
    if (action == Action::SCISSORS) {
        0
    } else if (action == Action::STONE) {
        1
    } else {
        2
    }
}

// Evaluate who wins a round (returns 0 for tie, 1 for player A, 2 for player B)
fun evaluate_round(action_a: Action, action_b: Action): u8 {
    if (action_a == action_b) {
        return 0  // Tie
    };
    
    // Rock beats Scissors, Scissors beats Paper, Paper beats Rock
    if (action_a == Action::STONE && action_b == Action::SCISSORS) {
        1
    } else if (action_a == Action::SCISSORS && action_b == Action::PAPER) {
        1
    } else if (action_a == Action::PAPER && action_b == Action::STONE) {
        1
    } else {
        2
    }
}

// Finalize the game and distribute winnings
fun finalizeGame<T>(
    game: &mut Game<T>,
    winner: address,
    ctx: &mut TxContext
) {
    // Update game status
    game.game_status = GameStatus::COMPLETED;
    game.winner = option::some(winner);
    
    // Calculate winnings (deduct house edge if configured)
    let total_stake = balance::value(&game.stake);
    
    // Transfer winnings to winner
    let winnings = coin::from_balance(
        balance::split(&mut game.stake, total_stake),
        ctx
    );
    transfer::public_transfer(winnings, winner);
    
    // Emit game completed event
    let game_id = object::uid_to_inner(&game.id);
    events::emit_game_completed(
        game_id,
        winner,
        game.points_a,
        game.points_b
    );
}

public fun addOrEditSupportedAsset(
    _admincap: &AdminCap,
    config: &mut Config,
    enabled: bool,
    min_stake: u64,
    max_stake: u64,
    house_edge: u16,
    typename: TypeName
) {
    let asset_config = AssetConfig {
        enabled,
        min_stake,
        max_stake,
        house_edge
    };
    
    if (table::contains(&config.allowedAssets, typename)) {
        // Update existing
        let existing = table::borrow_mut(&mut config.allowedAssets, typename);
        *existing = asset_config;
    } else {
        // Add new
        table::add(&mut config.allowedAssets, typename, asset_config);
    }
}

// Public accessor functions
public fun game_status<T>(game: &Game<T>): GameStatus {
    game.game_status
}

public fun player_a<T>(game: &Game<T>): address {
    game.player_a
}

public fun player_b<T>(game: &Game<T>): Option<address> {
    game.player_b
}

public fun winner<T>(game: &Game<T>): Option<address> {
    game.winner
}

public fun stake_per_player<T>(game: &Game<T>): u64 {
    game.stake_per_player
}

public fun points_a<T>(game: &Game<T>): u8 {
    game.points_a
}

public fun points_b<T>(game: &Game<T>): u8 {
    game.points_b
}

public fun rounds_to_win<T>(game: &Game<T>): u8 {
    game.rounds_to_win
}

public fun current_round<T>(game: &Game<T>): u8 {
    game.current_round
}

public fun round_timeout<T>(game: &Game<T>): u64 {
    game.round_timeout
}

public fun next_timeout<T>(game: &Game<T>): u64 {
    game.next_timeout
}

public fun created_at<T>(game: &Game<T>): u64 {
    game.created_at
}

// Test helper functions
#[test_only]
public fun game_status_open(): GameStatus {
    GameStatus::OPEN
}

#[test_only]
public fun game_status_active(): GameStatus {
    GameStatus::ACTIVE
}

#[test_only]
public fun game_status_cancelled(): GameStatus {
    GameStatus::CANCELLED
}

#[test_only]
public fun game_status_completed(): GameStatus {
    GameStatus::COMPLETED
}

// Policy function for Seal KMS services to check if decryption keys can be released
// Anyone can decrypt, but only for rounds where both players have committed
public fun check_policy<T>(
    game: &Game<T>,
    round_index: u64,              // Which round the commitment belongs to
    commitment_id: vector<u8>,     // The ID from the EncryptedObject being decrypted
): bool {
    // Check if the game is active
    if (game.game_status != GameStatus::ACTIVE) {
        return false
    };
    
    // Check if the round exists
    if (round_index >= vector::length(&game.rounds)) {
        return false
    };
    
    // Get the specified round
    let round = vector::borrow(&game.rounds, round_index);
    
    // Both commitments must exist before ANY decryption is allowed
    if (!round.commitment_a.is_some() || !round.commitment_b.is_some()) {
        return false
    };
    
    // Verify this commitment actually belongs to this round
    // Compare the commitment_id with the IDs stored in our round's commitments
    let commitment_a_id = bf_hmac_encryption::id(round.commitment_a.borrow());
    let commitment_b_id = bf_hmac_encryption::id(round.commitment_b.borrow());
    
    // Only allow decryption if this is one of the commitments from this round
    *commitment_a_id == commitment_id || *commitment_b_id == commitment_id
}