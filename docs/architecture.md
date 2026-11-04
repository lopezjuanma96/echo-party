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

`HeroRecord` owns a stable runtime ID, display name, and a deep-copied strict
JSON-safe progression document. It validates by replaying `HeroProgression` and
can create an extended copy without mutating the original record. `Roster` is
the pure party, memorial, and candidate model; its slot-ordered moves implement
roster resolution without scene or file access. `RosterResolution` supplies the
default candidate destination used by `Main.resolve_default()` in tests and
tooling: first empty party slot, then first empty memorial slot, then party
slot 1. `RosterCapacity` maps persisted unlock
IDs to party and memorial capacities and reports newly earned unlocks.
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
`Enemies`, not a child. Before adding each enemy to the tree, it applies that
encounter's `enemy_overrides[enemy_id]` in a fixed allow-list order, accepting
only finite nonnegative numbers for exported float properties (`move_speed`,
`max_health`, `flee_distance`, `keep_distance`, `shot_damage`; health must be
positive), then multiplies maximum health for a large party. Unknown keys and
invalid values are ignored without RNG draws; overrides reset between runs and
never mutate scene resources or the open-arena spawner.

Ownership is split deliberately:

- the director owns the enemies it spawns, as its own children, with
  `stable_spawn_order` starting at 1_000_001, so the spawner's child-count
  population is untouched;
- the spawner owns open-arena population, and the director only pauses it
  (`set_population(0)`) for the encounter and restores the prior target after;
- optional per-wave `max_alive` gates defer a due group until occupancy falls
  to that limit; Gallery uses two survivors before four reinforcements, while
  Bell Court keeps its existing timed waves;
- the director draws pack jitter and enemy seeds from its own seeded
  `RandomNumberGenerator`, reseeded at each start;
- its counters come from signals and state, not from the HUD: casts from the
  Hexcaller's `cast_resolved` and `cast_interrupted`, damage per enemy ID from
  `dealt_damage` (hero or echo by target type), and healing from per-actor
  `total_healing_done` deltas; and
- it re-emits `enemy_defeated` so `Main` routes court XP through the same
  handler as arena kills, and emits `report_ready(report)` with a plain-data
  report when an encounter is cleared or failed. Echo identities are captured
  in slot order at encounter start so reports retain every echo's job and
  survival after its node is freed. `reset_for_new_run()` fails a running
  encounter, frees its enemies, restores spawning, and re-arms.

`Main` asks the director to trigger, supplies the party's job IDs in slot order,
and renders the Trial panel, banner, level-3 modal annotations, and report from
director state and `report_ready`. `EncounterCatalog.trial_for_hero(n)` selects
`bell_court` for odd persisted hero numbers and `slinger_gallery` for even ones.
`Main` applies this after loading progress and after incrementing the hero number
on death, before opening or restoring resolution, so the roster's Next Trial and
coverage describe the next run. The panel behind resolution excludes the fallen
hero's job. Failed reports retain the old encounter ID. Both Trials trigger at
the active hero's level 5 once choices are answered; echo levels do not trigger
them. An explicit scenario `encounter_id` overrides rotation; an empty one shows
the rotated Trial for planning but disarms automatic triggering. Clear counts
remain keyed by Trial ID, with their sum driving capacity unlocks.

Scenario scenes under `tests/scenarios/` are deterministic playtest fixtures.
They set up jobs, levels, starting health, enemy population, debug enemy
spawns, starting echo levels, and bonus XP that opens the level-up and
extension modals at once, and they register a scenario-only frame-capture action.
They use memory-only storage unless `save_slot` selects
`user://playtest_saves/<slot>.json`; `reset_save` removes that slot before
`Main` loads it. They are not part of the shipped game flow.

`AbilityCatalog` resolves stable ability IDs to `AbilityDefinition` resources;
Mend is the first immediate ability. `HeroActor` is the smallest shared combat
contract for active heroes and echoes: health, progression-derived stats,
stable weapon loadouts, attack and ability cooldowns, heal targeting, aiming,
and melee/projectile execution. Player code adds direct input, movement, and
dodge behavior. Echo code adds the deterministic tactical policy
(slot-specific follow anchors, leash-bounded target selection with stable
spawn-order ties, range-aware weapon choice, approach/retreat, and exposed
intent). It reuses the same attack semantics rather than implementing parallel
weapon behavior. Each echo owns fresh runtime `HeroProgression`, receives the
same full XP reward as the active hero and every living slot mate, and applies
the corresponding ordered choice from its `HeroRecord` when it reaches that
level. The record remains immutable. XP is never capped: levels covered by the
record replay its choices, and levels past it become pending extension levels
(`get_pending_extension_levels`, `extension_pending`) that only
`apply_extension_choice` resolves, attributes only and in order.
`extension_record()` returns `HeroRecord.extended_with` over the levels
actually chosen (unchosen levels are not recorded) or null. Level-ups refresh
stats but rebuild the loadout only for a replayed job choice, so extension
never resets cooldowns.

