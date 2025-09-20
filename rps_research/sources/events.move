module rps_research::events;

use std::type_name::TypeName;
use sui::object::ID;
use sui::event;

public struct GameCreated has copy, drop {
    game_id: ID,
    creator: address,
    stake: u64,
    coin_type: TypeName,
    rounds_to_win: u8,
    whitelist: Option<address>,  // true if anyone can join
    join_deadline: u64,
}

public struct GameJoined has copy, drop {
    game_id: ID,
    joiner: address,
}

public struct GameStatusChanged has copy, drop {
    game_id: ID,
    old_status: u8,
    new_status: u8,
}

public struct RoundCommitment has copy, drop {
    game_id: ID,
    player: address,
    round: u8,
}

public struct RoundRevealed has copy, drop {
    game_id: ID,
    round: u8,
    move_a: u8, // 0=SCISSORS, 1=STONE, 2=PAPER
    move_b: u8,
    winner: Option<address>, // None if tie
}

public struct GameCompleted has copy, drop {
    game_id: ID,
    winner: address,
    points_a: u8,
    points_b: u8,
}

public fun emit_game_created(
    game_id: ID,
    creator: address,
    stake: u64,
    coin_type: TypeName,
    rounds_to_win: u8,
    whitelist: Option<address>,
    join_deadline: u64
) {
    event::emit(GameCreated {
        game_id,
        creator,
        stake,
        coin_type,
        rounds_to_win,
        whitelist,
        join_deadline
    });
}

public fun emit_round_commitment(
    game_id: ID,
    player: address,
    round: u8
) {
    event::emit(RoundCommitment {
        game_id,
        player,
        round
    });
}

public fun emit_round_revealed(
    game_id: ID,
    round: u8,
    move_a: u8,
    move_b: u8,
    winner: Option<address>
) {
    event::emit(RoundRevealed {
        game_id,
        round,
        move_a,
        move_b,
        winner
    });
}

public fun emit_game_completed(
    game_id: ID,
    winner: address,
    points_a: u8,
    points_b: u8
) {
    event::emit(GameCompleted {
        game_id,
        winner,
        points_a,
        points_b
    });
}