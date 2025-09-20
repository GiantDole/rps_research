# Questions

1. What is the best practice for Game structs? Where to store them? In a shared game object? Or does the creator own that object? I don't think the latter works because the other player needs to access the game, so it needs to be shared somehow. But if it's contained in a shared Games object, all traffic would go through that object, causing a potentially inefficient fee market. What is the best practice here? 
Game should just be a shared object to be referenced when acting upon it. This improves performance
2. What is the best approach for the frontend to keep track of open, running, cancelled, completed games?
Through events
3. Where to store all the config that needs to be accessed on every game creation and fee distribution etc? Shared config object? Is that the most efficient approach?
Yes, since its mostly read-only access

# Possible Optimizations / ToDos
1. Define public keys of kms servers on-chain

# Structs / Objects
- Config: 
    - contains admin defined config object
    - shared object
- Games:
    - object that stores all the Game structs
- Game:
    - represents a game between players
    - public shared object
    - contains both player's stake
    - contains several Rounds (as array?)
    - keeps track of the current game state (open, running, cancelled, completed)
    - keeps track of the current round number
    - could act as easy access for frontend to check for running, waiting, cancelled, or completedgames
- Round:
    - represents a round in a game
    - stores the commitments and outcome of the round

# Functions

## Game Creation

```rust
public fun createGame<T>(
    config: &Config,
    stake: Coin<T>,
    rounds: u8,
    whitelist: address,
    join_timeout: u64,
    round_timeout: u64
)
```
- Coin `T` must be suppprted
- stake amount must be in accepted bounds
- round timeout must be in accepted bounds
- join timeout has no restrictions (is this in accordance with specification?)
- rounds must be an uneven number
- round_timeout must be in acceptable bounds
- creates a new `Game` struct
- emits an event that can be tracked by frontends 

## Join Game

```rust
public fun joinGame<T>(
    stake: Coin<T>,
    game: Game
)
```
- `Coin<T>` must match other players `Type T` and must have equal amount
- game must still be valid: no timeout, game still open
- game must be joinable: either its open or the current address is contained in the whitelist
- emits an event that the game is joined
- round timeout starts
- current game status is changed
- player b is set

## Cancel Game

```rust
public fun cancelGame<T>(
    game: &mut Game
)
```
- caller must be player a
- player b cannot have joined yet
- game will be set to cancelled
- stake is returned to the player

## Commit Round
```rust
public fun playRound(
    game: &mut Game,
    action: EncryptedObject,
    reveal_a: Option<Keys>,
    reveal_b: Option<Keys>
) {

}
```

- only player can play
- game needs to be open
- make sure game is not timed out yet
- make sure round was not played yet
- For now, only allow commitments for current round. later: 
    - reveal round at the same time.
    - if this is the first move: reveal previous round
    - if this is the second move: increment round number


## Reveal Round
```rust
public fun revealRound(
    game: &mut Game,
    reveal_a: Option<Keys>,
    reveal_b: Option<Keys>
) 
```
- both players must have played in round
- reveal the previous round (round - 1)
- only if not revealed already
- if any player move invalid: they lost the game
- store the revelead action
- evaluate win and change points
- if continue: increment round number and create new round
- if game finalized: change state, ...

## Finalize Game
```rust
public fun finalizeGame(

)
```

- called when game is over
    - either when rounds played (called from reveal round)
    - or when player times out (called manually)
- game must be ACTIVE
- total wins must be reached OR player timed out
- maybe this function can be divided into external and internal functions (internal callable from reveal round as well)
- 

## Change Config

```rust
public fun addOrEditSupportedAsset(
    admincap: &AdminCap,
    config: &mut Config,
    enabled: bool,
    min_stake: u64,
    max_stake: u64,
    house_edge: u16,
    typename: TypeName
)
```


- requires AdminCap

