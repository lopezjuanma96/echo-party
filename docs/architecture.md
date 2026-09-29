# Architecture

## Principles

- Keep game rules independent from presentation where practical.
- Represent content as Godot resources rather than hard-coded scene logic.
- Keep build histories deterministic, ordered, and easy to inspect.
- Treat save compatibility as a feature before public playtests begin.
- Build only the abstractions required by the next milestone.

## Proposed Boundaries

### Domain

Plain scripts and resources for attributes, jobs, skills, level choices, build
histories, party rosters, and run results. These rules should be testable
without rendering a combat scene.

For the first-echo slice, `HeroRecord` is the only run-to-run domain object. It
owns a stable runtime ID, display name, and a deep-copied strict JSON-safe
progression document. It validates by replaying `HeroProgression`; it is held
in memory only and does not imply a roster, memorial, or save format.

### Simulation

Combat state, targeting, movement requests, cooldowns, effects, experience,
and tactical policies. Random decisions receive a seeded random source so bugs
and balance scenarios can be reproduced.

The current arena's `EnemySpawner` owns target-population replacement, safe
spawn selection, and per-enemy seeds. `Main` consumes its one-shot XP signal
but does not own enemy lifecycle or random placement.

`HeroActor` is the smallest shared combat contract for active heroes and
echoes: health, progression-derived stats, stable weapon loadouts, cooldowns,
aiming, and melee/projectile execution. Player code adds direct input,
movement, and dodge behavior. Echo code adds the deterministic tactical policy
(follow, leash-bounded target selection with stable spawn-order ties,
range-aware weapon choice, approach/retreat, and exposed intent). It reuses the
same attack semantics rather than implementing parallel weapon behavior.

### Presentation

Godot scenes for actors, animation, effects, camera, UI, and audio. Scenes read
simulation state and submit player intent; they should not own permanent hero
data.

`Main` currently coordinates the in-memory defeat transition, newest-echo-only
replacement, shared XP routing from `EnemySpawner`, and concise run/echo HUD.
This is temporary run orchestration, not persistence or roster resolution.

### Persistence

A versioned save document containing unlocks, capacity upgrades, echo records,
the active roster, memorial entries, and settings. Run-only equipment belongs
to a separate current-run state.

## Build History Shape

The exact implementation can evolve, but a hero record needs these concepts:

```text
HeroRecord
  id
  display_name
  appearance_seed
  tactical_profile
  choices[]

LevelChoice
  level
  attribute_changes[]
  learned_skill_id?
  job_change_id?
```

Stable content IDs are essential. Save data should reference `skill_id` and
`job_id`, never scene paths or translated display names.

The current prototype stores one strict choice per level: attribute entries use
`attribute_id`, while the level-3 advancement entry uses `job_id`. Weapon
definitions are Resources keyed by stable weapon IDs; display names are only
resolved by presentation code.

## Tactical AI

Start with scored actions or a small utility system shared by player and echo
abilities:

1. Gather valid actions and targets.
2. Reject actions whose range, resource, or cooldown requirements fail.
3. Score the remaining choices from job role and tactical profile.
4. Choose the highest score with deterministic tie-breaking.
5. Expose the chosen intent to the UI before execution where possible.

This makes behavior debuggable and allows designers to tune priorities without
retraining a model.

## Suggested Initial Layout

```text
assets/             Original and properly licensed third-party assets
docs/               Design decisions and roadmap
src/domain/         Hero, job, skill, roster, and run data
src/simulation/     Combat and tactical AI
src/presentation/   Actors, effects, camera, and UI
src/main/           Application entry scene
tests/              Headless domain and simulation tests
```

Only directories with actual content should be added to Git.
