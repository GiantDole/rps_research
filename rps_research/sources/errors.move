module rps_research::errors;

/// Error codes
const EAssetNotAllowed: u64 = 1;
const EAssetDisabled: u64 = 2;
const EStakeTooLow: u64 = 3;
const EStakeTooHigh: u64 = 4;
const ETimeoutTooLow: u64 = 5;
const ETimeoutTooHigh: u64 = 6;
const EGameWhitelisted: u64 = 7;
const EGameNotOpen: u64 = 8;
const EGameTimedOut: u64 = 9;
const EGameUnequalStake: u64 = 10;
const EGamePlayerNotJoined: u64 = 11;
const EGameNotActive: u64 = 12;
const ERoundTimedOut: u64 = 13;
const EInvalidPlayer: u64 = 14;
const EAlreadyPlayed: u64 = 15;
const ERoundNotComplete: u64 = 16;
const EInvalidDecryptionKey: u64 = 17;
const EInvalidCommitment: u64 = 18;

/// Abort functions for each error
public fun asset_not_allowed() {
    abort EAssetNotAllowed
}

public fun asset_disabled() {
    abort EAssetDisabled
}

public fun stake_too_low() {
    abort EStakeTooLow
}

public fun stake_too_high() {
    abort EStakeTooHigh
}

public fun timeout_too_low() {
    abort ETimeoutTooLow
}

public fun timeout_too_high() {
    abort ETimeoutTooHigh
}

public fun game_whitelisted() {
    abort EGameWhitelisted
}

public fun game_not_open() {
    abort EGameNotOpen
}

public fun game_timed_out() {
    abort EGameTimedOut
}

public fun game_unequal_stake() {
    abort EGameUnequalStake
}

public fun game_player_not_joined() {
    abort EGamePlayerNotJoined
}

public fun game_not_active() {
    abort EGameNotActive
}

public fun round_timed_out() {
    abort ERoundTimedOut
}

public fun invalid_player() {
    abort EInvalidPlayer
}

public fun already_played() {
    abort EAlreadyPlayed
}

public fun round_not_complete() {
    abort ERoundNotComplete
}

public fun invalid_decryption_key() {
    abort EInvalidDecryptionKey
}

public fun invalid_commitment() {
    abort EInvalidCommitment
}