Echo command state is run-local and independent of the record: focus overrides
nearest-target selection while valid, hold suppresses tactical movement without
suppressing attacks, and regroup clears both until the echo reaches its follow
anchor. `PartyCommander` owns slot addressing and filtering. The wheel cycles
`All → Echo 1 → Echo 2 → All`, limited to spawned slots; commands and addressed
echo defeat return the address to `All`. `Main` translates named input actions
into these commands and presents their state; presentation does not alter build
history.

### Presentation

Godot scenes for actors, animation, effects, camera, UI, and audio. Scenes read
simulation state and submit player intent; they should not own permanent hero
data.

`Main` coordinates the defeat transition, slot-stable multi-echo spawning, full
XP routing from enemy rewards, per-slot HUD rows, and persistence orchestration.
Its `echoes` array retains slot positions with null holes after defeat; the
read-only `echo` accessor preserves the first-slot contract for existing
callers. `RosterCapacity` derives normal capacity from the document's persisted
unlock IDs; a clear updates capacity for the next resolution without spawning
anything into the current run.

Choice flow: `_pending_choice_subjects()` orders the open choices (hero, then
each living echo by slot, each with its next unchosen level) and
`_show_next_choice_if_needed()` presents the first through the shared modal,
pausing the tree. An echo choice goes through `_apply_echo_extension`, which
calls `EchoActor.apply_extension_choice`, then `Roster.replace_record` with the
new record and refreshes `EchoActor.hero_record`; the roster changes in memory
at once and is written at the next save point. A defeated echo or a defeated
hero drops any open choices. `_mcp_state()` reports `pending_choice_subjects`;
each echo's state adds `pending_extension_levels` and `record_level`.

Run flow: `_on_player_defeated` defers `_start_next_run()`, which offers the
fallen record to `Roster` (only job-holding heroes qualify), clears combat,
resets the director, frees the party, and advances the persistent hero counter.
The death save includes chosen extensions and sets `pending` with the candidate
and current Anchors when a resolution opens. If there is no candidate and the
memorial is empty it saves, shows a notice, and calls `_begin_run()` at once.
Otherwise it presents `ResolutionScreen` and pauses the tree. The screen emits
`resolved(anchors_left)` from Start; `Main` clears and saves `pending`, then
`_begin_run()` unpauses, drops unspent Anchors, resets the hero, and spawns
`roster.party` in slot order. `resolve_default()` is the headless shortcut.

`ResolutionScreen` (`src/main/resolution_screen.gd/.tscn`, process mode always)
is UI only. It reads and drives the `Roster` it is handed (`preview` before
`move`, `discard_candidate` for Anchors) and holds only selection, pending
confirmation, and the Anchor count; it never touches actors, files, or `Main`.
Rows are the candidate, party slots, and memorial slots, capped at five. Its
public methods (`select_row`, `confirm`, `discard`, `cancel`, `start`, `get_text`)
drive the same paths as the mouse and the modal-only keys, and `_mcp_state()`
exposes it under `Main._mcp_state()["resolution"]`. `Main` supplies unlock IDs
and the total Trial-clear count for its capacity hint.

Each echo has a slot-labelled world label, status overlay, and focus-marker
digit. The overlays and HUD only read echo state (`get_display_intent`,
`get_intent_summary`, cooldown fractions). The 0.25 s display dwell lives in
`EchoActor` so tests and tooling see the same intent as the player; the raw
`current_intent` stays unchanged for simulation and tests.

### Persistence

`SaveDocument` is the strict schema-v1 model for the hero counter, unlocks,
Trial clear counts, slot-ordered roster and memorial records, and an optional
pending resolution with its Anchor count. `SaveMigrations` applies the
dictionary-only version chain and rejects missing or newer versions.
`SaveStore` owns injected-path file I/O, deterministic JSON, atomic replacement,
corrupt-file backups, and read-only handling for newer saves. An empty path is
memory-only. Run state, settings, and Anchors outside a pending resolution are
not persisted.

`Main` holds the live `document: SaveDocument` and `roster_store: SaveStore`.
`save_path` defaults to `user://echo_party_save.json`; before `_ready()` loads,
a headless run using that default changes it to the empty memory-only path. The
load status (`new`, `ok`, `migrated`, `corrupt`, `too_new`) selects the document,
with HUD notices for corrupt and newer saves. Save failures also produce a
notice and never block play. A loaded `pending` entry opens the roster screen
before the first run; otherwise the saved party spawns immediately.

The write points are death after extension commits and `pending` assignment,
resolution confirmation with `pending` cleared, and a cleared Trial report. The
last increments `trial_clears` under its stable encounter ID, appends only newly
earned `RosterCapacity` unlocks, grants at most one run Anchor, shows the reward
toast, and saves. `_mcp_state()` exposes plain-typed save path/status/read-only
state, unlock strings, clear counts, the next hero number, and `pending_saved`.
Tests use memory-only Main instances or `user://test_saves/` paths and remove
their files; scenarios use only their explicit playtest slots.

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
