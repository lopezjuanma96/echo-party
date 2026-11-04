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
`JobCatalog` resolves stable job IDs to display names, ability IDs, tactical
postures, and capability tags (`provides`). `PartyNeeds` is the pure coverage
logic over those tags: given job IDs and need tags it returns the covered needs
with their covering job and the uncovered ones, and builds the Trial annotation
and report text fragments. It holds no nodes or state.

### Simulation

Combat state, targeting, movement requests, cooldowns, effects, experience,
and tactical policies. Random decisions receive a seeded random source so bugs
and balance scenarios can be reproduced.

The current arena's `EnemySpawner` owns target-population replacement, safe
spawn selection, per-enemy seeds, and the level-gated variant table. Variant
choice draws from a separate seeded type stream, so the position stream does
not change when types are added. `Main` sets the spawner's `threat_level` from
the active hero's level and consumes its one-shot XP signal, but does not own
enemy lifecycle or random placement.

Enemy variants extend `EnemyActor`. `EnemyCatalog` maps stable enemy IDs to
scenes. `EnemyTargeting` provides deterministic friendly-target queries over
the `friendly_actors` group, breaking ties by node name. Enemies report damage
dealt through `dealt_damage(enemy_id, target, applied)` for later encounter
reporting. Hero attacks pass an `interrupts` flag with damage, and staff
splash is applied by the bolt. `EnemyActor.is_casting()` lets targeting code ask
whether an enemy is interruptible without knowing its type; the Hexcaller
overrides it. The Slinger's dart is a separate `EnemyShot` that only hurts
friendlies and walls, reporting hits back through the Slinger's
`dealt_damage`; enemy fire never reuses `Bolt`.

`EncounterCatalog` holds static encounter data keyed by stable ID (needs,
trigger level, warning time, wave timeline, seed). `EncounterDirector` runs one
encounter through `IDLE → WARNING → ACTIVE → CLEARED` and is a sibling of
`Enemies`, not a child. Ownership is split deliberately:

- the director owns the enemies it spawns, as its own children, with
  `stable_spawn_order` starting at 1_000_001, so the spawner's child-count
  population is untouched;
- the spawner owns open-arena population, and the director only pauses it
  (`set_population(0)`) for the encounter and restores the prior target after;
- the director draws pack jitter and enemy seeds from its own seeded
  `RandomNumberGenerator`, reseeded at each start;
- its counters come from signals and state, not from the HUD: casts from the
  Hexcaller's `cast_resolved` and `cast_interrupted`, damage per enemy ID from
  `dealt_damage` (hero or echo by target type), and healing from per-actor
  `total_healing_done` deltas; and
- it re-emits `enemy_defeated` so `Main` routes court XP through the same
  handler as arena kills, and emits `report_ready(report)` with a plain-data
  report when an encounter is cleared or failed. `reset_for_new_run()` fails a
  running encounter, frees its enemies, restores spawning, and re-arms.

`Main` asks the director to trigger, supplies the party's job IDs, and renders
the Trial panel, banner, level-3 modal annotations, and report from director
state and `report_ready`.

Scenario scenes under `tests/scenarios/` are deterministic playtest fixtures.
They set up jobs, levels, starting health, enemy population, and debug enemy
spawns, and they register a scenario-only frame-capture action. They are not
part of the shipped game flow.

`AbilityCatalog` resolves stable ability IDs to `AbilityDefinition` resources;
Mend is the first immediate ability. `HeroActor` is the smallest shared combat
contract for active heroes and echoes: health, progression-derived stats,
stable weapon loadouts, attack and ability cooldowns, heal targeting, aiming,
and melee/projectile execution. Player code adds direct input, movement, and
dodge behavior. Echo code adds the deterministic tactical policy
(follow, leash-bounded target selection with stable spawn-order ties,
range-aware weapon choice, approach/retreat, and exposed intent). It reuses the
same attack semantics rather than implementing parallel weapon behavior.
Each echo owns fresh runtime `HeroProgression`, receives the same XP reward as
the active hero, and applies the corresponding ordered choice from its
`HeroRecord` when it reaches that level. The record remains immutable; runtime
progression stops at its highest fully recorded level until history extension
is implemented. Echo command state is run-local and independent of the record:
focus overrides nearest-target selection while valid, hold suppresses tactical
movement without suppressing attacks, and regroup clears both until the echo
reaches the active hero. `Main` translates named input actions into these
commands and presents their state; presentation does not alter build history.

### Presentation

Godot scenes for actors, animation, effects, camera, UI, and audio. Scenes read
simulation state and submit player intent; they should not own permanent hero
data.

`Main` currently coordinates the in-memory defeat transition, newest-echo-only
replacement, shared XP routing from `EnemySpawner`, and concise run/echo HUD.
This is temporary run orchestration, not persistence or roster resolution.

The echo's `StatusOverlay` and the HUD only read echo state (`get_display_intent`,
`get_intent_summary`, cooldown fractions). The 0.25 s display dwell lives in
`EchoActor` so tests and tooling see the same intent as the player; the raw
`current_intent` stays unchanged for simulation and tests.

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
