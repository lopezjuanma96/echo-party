# M3 Roster Roguelite Plan

Working implementation plan for milestone M3. Sonnet 5.5 drafted it (design
role). When a slice lands, its decisions move into `docs/game-design.md`,
`docs/architecture.md`, `README.md`, and `docs/roadmap.md`. This file is not the
source of truth for shipped rules.

## Coordinator Amendments

1. **User-confirmed decisions (2026-11-03).** D1 and D2 (start with 1 echo slot
   and 1 memorial slot; Trial clears unlock more), D3, D4 and D5 (only job
   heroes become candidates; refusing one costs an Echo Anchor), D7 (the wheel
   picks which echo a command goes to; `1`/`2` keep selecting weapons), and D12
   (second Trial as optional slice 7) all use the recommended defaults below.
   D6, D9 (quitting mid-run abandons it) and D13 use their defaults unless the
   user overrides them.
2. One editing implementer at a time. Checkpoint each verified slice before the
   next starts.

Carry-over rules from the M2 plan still apply:

- Playtest hooks are scenario scenes under `tests/scenarios/` plus
  `_mcp_state()` (plain `String`/number/bool/array/dict only; write
  `String(id)`, `pos_x`/`pos_y`). The playtester gets a deterministic starting
  state, never long manual steering.
- All randomness uses an injected or seeded `RandomNumberGenerator`.
- Headless tests extend `SceneTree`, collect `_failures`, and run with
  `godot --headless --path . --script res://tests/<file>.gd`.

## A. Rationale

The exit condition is: *roster decisions create meaningful tradeoffs across
several runs without an obvious dominant strategy.* Two pillars drive the plan:

- **Meaningful roster pressure (4).** Pressure only exists if something is
  scarce and someone can be lost. M3 makes three things scarce: party slots
  (earned, start at 1), memorial slots (start at 1), and the Echo Anchor (the
  only way to refuse a fallen hero). Every qualifying death forces a placement,
  so a roster is never "set and forget".
- **Readable complexity (5).** The cap stays at **2 echoes** (design: test two
  before assuming more). Commands stay party-wide by default, with one cheap
  addressing layer. The resolution screen shows, in one place, what each hero
  is, which Trial needs the roster covers, and what the player's *next* hero
  should fill. It reuses `PartyNeeds`, so the existing "build for a future
  need" loop (M2 exit) feeds the roster loop.

Tensions that make choices non-obvious (the intended design levers):

1. **Role vs strength.** A needed Mender at low level against a stronger
   redundant Arcanist.
2. **Growth vs hoarding.** Only party echoes level and extend their history.
   Memorial heroes are frozen, so storing a hero preserves it but stops its
   growth.
3. **Loss.** With party and memorial full and no Anchor, a new hero costs an
   existing one. Dying well is not free.
4. **Planning.** The next Trial's needs are visible before composing the party.

Known dominance risk (see section H): with one Trial (Bell Court needs
interrupt, area, sustain), Vanguard + Mender is always the best pair. Section F
slice 7 proposes a cheap data-only second Trial that rotates the needed pair. It
needs the user's confirmation and is not required to ship slices 1-6.

## B. Facts Verified In The Code

- `Main` (`src/main/main.gd`) owns a single `echo: EchoActor` and a single
  `latest_echo_record`. `_start_next_run()` (called deferred from
  `_on_player_defeated`) captures `HeroRecord.capture("hero-%d" % run_number,
  "Hero %d" % run_number, progression)`, frees the echo, increments
  `run_number`, resets the player, and calls `_spawn_latest_echo()`.
- Input routes straight to `echo`: `_unhandled_input` (`echo_focus`,
  `echo_regroup`, `echo_hold`) and `command_echo_focus_at`. The focus marker
  reads `echo.focused_target`. `_on_enemy_defeated` grants XP to `progression`
  and one `echo`. `_party_job_ids()` caches one record's final job and appends
  the hero's job.
- `run_number` resets to 1 every launch, so `hero-N` IDs would collide across
  sessions once records persist. M3 needs a persisted counter.
- `HeroRecord` is immutable, strict (exactly `runtime_id`, `display_name`,
  `progression`), and validates by replaying `HeroProgression.from_dict`.
  `capture` returns `null` on empty ID or name.
- `HeroProgression.from_dict` accepts whole floats as integers (JSON parses
  every number as a float) and allows `choices.size() <= level - 1`, so a
  record may carry unchosen levels. Level is unlimited. `ADVANCEMENT_LEVEL = 3`
  is the job choice; levels 2 and 4+ are `might`/`vitality`.
- `EchoActor.grant_shared_experience` caps XP at `_replay_level_limit =
  min(record level, choices + 1)`. An echo past its record simply stops. The
  extension work (roadmap item 5) removes this cap.
- Echo commands are per-instance fields (`focused_target`, `is_regrouping`,
  `is_holding_position`), so N echoes need no per-echo refactor, only an
  addressing layer. Echoes are in the `friendly_actors` group; so is the Player.
- `PartyNeeds.evaluate(job_ids, needs)` already takes an ordered job list; the
  first provider wins and empty IDs are skipped. Multi-echo coverage needs no
  change to it.
- `EncounterDirector._find_echo()` returns only the first `EchoActor`;
  `had_echo`/`echo_survived` are single booleans. `report_ready` fires once per
  finish with `outcome` (`cleared`/`failed`); that is the hook for Trial-clear
  rewards.
- Existing tests couple to `main.echo`, `main.latest_echo_record`,
  `main._start_next_run()`, and HUD strings (`echo_value`, `echo_command_value`,
  `echo_intent_value`, `echo_cooldowns_value`) in `test_echo`, `test_feedback`,
  `test_mender`, `test_encounter`. `court_matrix.gd` treats `run_number > 1` as a
  failed run, and `apply_scenario` sets `run_number = 1`.
- No file I/O exists in `src/` or `tests/` except the scenario capture folder.
  Tests instantiate `Main` freely, so a default save path would write to the
  developer's real save. A guard is mandatory (decision D9).
- The left HUD column is Instructions (y 20-247), RunStatus (259-364), and
  Progression (376-474). `_test_hud_panels_do_not_overlap` enforces 12 px gaps
  and a bottom edge at most 720.
- The mouse wheel is bound to `weapon_previous`/`weapon_next`; weapon slots also
  have `1`/`2`. `docs/exploration/multi-echo-commands.md` records the user's
  2026-10-30 proposal to move the wheel to echo addressing.
- `scenario_launcher.gd` already exports `player_job`, `echo_job`, `level`,
  `encounter_id`, health fractions, `enemy_population`, `debug_enemies`, and the
  F12 capture action.

## C. Product Decisions

Legend: **[PRODUCT]** is a design call the user must confirm; **[ENG]** is an
engineering default the implementer may take without asking. Recommended
defaults are marked **→**.

### D1. Initial party cap and slot earning [PRODUCT]

- Options: (a) start at 1 echo slot, slot 2 on the first Trial clear; (b) start
  at 2; (c) start at 1, slot 2 by reaching hero level 7.
- → **(a).** Start with 1 echo slot. The first Trial clear (any Trial) unlocks
  `party_slot_2`. **M3 hard maximum is 2 echo slots** (party = active hero + 2
  echoes). Solving a role check earns the right to bring a second role, which
  matches pillar 1. If playtests show nobody clears the Court, the lever is the
  table in `RosterCapacity.UNLOCKS`, not new rules.
- A slot unlocked mid-run is usable at the *next* resolution. Nothing joins a
  run in progress.

### D2. Memorial capacity and swapping [PRODUCT]

- → Start with **1** memorial slot; `memorial_slot_2` unlocks at the **3rd total
  Trial clear**; M3 maximum is 2.
- Swapping is allowed **only between runs, on the roster screen** (D3). Never
  mid-run.
- Memorial heroes do not gain XP, extend, or take part in runs.

### D3. When roster resolution happens (open design question) [PRODUCT]

- Options: (a) every death; (b) only after "meaningful progress"; (c) always
  show a screen.
- → **(b)**, with "meaningful" defined as **the fallen hero chose a job**
  (reached level 3, the advancement level). A hero that never advanced has no
  role and is *not* offered as a candidate; a one-line notice says so. The
  roster screen still opens whenever a candidate qualifies **or** the memorial
  holds at least one hero (so swapping stays reachable after short runs).
  Otherwise the next run starts immediately.
- Resolves the open question in `game-design.md`.

### D4. Resolution rules [PRODUCT]

A qualifying candidate must be placed before the next run. There is no free
discard.

| Action | Result |
| --- | --- |
| candidate → empty party slot | joins the party |
| candidate → empty memorial slot | stored |
| candidate → occupied party slot X | takes the slot; X goes to the first free memorial slot, else **is lost** |
| candidate → occupied memorial slot Y | takes it; Y **is lost** |
| party ↔ memorial / party ↔ party | swap (party order sets slot numbers) |
| party/memorial → empty slot of the other zone | moves |
| Discard candidate | requires one Echo Anchor (spent); roster and memorial unchanged |

Any action that loses a hero shows the hero's name and needs a second
confirming press. Lost heroes are gone for good (no undo).

### D5. Preservation item: Echo Anchor [PRODUCT]

- Stable ID `anchor`, display "Echo Anchor": spend at resolution to discard the
  fallen hero and leave the party and memorial untouched.
- **Source without M4 loot:** the active hero is granted **one Anchor when a
  Trial is cleared** (maximum 1 held). The "Anchor earned" toast appears with
  the Trial report. M4's loot tables replace this source; the item API stays.
- **Run-only:** it lives in `Main` for the run. It is saved only inside the
  `pending` resolution snapshot (D9) so quitting at the death screen cannot
  lose a hero or an Anchor. An unspent Anchor is gone when the next run begins.
- Alternatives (not chosen): a seeded Brute/Hexcaller drop (needs a pickup and
  an RNG stream); a level milestone (rewards survival, not skill).

### D6. History extension UX and persistence [PRODUCT]

- When a party echo's level passes the highest level in its record, the player
  chooses its next attribute through the **same level-up modal** (title names
  the echo: `ECHO 1 · Hero 2 (Mender) · LEVEL 6 — CHOOSE AN ATTRIBUTE`). The
  hero's choice comes first, then echoes by slot. Echoes always have a job
  (qualification rule), so extension choices are attributes.
- → **Persistence: immediate in memory, durable at the next save point.** The
  choice replaces the echo's record in the roster at once; the file is written
  at the next save point (D9). A defeated echo's extension keeps only the levels
  it chose before falling. This answers the "checkpoint" open question: failure
  still counts as progression (pillar 2).
- Alternative: commit only if the echo is alive when the hero falls (adds
  protect-your-echo pressure but punishes the choice itself). Not chosen.
- Lever if playtests report modal fatigue: move extension choices to the
  resolution screen. The domain call (`Roster.replace_record`) is identical.

### D7. Multi-echo command addressing [PRODUCT, changes a control]

- Chosen model: exploration **A + the wheel proposal (cheap B)**. `RMB` focus,
  `Q` hold, and `R` regroup apply to the *addressed* target. The mouse wheel
  cycles the address `All → Echo 1 → Echo 2 → All`. Default is `All`; the
  address **snaps back to `All` after each command** (experiment 7's safer
  variant) and whenever the addressed echo dies.
- `Q` on `All` holds everyone unless every echo is already holding, in which
  case it releases everyone.
- Weapon cycling leaves the wheel; `1`/`2` stay. The README controls list and
  `game-design.md` change in the same slice (slice 2).
- Fallback if declined: pure model A (all commands party-wide, no address).
  `PartyCommander` already supports it with `address` fixed at `All`.
- Address and each echo's slot are shown with text and shape (HUD `▶ Echo 2`,
  world label `ECHO 2`), never colour alone.

### D8. XP sharing [ENG]

- → Every living echo receives the **full** reward, as today. No split.
  Enemy XP is granted once per kill regardless of killer. A defeated echo
  stops receiving XP for the run.
- Rejected: splitting XP (echoes would rarely pass their record, so extension
  would never trigger).

### D9. What is saved, and when [ENG, one PRODUCT confirm]

- Persisted: format `version`, `next_hero_number`, earned `unlocks`,
  `trial_clears`, `roster` and `memorial` records, and `pending` (candidate
  plus Anchor count) while a resolution is open. Not persisted: run state,
  settings, Anchors outside `pending`, controls.
- Save points: (1) on death, after extensions are committed and `pending` is
  set; (2) when resolution is confirmed (`pending` cleared); (3) when an unlock
  is earned. Launching with a `pending` entry reopens the roster screen first.
- **[PRODUCT confirm]** Closing the game mid-run *abandons* the run: no
  candidate and no unsaved extensions. M3 has no "quit counts as death" rule.
- **Test isolation (mandatory):** `Main.save_path` defaults to
  `user://echo_party_save.json`, and an empty path means memory-only. A headless
  display (`DisplayServer.get_name() == "headless"`) forces memory-only when the
  default path is in use. Existing tests set `main.save_path = ""` explicitly.
  Scenario scenes use memory-only unless a `save_slot` is exported.

### D10. Trial coverage with several echoes [ENG]

- → `_party_job_ids()` returns each roster echo's **final recorded job in slot
  order**, then the hero's job. This extends M2 decision G4: coverage counts
  from run start so the player can plan. `PartyNeeds` is unchanged. A
  duplicate provider is harmless (first by slot is named).
- The Trial report names every echo (`Echo 1 Mender: survived`,
  `Echo 2 Vanguard: defeated`); the existing lumped `echo` damage column stays.

### D11. Identity [ENG]

- → Heroes keep placeholder names `Hero N`, where `N` comes from the persisted
  `next_hero_number`. Labels are `Hero 7 · Mender · Lv 6` so identical jobs are
  distinguishable by level. No renaming in M3. `HeroRecord.runtime_id` is
  `hero-N`.

### D12. Second Trial for rotation (scope) [PRODUCT]

- → **Yes, as optional slice 7, after slices 1-6 are playtested.** Data-only:
  a second `EncounterCatalog` entry whose needs a Vanguard + Mender pair does
  not cover, plus a deterministic rotation by hero number. Without it, the
  exit condition probably fails on dominance (section H). If declined, record
  "dominance risk accepted until M4" in `docs/roadmap.md`.

### D13. New inputs [PRODUCT, controls]

- Wheel addresses echoes (D7).
- Roster screen (modal, tree paused): `1`-`5` pick a row, `Backspace`/`Esc`
  cancels a selection, `X` discards with an Anchor, `Enter` starts the run, plus
  mouse buttons for everything. These are modal-only keys, not gameplay
  controls, and are documented in the README.

## D. Persistence Design

### Files (new `src/persistence/` and domain)

```text
src/domain/roster.gd              Roster (party/memorial/candidate rules, pure)
src/domain/roster_capacity.gd     RosterCapacity (unlock table → slot counts)
src/persistence/save_document.gd  SaveDocument (schema v1, strict validation)
src/persistence/save_migrations.gd SaveMigrations (version chain)
src/persistence/save_store.gd     SaveStore (file I/O, path injected)
```

None of them touches a scene or the tree. `SaveStore` only uses `FileAccess`
and `DirAccess`.

### Schema v1

```json
{
  "version": 1,
  "next_hero_number": 5,
  "unlocks": ["party_slot_2"],
  "trial_clears": {"bell_court": 2},
  "roster": [ {"runtime_id": "hero-3", "display_name": "Hero 3", "progression": {...}} ],
  "memorial": [ {...} ],
  "pending": null
}
```

`pending` is `null` or `{"candidate": <record>|null, "anchors": 0|1}`.

Rules (strict, same style as `HeroRecord.from_dict`; any violation returns
`null` and the whole file is rejected):

- Exactly the seven top-level keys; `version` equals `CURRENT_VERSION` after
  migration. All integers accept whole floats and are re-normalised to `int`
  (JSON parses numbers as floats).
- `next_hero_number >= 1` and greater than every `N` in `hero-N` runtime IDs
  present.
- `unlocks`: unique strings, each in `RosterCapacity.UNLOCK_IDS`; canonicalised
  to table order.
- `trial_clears`: keys are `EncounterCatalog` IDs, values ints `>= 0`.
- `roster.size() <= RosterCapacity.party_slots(unlocks)` and
  `memorial.size() <= RosterCapacity.memorial_slots(unlocks)`.
- Every record passes `HeroRecord.from_dict`, has `job_id != novice`, and
  runtime IDs are unique across roster, memorial, and `pending.candidate`.
- Only stable IDs: `job_id`, `attribute_id`, unlock ID, and encounter ID. No
  scene paths and no display names as keys.
- Serialisation is deterministic: `JSON.stringify(dict, "\t", true)` (sorted
  keys), arrays in slot order. A golden file round-trips byte-for-byte.

### Capacity

```gdscript
class_name RosterCapacity
const BASE_PARTY_SLOTS := 1
const BASE_MEMORIAL_SLOTS := 1
const UNLOCKS := [  # table order is canonical
	{"id": &"party_slot_2", "total_clears": 1, "party_slots": 1},
	{"id": &"memorial_slot_2", "total_clears": 3, "memorial_slots": 1},
]
static func party_slots(unlocks: Array) -> int
static func memorial_slots(unlocks: Array) -> int
static func newly_earned(unlocks: Array, total_clears: int) -> Array[StringName]
static func next_unlock(unlocks: Array, total_clears: int) -> Dictionary  # {} when none
static func hint_text(unlocks: Array, total_clears: int) -> String
```

Unlock IDs are persisted, not recomputed, so retuning thresholds never takes a
slot away. There is no third party slot in M3.

### Migration chain

```gdscript
class_name SaveMigrations
const CURRENT_VERSION := 1
## Returns {"status": &"ok"|&"migrated"|&"invalid"|&"too_new",
##          "data": Dictionary, "from_version": int}
static func migrate(raw: Variant) -> Dictionary
static func migrate_with(steps: Dictionary, current: int, raw: Variant) -> Dictionary
```

- **v0 is "no save file":** `SaveStore.load_document()` returns
  `SaveDocument.new_default()` with status `new`. M0-M2 never wrote saves, so
  there is nothing else to import.
- `steps` maps `from_version → Callable(data) -> Dictionary` and applies in
  order until `current`. Missing step, non-integer or `< 1` version → `invalid`;
  `version > current` → `too_new`. `migrate_with` is the injection point so tests
  can prove the chain with a fake v1→v2 step without a v2 schema existing.
- Rule for future steps: migrations only transform dictionaries and never call
  scene code. Add a `tests/fixtures/save_vN.json` for every shipped version.

### SaveStore

```gdscript
class_name SaveStore
extends RefCounted
func _init(new_path: String = "") -> void       # "" = memory-only
func load_document() -> Dictionary  # {"document": SaveDocument, "status": StringName}
func save_document(document: SaveDocument) -> bool
```

- Statuses: `new` (no file), `ok`, `migrated`, `corrupt`, `too_new`.
- Atomic write: write `<path>.tmp`, then `DirAccess.rename_absolute` over the
  target. Verify in the headless test that `rename_absolute` works for `user://`
  paths. If it does not, fall back to remove-then-rename.
- `corrupt`: copy the file to `<path>.corrupt` (overwriting any earlier copy),
  return a fresh default document, and surface a HUD notice. The corrupt file
  is not parsed again.
- `too_new`: return a default document, set `read_only = true`, and refuse all
  saves. A newer build's save is never overwritten.
- Tests use `SaveStore.new("user://test_saves/<name>.json")` and delete it
  afterwards. Pure schema tests use `SaveDocument.from_dict` with no file.

## E. Architecture Notes For The Runtime

- `Main` stays the orchestrator but must not grow past orchestration. New
  presentation code goes in new files: `src/main/resolution_screen.gd/.tscn`
  (UI only, driven by `Roster`) and `src/echo/party_commander.gd`.
- `Main.echoes: Array[EchoActor]` is ordered by roster slot. A read-only
  `echo` property returns `echoes[0]` or `null` so existing call sites and tests
  keep working.
- `Main` holds `document: SaveDocument` (the live save state) and
  `roster_store: SaveStore`.
- Randomness: none is added. Echo spawn offsets are fixed per slot.
- Documentation (`docs/architecture.md`): add a `Persistence` section for the
  files above; update `Domain` for `Roster`/`RosterCapacity`; update
  `Presentation` for `PartyCommander` and the resolution screen.

## F. Implementation Slices

Ordered by risk. Each slice updates the docs listed in section G for what it
lands, and finishes with the project-wide smoke test
(`godot --headless --path . --quit-after 600`) and `git diff --check`.

### Slice 1. Domain roster, capacity, save model, and migrations (no scenes)

**Goal:** the riskiest invariants (strict persistence, resolution rules) are
proven headless before any UI exists.

**Add:** `src/domain/roster.gd`, `src/domain/roster_capacity.gd`,
`src/persistence/save_document.gd`, `src/persistence/save_migrations.gd`,
`src/persistence/save_store.gd`, `tests/test_roster.gd`, `tests/test_save.gd`,
`tests/fixtures/save_v1.json`.

**Edit:** `src/domain/hero_record.gd` (add `extended_with(progression) ->
HeroRecord`, which returns a new record with the same ID and name when
`progression` strictly extends this record's choices and level, otherwise
`null`; the record itself stays immutable).

**`Roster` API:**

```gdscript
class_name Roster
extends RefCounted
const ZONE_CANDIDATE := &"candidate"
const ZONE_PARTY := &"party"
const ZONE_MEMORIAL := &"memorial"
var party: Array[HeroRecord]
var memorial: Array[HeroRecord]
var candidate: HeroRecord
func _init(party_slots: int, memorial_slots: int) -> void
func set_capacity(party_slots: int, memorial_slots: int) -> void  # never shrinks below contents
## source/dest: {"zone": StringName, "index": int}. Returns
## {"ok": bool, "reason": String, "lost_id": String}.
func move(source: Dictionary, dest: Dictionary) -> Dictionary
func preview(source: Dictionary, dest: Dictionary) -> Dictionary  # runs on a copy
func discard_candidate(anchors: int) -> Dictionary  # {"ok", "reason", "anchors_left"}
func offer_candidate(record: HeroRecord) -> bool    # false if unqualified (no job)
func replace_record(runtime_id: String, record: HeroRecord) -> bool
func party_job_ids() -> Array[StringName]           # final recorded job, slot order
func to_dict() -> Dictionary
static func from_dict(data: Variant, party_slots: int, memorial_slots: int) -> Roster
```

`move` implements the D4 table. Empty destination indices at or above the
current array size mean "append". Failures leave the roster untouched.

**Acceptance:**

- Every D4 row behaves as written, including displaced-hero routing, the
  `lost_id` result, and no-op rejection (memorial → memorial, unknown index,
  moving a hero into the zone it is already in at the same index).
- `discard_candidate` fails with 0 anchors and spends exactly one otherwise.
- `offer_candidate` rejects a novice-only record.
- The roster never exceeds capacity and `runtime_id`s stay unique.
- `SaveDocument.from_dict` accepts a valid v1 document, normalises float
  integers to `int`, and rejects every invalid case in section D.
- The golden file `tests/fixtures/save_v1.json` loads, and saving it back
  produces the identical bytes.
- Corrupt JSON, wrong version, and `too_new` produce the documented statuses
  and never overwrite the source file.

**Headless tests:** `tests/test_roster.gd` (one `_test_*` per D4 row, capacity
shrink guard, `replace_record`, `extended_with` accept and reject, duplicate-ID
rejection) and `tests/test_save.gd` (valid round-trip, each rejection reason,
float integers, `next_hero_number` below an existing `hero-N`, golden fixture,
corrupt file backup, `too_new` read-only, `migrate_with` with a fake v1→v2 step,
missing step, `SaveStore` temp-path write/read/atomic replace, memory-only
store, `RosterCapacity` tables and `newly_earned`).

**Playtest:** none (no runtime change).

### Slice 2. Multi-echo runtime, XP sharing, HUD rows, addressing, coverage

**Goal:** the game runs a party of 0-2 echoes taken from a `Roster`, with
readable commands. This slice changes no persistence and no death flow beyond
what is needed to run: on death `Main` uses an in-memory
`Roster.offer_candidate` and a test-only `RosterResolution.default_choice()`
(first empty party slot, else first empty memorial slot, else replace party slot
1). Slice 3 replaces that with the screen.

**Add:** `src/echo/party_commander.gd`, `tests/test_party.gd`, scenarios (below).

**Edit:** `src/main/main.gd`, `src/main/main.tscn`,
`src/combat/focus_target_marker.gd` (shows a slot digit; one marker per echo),
`src/echo/echo.gd` (`slot_index`, world label `ECHO 1 · Hero 2 · Lv 5`, follow
anchor offset by slot so two idle echoes settle at least 40 px apart),
`src/encounter/encounter_director.gd` (`_find_echoes()` in slot order; keep
`had_echo`; add `echo_survival: Array[bool]`; report gains
`echoes: [{slot, job_id, survived}]`; keep existing keys),
`src/player/player.gd` and `Main.DEFAULT_MOUSE_BINDINGS` (wheel →
`address_previous`/`address_next`; `weapon_previous`/`weapon_next` stay defined
with no mouse event), `tests/scenarios/scenario_launcher.gd`,
`tests/test_echo.gd`, `tests/test_feedback.gd`, `tests/test_mender.gd`,
`tests/test_encounter.gd` (string and API updates), `README.md` controls.

**`PartyCommander` (RefCounted, no nodes of its own):**

```gdscript
class_name PartyCommander
const ADDRESS_ALL := -1
var address := ADDRESS_ALL
var last_command := {}   # {"tick": int, "address": int, "verb": String, "target": String}
func cycle_address(direction: int, echo_count: int) -> void   # All → 0 → 1 → All
func addressed(echoes: Array[EchoActor]) -> Array[EchoActor]
func focus(echoes: Array[EchoActor], target: Node2D) -> int   # echoes that accepted
func regroup(echoes: Array[EchoActor]) -> int
func toggle_hold(echoes: Array[EchoActor]) -> bool            # D7 All semantics
func address_label(echoes: Array[EchoActor]) -> String        # "All" / "Echo 2 · Mender"
func on_echoes_changed(echo_count: int) -> void                # clamps address
```

Every command sets `address = ADDRESS_ALL` after running. `last_command` logs
tick (`Engine.get_physics_frames()`), address, verb, and the target's
`stable_spawn_order` as a string.

**`Main` changes:**

- `echoes: Array[EchoActor]`; `_spawn_party()` spawns `roster.party` in slot
  order at fixed offsets `[(92, 0), (-92, 0)]` from the hero; connects each
  echo's `defeated`/`progression_changed`.
- `_on_enemy_defeated` grants the full reward to the hero and every living echo.
- `_on_echo_defeated(slot)` frees that echo only and updates its HUD row to
  `Echo N: Defeated`.
- `command_echo_focus_at` keeps its click-selection logic but returns the count
  of echoes that accepted the focus.
- `_party_job_ids()` uses `roster.party_job_ids()` (D10); the cache keys on the
  roster contents.
- HUD: replace the single echo rows with one block per slot:
  `Echo 1: Mender · Level 5 · 87/100 HP`, `Command: Focus · …`, `Intent: …`,
  `Cooldowns: …`, and a `▶` prefix on the addressed echo. Rows for slots the
  save has not unlocked are hidden; an unlocked empty slot reads
  `Echo 2: empty slot`. Slot 1 keeps the existing node names; slot 2 nodes are
  duplicated. Grow the panel and shift Progression down (target: RunStatus
  259-~440, Progression ~452-~550) and update the overlap test numbers; gaps stay
  12 px and the bottom edge at most 720.
- `_mcp_state()` gains `echo_count`, `echoes` (array of per-echo
  `_mcp_state()` plus `slot`), `address`, `address_label`, `last_command`,
  `party_slots`, and `roster_party` (array of `{id, name, job_id, level}`).

**Scenario launcher:** add `@export var echo_jobs: Array[StringName]`
(empty → fall back to `echo_job`, so every existing scene keeps working),
`echo_levels: Array[int]` (empty → use `level`), and `party_slots := 1` (capacity
for the scenario's roster; must be `>= echo_jobs.size()`). `apply_scenario`
keeps its current signature and gains an optional trailing
`echo_jobs: Array[StringName] = []`, `echo_levels: Array[int] = []`.

**Scenario scenes:**

- `tests/scenarios/vanguard_mender_arcanist_5.tscn` (player vanguard, echoes
  mender + arcanist, level 5, no encounter, `enemy_population = 0`).
- `tests/scenarios/vanguard_mender_arcanist_5_court.tscn` (same, `encounter_id =
  bell_court`).
- `tests/scenarios/vanguard_mender_vanguard_5_hurt.tscn` (hero at 0.5, mender
  echo at 0.5, plus a vanguard echo; checks Mend selection with two echoes).

**Acceptance:**

- A scenario with two echoes spawns both in slot order with their recorded jobs
  and levels. Every kill advances the hero and both echoes equally.
- With address `All`, `RMB`/`Q`/`R` act on both echoes. After one wheel step the
  HUD shows `▶ Echo 1`; the command affects only echo 1, and the address returns
  to `All`.
- Both echoes' status overlays, focus markers, and HUD rows are distinguishable
  without colour (slot number, job name).
- Two idle echoes do not stack: their positions are at least 40 px apart.
- A defeated echo removes only its own HUD block's live values and stops
  receiving XP.
- `_party_job_ids()` for Mender + Vanguard echoes returns both jobs in slot
  order plus the hero's. The Trial panel shows all three needs covered for
  hero Novice.
- The Bell Court report lists both echoes' survival.
- Existing single-echo scenario scenes still start and the updated old tests
  pass.

**Headless tests (`tests/test_party.gd`):** `PartyCommander` address cycling and
clamping, `All` hold semantics (mixed → hold all, all holding → release all),
snap-back after a command, `last_command` shape, `focus` only affecting the
addressed echo, per-slot spawn offsets, full-XP sharing for two echoes, defeat of
echo 1 not removing echo 2, `_party_job_ids` slot order, HUD overlap test with
two rows, `_mcp_state` types (no `StringName`/`Vector2`/`Object`).

**Playtest (scenario `vanguard_mender_arcanist_5.tscn`):**

- Is it clear which echo is which (label, overlay, HUD row)?
- Wheel to Echo 2, `RMB` a Drifter: does only echo 2 focus? Does the HUD show
  that, and does the address visibly reset to `All`?
- Is `Q` hold readable with two echoes (does a holding Mender strand itself)?
- Do the two echoes cluster or block each other?
- Read `_mcp_state` `echoes[i].command_status`, `address`, and `last_command`.
- Run `vanguard_mender_arcanist_5_court.tscn`: is the Court clearly easier or
  harder with three jobs, and does the report name both echoes?

### Slice 3. Death → roster resolution screen, memorial storage and swapping

**Goal:** roadmap items 1 and 3 (and the Anchor consumption half of item 4)
using the Slice 1 rules, still with an in-memory document.

**Add:** `src/main/resolution_screen.gd`, `src/main/resolution_screen.tscn`,
`tests/test_resolution.gd`, scenarios (below).

**Edit:** `src/main/main.gd`, `src/main/main.tscn` (instance the screen under
`HUD`, hidden), `tests/scenarios/scenario_launcher.gd`, `README.md`,
`docs/game-design.md`, `docs/architecture.md`.

**Run flow:**

```text
_on_player_defeated (deferred) → _finish_run():
    candidate = HeroRecord.capture("hero-N", "Hero N", progression)
    qualifies = candidate != null and progression.get_job_id() != novice  # D3
    roster.offer_candidate(candidate) if qualifies
    clear transient combat, reset director, free echoes
    if roster.candidate != null or memorial non-empty:
        resolution_screen.present(roster, context)   # tree paused
        await confirmed
    _begin_run()                                     # spawn party, reset player
```

`_start_next_run()` stays as the entry point (deferred call). When no screen is
needed it falls through to `_begin_run()` immediately, so the existing tests'
timing assumption holds for non-qualifying deaths. For qualifying deaths, tests
call `main.resolve_default()` (uses `RosterResolution.default_choice`).

**`ResolutionScreen` (UI only):**

- Rows, in order: `C` Candidate, `P1`..`Pn` party slots, `M1`..`Mm` memorial
  slots (empty slots shown as `— empty —`, locked slots hidden). Each filled row
  reads `Hero 7 · Mender · Lv 6`.
- Interaction (mouse or keys `1`-`5`): choose a source row, then a destination
  row; it calls `roster.preview()` first and shows the outcome line
  (`Hero 2 → memorial · Hero 5 → lost`), and a second confirming press commits
  with `roster.move()`. `X`/button `Discard (Anchor)` calls `discard_candidate`
  and is disabled with 0 Anchors. `Enter`/`Start run` is disabled while a
  candidate is unresolved.
- Info lines: `Roster covers: INTERRUPT ✓ Vanguard · AREA ✓ Vanguard · SUSTAIN ✗`
  from `PartyNeeds.evaluate(roster.party_job_ids(), needs)`;
  `Your next hero should fill: SUSTAIN → Mender` (reuse `missing_line`);
  `Anchors: 1`; `RosterCapacity.hint_text(...)` (`Next unlock: Party slot 2 —
  clear a Trial (0/1)`); and a one-line fallen-hero summary when a candidate
  was rejected for having no job.
- Public methods for tests: `select_row(zone, index)`, `confirm()`,
  `discard()`, `start()`, `get_text() -> String`. It emits `resolved` and never
  mutates anything but its `Roster`.

**Scenario launcher:** add `start_at_resolution := false`, `fallen_job`,
`fallen_level := 4`, `memorial_jobs: Array[StringName]`, `memorial_slots := 1`,
and `anchors := 0`. `Main.apply_resolution_scenario(...)` builds the roster in
memory and presents the screen without running combat.

**Scenario scenes:**

- `tests/scenarios/resolution_room.tscn`: party slots 1 holding a Vanguard
  (level 5), memorial slots 1 empty, fallen Mender (level 5), 0 Anchors.
- `tests/scenarios/resolution_full_anchor.tscn`: party 1 (Vanguard) + memorial 1
  (Arcanist) both full, fallen Mender, 1 Anchor.
- `tests/scenarios/resolution_swap_only.tscn`: no candidate (fallen Novice),
  memorial holds an Arcanist, party holds a Vanguard.

**Acceptance:**

- A level-3+ death shows the screen; a Novice death with an empty memorial
  starts the next run directly with a notice; a Novice death with a non-empty
  memorial shows the screen with no candidate.
- Every D4 move is reachable from the screen. A move that loses a hero shows its
  name and needs a second press. `Start run` stays disabled until the candidate
  is placed or discarded.
- The coverage line updates after every move.
- After `Start`, the next run spawns exactly the final party in slot order.
- Memorial heroes never spawn.
- The tree is paused while the screen is open and unpaused after `Start`.

**Headless tests (`tests/test_resolution.gd`):** qualification threshold
(level-2 vs level-3 death), screen presence rules, each interaction through the
public methods, loss confirmation (first press previews, second commits),
Anchor discard consumes exactly one, coverage text before/after a move, party
spawned after `Start`, pause state, `_mcp_state` resolution block (`visible`,
`candidate`, `party`, `memorial`, `anchors`, `can_start`, `coverage_text`,
`outcome_text`).

**Playtest:**

- `resolution_room.tscn`: place the Mender into party slot 1. Is the loss
  warning understandable? Does the row text identify who is who?
- `resolution_full_anchor.tscn`: is the cost of each option clear (replace,
  store-and-lose, discard)? Does the Anchor count read as a scarce resource?
- `resolution_swap_only.tscn`: is swapping discoverable without a candidate?
- Does `coverage` guide the choice, or is it ignored?
- Capture the screen (F12) at 1280×720: any overlap or truncated text?

### Slice 4. History extension

**Goal:** roadmap item 5; party echoes keep growing and the player authors
their continuation.

**Add:** `tests/test_extension.gd`, scenarios (below).

**Edit:** `src/echo/echo.gd`, `src/main/main.gd`, `src/main/main.tscn` (modal
title only), `tests/test_echo.gd` and `tests/test_hero_progression.gd` (the old
"echo stops at its highest recorded level" cases), `README.md`,
`docs/game-design.md`.

**Echo changes:**

- `grant_shared_experience(amount)` no longer clamps. Levels up to the record's
  `_replay_level_limit` replay as now; levels beyond it become pending
  extension levels.
- `get_pending_extension_levels() -> Array[int]`;
  `apply_extension_choice(level, attribute_id) -> bool` (validates order through
  `HeroProgression.apply_attribute_choice`); `signal extension_pending(echo)`.
- Stats and job apply only through chosen levels. The world label shows
  `Lv 6*` while a choice is pending.
- `extension_record() -> HeroRecord`: `hero_record.extended_with(progression)`
  or `null` when nothing extended.

**Main changes:**

- Generalise the choice queue to subjects `[hero, echo 0, echo 1]` in slot
  order. `_show_next_choice_if_needed()` picks the first subject with a pending
  level; the modal title names the subject for echoes. Extension options are
  `might`/`vitality` only.
- After each applied echo choice, `roster.replace_record(id,
  echo.extension_record())` (immediate, in memory per D6).
- No XP is lost: simultaneous pendings resolve in order before the tree
  unpauses.

**Scenario launcher:** add `bonus_experience := 0`, granted through
`Main._on_enemy_defeated` after setup, so the modal opens at once.

**Scenario scenes:**

- `tests/scenarios/vanguard_mender_4_extend.tscn`: hero level 4 (Vanguard), one
  Mender echo whose record is level 4, `bonus_experience = 100` (both reach
  level 5; hero modal first, then Mender extension).
- `tests/scenarios/vanguard_mender_arcanist_4_extend2.tscn`: records at levels 4
  and 6, `bonus_experience = 200` (hero → level 6; only echo 1 passes its
  record), checking that an echo within its record never prompts.

**Acceptance:**

- An echo within its record never prompts; one past it prompts once per level.
- The hero's modal precedes echo modals; echo modals follow slot order.
- After the choice the echo's stats change (`Might` +5 attack, `Vitality` +20
  max health) and its record in the roster is longer; the previous record
  object is untouched.
- A defeated echo's roster record contains only the levels it chose.
- Next run, the extended echo replays the new choice automatically.
- A multi-level jump produces the right number of consecutive prompts.

**Headless tests (`tests/test_extension.gd`):** pending-level computation at and
past the record limit, `apply_extension_choice` ordering and rejection,
`extended_with` prefix validation (rejects divergent choices), the roster record
replaced (original unchanged), replay of an extended record in a fresh echo,
multi-subject modal order, death-then-no-further-prompts, and `Main` mcp state
`pending_choice_subjects`.

**Playtest:**

- `vanguard_mender_4_extend.tscn`: does the title make clear *whose* choice it
  is? Is the second modal acceptable or fatiguing?
- After picking Vitality, read the echo's `max_health` in `_mcp_state`.
- `...extend2.tscn`: confirm echo 2 never prompts. Is the `Lv 6*` marker
  readable?

### Slice 5. Persistence wiring, capacity unlocks, Echo Anchor award

**Goal:** roadmap items 2, 4 (source half), and 6 end to end.

**Add:** scenario scenes (below). Extend `tests/test_resolution.gd`; add
`tests/test_persistence_flow.gd`.

**Edit:** `src/main/main.gd`, `tests/scenarios/scenario_launcher.gd`,
`README.md`, `docs/*`.

**Wiring:**

- `Main.save_path` and `roster_store` per D9, including the headless guard.
  `_ready()` loads the document: `new` → default; `ok`/`migrated` → use it;
  `corrupt`/`too_new` → default plus a HUD notice (`Save unreadable — backed up
  to …` / `Save is from a newer version — progress this session will not be
  saved`). The roster capacity comes from `RosterCapacity` over `unlocks`.
- `run_number` and hero IDs use `document.next_hero_number`.
- Save points exactly as D9. Save failures show a HUD notice and never block
  play.
- Launching with `pending` set reopens the roster screen before the first run.
- `encounter_director.report_ready` with `outcome == cleared`:
  `trial_clears[encounter_id] += 1`; `RosterCapacity.newly_earned(...)` appends
  unlocks; grant one Anchor (`run_anchors = min(run_anchors + 1, 1)`); show a
  toast `Unlocked: Party slot 2 · Echo Anchor found`; save.
- `apply_scenario` and resolution scenarios use memory-only unless
  `save_slot` is exported.

**Scenario launcher:** add `save_slot: String` (empty → memory-only; otherwise
`user://playtest_saves/<save_slot>.json`) and `reset_save := true` (deletes
the slot file first).

**Scenario scenes:**

- `tests/scenarios/persist_new_slot.tscn`: `save_slot = "pw1"`, `reset_save`,
  plain Main with Vanguard hero, level 3, `enemy_population = 0`.
- `tests/scenarios/persist_reload_slot.tscn`: `save_slot = "pw1"`,
  `reset_save = false`, no scenario overrides (loads whatever the file holds).
- `tests/scenarios/vanguard_mender_5_court_clear_slot.tscn`: Vanguard + Mender,
  level 5, Court, `save_slot = "pw2"`, `reset_save`, with a
  `court_instant_clear` flag implemented as a `Main` debug method calling the
  director's clear path so the playtester can reach the unlock deterministically.
  (If the existing harness already clears the Court deterministically, use that
  instead of a new flag.)

**Acceptance:**

- First launch with no file: defaults, 1 party slot, 1 memorial slot, no file
  written until the first save point.
- After a Court clear the unlock appears in `_mcp_state.unlocks`, the file
  contains it, and the next resolution offers two party slots.
- Quit and relaunch the same slot: roster, memorial, counter, unlocks, and
  `trial_clears` are intact; hero numbering continues without reuse.
- Quit while the roster screen is open: relaunch shows the same screen with the
  same candidate and Anchor count.
- A corrupt file is backed up and replaced by defaults; a `version: 999` file is
  untouched and the session is read-only.
- Unspent Anchors do not carry into the next run.
- No test or scenario touches the real `user://echo_party_save.json`.

**Headless tests (`tests/test_persistence_flow.gd`):** `Main` with a temp
`SaveStore` through a death → resolve → relaunch cycle (second `Main` loads the
same document), pending recovery, unlock award on a synthetic `report_ready`
(including that it fires only on `cleared` and only once per threshold),
Anchor cap of 1, save failure path (read-only), headless guard on the default
path, and the `hero-N` counter.

**Playtest:**

- `persist_new_slot.tscn`: die at level 3+, resolve, stop the scene; run
  `persist_reload_slot.tscn`: is the roster restored exactly (read
  `_mcp_state.roster_party`, `memorial`, `next_hero_number`)?
- `vanguard_mender_5_court_clear_slot.tscn`: after the clear, is the toast
  readable and visible long enough? Does the report mention the Anchor?
- Is `Next unlock: …` on the roster screen informative?

### Slice 6. Balance, docs closure, and dominance check

**Goal:** evidence for the exit condition, plus all documentation.

**Edit:** `tests/court_matrix.gd` (accept 2-echo scenes and a roster-level
parameter), `docs/game-design.md`, `docs/architecture.md`, `docs/roadmap.md`,
`README.md`, this plan (tuning log).

**Work:**

- Extend the matrix with party scenes `vanguard_mender_arcanist_5_court`,
  `vanguard_mender_vanguard_5_court`, `arcanist_mender_vanguard_5_court`, and
  roster levels 4 vs 7, using the same bot and recording the same columns plus
  `echoes lost`.
- Review these questions with the numbers: does a third job make the Court
  trivial? Does a level-7 redundant echo beat a level-4 needed one? If a single
  composition clears with a large margin in every ordering, apply one of the
  levers (below) and re-run.
- Record a short tuning log.

**Levers (pick at most two, only from evidence):**

1. Court enemy HP/damage scaled up when `echo_count == 2` (a tighter trial for
   the larger party).
2. Raise `memorial_slot_2` to the 4th clear or lower to the 2nd.
3. A smaller extension supply: only every other level past the record prompts.
4. D12's second Trial (slice 7) if the matrix shows one pair dominating.

**Acceptance:** full headless suite green; matrix table in the tuning log;
roadmap marks each M3 item as implemented or defers it with a reason; docs
match the shipped rules.

### Slice 7 (optional, needs D12): Second Trial and rotation

**Goal:** make memorial swapping and slot choice matter by rotating which pair
the Trial rewards.

**Add:** an `EncounterCatalog` entry (suggested ID `slinger_gallery`, needs
`interrupt`, `area`, `range`, so Vanguard + Arcanist covers it and Vanguard +
Mender does not), a wave list built from existing enemies (Slingers and
Hexcallers at distance, Skitter packs), a seed, and scenarios
`tests/scenarios/vanguard_arcanist_5_gallery.tscn` and
`mender_vanguard_5_gallery.tscn`. `EncounterCatalog.trial_for_hero(n)`
returns the Trial for hero number `n` (odd → `bell_court`, even →
`slinger_gallery`, deterministic). `Main` sets `encounter_director.encounter_id`
at run start. The roster screen line becomes
`Next Trial: Slinger Gallery (INTERRUPT AREA RANGE)`.

**Acceptance:** each Trial's needs are covered by a distinct best pair in the
matrix; the Trial panel, level-3 modal annotations, and report work for both;
`trial_clears` counts both. Tune with the bot matrix as in M2 (idle and bot
rows).

**Playtest:** from `resolution_room.tscn`-style scenes with the Gallery as the
next Trial, does the player move heroes between party and memorial to match the
need?

## G. Documentation Updates (per slice)

| Slice | `game-design.md` | `architecture.md` | `README.md` | `roadmap.md` |
| --- | --- | --- | --- | --- |
| 1 | Vocabulary: party/memorial capacities; Persistence rules summary | Domain: `Roster`, `RosterCapacity`; new Persistence section (schema, migrations, `SaveStore`) | Add `test_roster`/`test_save` to the test list | M3 item 6 started |
| 2 | Echo Commands: addressing, wheel, `All` hold semantics; replace "more than one echo at a time" in Non-Goals; rewrite the First-Echo Vertical Slice paragraph | Presentation: `PartyCommander`, `Main.echoes`; director multi-echo | Controls (wheel), HUD, scenario list, `test_party` | note multi-echo |
| 3 | Death And Roster Resolution (rules D3-D5, table D4); answer the "after every death?" open question | Presentation: resolution screen | Resolution screen, modal keys | items 1 and 3 |
| 4 | Echo Rules: extension UX and persistence (D6); answer the checkpoint open question; remove "stops at highest recorded level" | `Echo` runtime extension flow | Extension description, scenarios | item 5 |
| 5 | Progression Layers: shipped caps (D1, D2), Anchor source (D5) | Persistence: save points, test isolation, startup flow | Save location, test list, scenarios | items 2, 4, 6 |
| 6 | Final balance notes | Final boundaries | Matrix commands | Status paragraph, exit-condition evidence |
| 7 | Second Trial section | Rotation | Scenario list | note |

Open Design Questions in `game-design.md` that M3 answers (remove or mark
resolved): extension persistence, roster resolution frequency, and party size
for M3 (leave "what size remains readable" open for M4+).

## H. Risks And Open Questions

- **Dominance risk:** with one Trial, Vanguard + Mender is optimal; only levels
  and survival differentiate. Mitigations: slice 6 matrix and slice 7.
- **Equal XP makes levels converge:** hero and echoes gain the same XP, so
  extended echoes catch up to the hero's level. The role-vs-strength tension
  then rests on jobs and on early echo losses, not on raw level. Watch in the
  matrix.
- **Modal fatigue:** up to three consecutive choice modals per level when both
  echoes are past their records. Lever in D6.
- **Wheel remap:** it removes weapon cycling from the wheel. If the user rejects
  it, use model A only; the plan's other parts do not change.
- **Unlock pace:** the first Trial clear gates slot 2. If testers cannot clear
  the Court (M2's bot shows thin clears for some orders), the unlock is unreachable.
  The knob is `RosterCapacity.UNLOCKS`.
- **Test isolation:** a missed `save_path = ""` in a test writes to the real
  save. The headless guard is the backstop; reviewers must check it.
- **Abandon rule:** closing mid-run discards extensions and the run. Confirm in
  D9.
- **Atomic rename on `user://`:** verify `DirAccess.rename_absolute` in the
  slice 1 test; fall back as documented.
- **Existing-test churn in slice 2:** four test files assert on `main.echo` and
  HUD strings. Keep the `echo` alias and plan the string edits in the same slice.

## I. What M3 Should NOT Do

- No M4 systems: no equipment, consumables beyond the Anchor, loot tables,
  pickups, rooms, bosses, or audio.
- No parties larger than 2 echoes, no third party slot, no third memorial slot.
- No formation tools, role-group addressing, command wheel, pause/slow-time
  command UI, or gambit/standing-order editor.
- No new jobs, skills, or attributes; extension uses `might`/`vitality`.
- No hero renaming, appearance, tactical-profile dials, or settings in the save.
- No imitation learning, no online features.
- No speculative frameworks: no generic inventory, event bus, or command log
  beyond `last_command`.
- No scene paths or display names in saved data; no mutation of `.godot/`.
- No commits, pushes, or PRs without explicit user instruction.

## Tuning Log (Slice 6)

All runs used Godot 4.7.2 with the real scenario scenes, a 60 Hz fixed physics
step, and the unchanged Court rules. Echo HP values are in party-slot order;
`echoes lost` includes the earliest loss time. The level override skips the
solo scenario because it has no echo to override.

### Default bot, choices answered with Might

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
```

```text
Bell Court matrix (deterministic player bot, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.6s          65       65/15     0              1/0        0        0
arcanist_mender               hero      CLEARED   13.8s          120      95        0              2/0        30       0
arcanist_mender_vanguard      hero      CLEARED   13.9s          120      65/65     0              1/1        105      0
mender_arcanist_arcanist      hero      CLEARED   13.8s          95       120/120   0              1/1        30       0
mender_vanguard               hero      CLEARED   13.5s          95       70        0              1/1        80       0
vanguard_arcanist             hero      CLEARED   13.5s          20       65        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.5s          20       0         1 @ 6.7s       1/1        50       0
vanguard_mender_arcanist      hero      CLEARED   13.4s          75       65/120    0              1/1        110      0
vanguard_mender_vanguard      hero      CLEARED   13.7s          70       95/62     0              1/1        80       0
vanguard_solo                 hero      FAILED    4.9s           15       -         -              1/0        0        7
vanguard_vanguard             hero      FAILED    5.6s           15       15        0              1/0        0        6
```

### Bot with choices left unanswered

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --leave-choices
```

```text
Bell Court matrix (deterministic player bot, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   14.7s          65       65/15     0              1/1        0        0
arcanist_mender               hero      FAILED    28.2s          15       0         1 @ 24.2s      7/0        120      1
arcanist_mender_vanguard      hero      CLEARED   15.0s          120      95/65     0              1/1        135      0
mender_arcanist_arcanist      hero      TIMEOUT   61.0s          95       20/120    0              15/0       315      1
mender_vanguard               hero      CLEARED   14.6s          95       80        0              1/1        140      0
vanguard_arcanist             hero      CLEARED   13.5s          20       65        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.5s          20       0         1 @ 6.7s       1/1        50       0
vanguard_mender_arcanist      hero      CLEARED   13.7s          75       65/120    0              1/1        110      0
vanguard_mender_vanguard      hero      CLEARED   13.7s          70       95/70     0              1/1        80       0
vanguard_solo                 hero      FAILED    4.9s           15       -         -              1/0        0        7
vanguard_vanguard             hero      FAILED    5.6s           15       15        0              1/0        0        6
```

### Bot with level-4 echoes

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=4
```

```text
Bell Court matrix (deterministic player bot, echo level 4, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.9s          65       45/0      1 @ 4.0s       1/1        0        0
arcanist_mender               hero      CLEARED   13.8s          120      75        0              2/0        30       0
arcanist_mender_vanguard      hero      CLEARED   13.9s          65       75/45     0              1/1        80       0
mender_arcanist_arcanist      hero      CLEARED   13.8s          95       100/100   0              1/1        30       0
mender_vanguard               hero      CLEARED   13.5s          65       100       0              1/1        100      0
vanguard_arcanist             hero      CLEARED   13.5s          20       45        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.5s          20       0         1 @ 4.9s       1/1        50       0
vanguard_mender_arcanist      hero      CLEARED   13.4s          75       45/100    0              1/1        110      0
vanguard_mender_vanguard      hero      CLEARED   13.7s          80       45/92     0              1/1        110      0
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    5.6s           15       0         1 @ 4.0s       1/0        0        6
```

### Bot with level-7 echoes

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=7
```

```text
Bell Court matrix (deterministic player bot, echo level 7, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.6s          65       85/35     0              1/0        0        0
arcanist_mender               hero      CLEARED   13.9s          120      85        0              2/0        0        0
arcanist_mender_vanguard      hero      CLEARED   13.9s          120      85/95     0              1/0        115      0
mender_arcanist_arcanist      hero      CLEARED   13.6s          95       85/140    0              1/0        30       0
mender_vanguard               hero      CLEARED   13.4s          95       100       0              1/1        90       0
vanguard_arcanist             hero      CLEARED   13.7s          62       85        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.4s          120      85        0              1/1        100      0
vanguard_mender_arcanist      hero      CLEARED   13.5s          75       85/140    0              1/1        110      0
vanguard_mender_vanguard      hero      CLEARED   13.6s          70       85/140    0              1/1        108      0
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    5.6s           15       35        0              1/0        0        6
```

### Idle player

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
```

```text
Bell Court matrix (idle player, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    idle      FAILED    8.0s           15       65/20     0              2/0        0        5
arcanist_mender               idle      FAILED    9.0s           7        0         1 @ 8.1s       2/0        55       7
arcanist_mender_vanguard      idle      FAILED    8.0s           15       65/62     0              2/0        50       4
mender_arcanist_arcanist      idle      FAILED    9.1s           7        65/120    0              2/0        0        4
mender_vanguard               idle      FAILED    8.5s           7        0         1 @ 7.3s       2/0        0        7
vanguard_arcanist             idle      FAILED    9.0s           7        10        0              2/0        0        6
vanguard_mender               idle      FAILED    9.0s           7        0         1 @ 8.1s       2/0        55       7
vanguard_mender_arcanist      idle      FAILED    9.5s           7        15/120    0              2/0        55       4
vanguard_mender_vanguard      idle      FAILED    8.0s           15       65/62     0              2/0        50       4
vanguard_solo                 idle      FAILED    8.5s           7        -         -              2/0        0        7
vanguard_vanguard             idle      FAILED    8.5s           7        0         1 @ 7.3s       2/0        0        7
```

### Observations

- Every two-echo composition clears the default bot run in 13.4–13.9 s with 65–120 hero HP and no losses; the one-echo Vanguard+Mender and Vanguard+Arcanist rows finish with 20 hero HP, and Vanguard+Vanguard fails.
- Adding Arcanist to Vanguard+Mender changes its default result from 20 hero HP and a dead echo to 75 hero HP with 65/120 echo HP, so the third job makes this bot matchup substantially safer.
- A level-7 redundant Vanguard does not beat a level-4 needed Mender: Vanguard+Vanguard still fails at 5.6 s with six enemies left, while level-4 Vanguard+Mender clears at 13.5 s with 20 hero HP and one echo lost.
- The level-7 second Vanguard in Vanguard+Mender+Vanguard also does not improve clear time over the level-4 Vanguard+Mender+Arcanist party (13.6 s versus 13.4 s, with 70 versus 75 hero HP).
- Vanguard+Mender clears in both tested hero orders at levels 4, 5, and 7; its thinnest margin is level-4 Vanguard hero at 20 HP with the Mender dead, versus 65/100 HP in the reverse order.
- All four added two-echo parties clear the default, level-4, and level-7 bot tables; Mender+Arcanist+Arcanist is the only one that times out when choices are left open.
- No composition dominates every mode because every idle row fails; among bot runs, Vanguard+Mender+Arcanist has the steadiest high-HP coverage, but Vanguard+Mender+Vanguard and Arcanist+Arcanist+Vanguard also clear all four bot tables.
- These numbers point to lever 1 (scale Court enemy HP/damage when `echo_count == 2`); they do not establish a need for levers 2, 3, or 4.

### Slice 6b

The `bell_court.large_party` catalog entry applies when at least two echoes are
present at encounter start. It adds Hexcallers at t=0 at (-340, -150) and
(400, -250), a Brute at t=8 at (120, 250), and sets
`enemy_health_multiplier = 1.25`; enemy damage is unchanged. Zero- and one-echo
Courts use only the original waves and stats.

Six default-matrix configurations were tried: two extra enemies at health 1.0
and 1.5, then the third Hexcaller at health 1.25, 1.35, 1.30, and 1.27. The
1.25 table below was selected as the closest overall match to the targets.

#### Default bot, choices answered with Might

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
```

```text
Bell Court matrix (deterministic player bot, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.1s          10       10/62     0              3/4        0        0
arcanist_mender               hero      CLEARED   13.8s          120      95        0              2/0        30       0
arcanist_mender_vanguard      hero      CLEARED   13.7s          120      65/120    0              4/4        113      0
mender_arcanist_arcanist      hero      CLEARED   15.2s          40       65/15     0              9/0        90       0
mender_vanguard               hero      CLEARED   13.5s          95       70        0              1/1        80       0
vanguard_arcanist             hero      CLEARED   13.5s          20       65        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.5s          20       0         1 @ 6.7s       1/1        50       0
vanguard_mender_arcanist      hero      CLEARED   14.5s          25       40/65     0              4/5        90       0
vanguard_mender_vanguard      hero      CLEARED   14.3s          67       95/15     0              4/4        90       0
vanguard_solo                 hero      FAILED    4.9s           15       -         -              1/0        0        7
vanguard_vanguard             hero      FAILED    5.6s           15       15        0              1/0        0        6
```

#### Bot with level-4 echoes

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=4
```

```text
Bell Court matrix (deterministic player bot, echo level 4, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.6s          10       0/42      1 @ 8.1s       3/4        0        0
arcanist_mender               hero      CLEARED   13.8s          120      75        0              2/0        30       0
arcanist_mender_vanguard      hero      CLEARED   13.7s          65       75/100    0              4/4        88       0
mender_arcanist_arcanist      hero      CLEARED   17.1s          70       45/0      1 @ 12.1s      10/0       115      0
mender_vanguard               hero      CLEARED   13.5s          65       100       0              1/1        100      0
vanguard_arcanist             hero      CLEARED   13.5s          20       45        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.5s          20       0         1 @ 4.9s       1/1        50       0
vanguard_mender_arcanist      hero      CLEARED   14.5s          25       20/45     0              4/5        90       0
vanguard_mender_vanguard      hero      FAILED    8.7s           7        75/0      1 @ 8.1s       4/2        30       4
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    5.6s           15       0         1 @ 4.0s       1/0        0        6
```

#### Bot with level-7 echoes

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=7
```

```text
Bell Court matrix (deterministic player bot, echo level 7, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.1s          10       30/82     0              3/4        0        0
arcanist_mender               hero      CLEARED   13.9s          120      85        0              2/0        0        0
arcanist_mender_vanguard      hero      CLEARED   14.7s          120      85/82     0              3/4        110      0
mender_arcanist_arcanist      hero      CLEARED   14.9s          95       85/90     0              5/3        90       0
mender_vanguard               hero      CLEARED   13.4s          95       100       0              1/1        90       0
vanguard_arcanist             hero      CLEARED   13.7s          62       85        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.4s          120      85        0              1/1        100      0
vanguard_mender_arcanist      hero      CLEARED   13.3s          65       60/85     0              4/3        80       0
vanguard_mender_vanguard      hero      CLEARED   14.4s          57       85/95     0              4/4        110      0
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    5.6s           15       35        0              1/0        0        6
```

#### Idle player

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
```

```text
Bell Court matrix (idle player, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    idle      FAILED    8.0s           15       65/0      1 @ 7.3s       4/3        0        10
arcanist_mender               idle      FAILED    9.0s           7        0         1 @ 8.1s       2/0        55       7
arcanist_mender_vanguard      idle      FAILED    9.0s           15       10/0      1 @ 7.3s       4/3        55       10
mender_arcanist_arcanist      idle      FAILED    8.0s           15       65/65     0              6/0        0        7
mender_vanguard               idle      FAILED    8.5s           7        0         1 @ 7.3s       2/0        0        7
vanguard_arcanist             idle      FAILED    9.0s           7        10        0              2/0        0        6
vanguard_mender               idle      FAILED    9.0s           7        0         1 @ 8.1s       2/0        55       7
vanguard_mender_arcanist      idle      FAILED    9.0s           7        0/65      1 @ 8.1s       6/0        55       6
vanguard_mender_vanguard      idle      FAILED    9.0s           15       10/0      1 @ 7.3s       4/3        55       10
vanguard_solo                 idle      FAILED    8.5s           7        -         -              2/0        0        7
vanguard_vanguard             idle      FAILED    8.5s           7        0         1 @ 7.3s       2/0        0        7
```

#### Observations

- All three covered two-echo parties clear at levels 5 and 7; the default margins range from 25 to 120 hero HP instead of the previous uniform 65–120 HP.
- At level 4, Vanguard+Mender+Arcanist clears at 25 HP and Arcanist+Mender+Vanguard at 65 HP, but Vanguard+Mender+Vanguard fails at 8.7 s, so the level-4 target is only partly met.
- Arcanist+Arcanist+Vanguard meets the missing-need target with a 10-HP default clear; Mender+Arcanist+Arcanist clears at 40 HP with no echo lost, missing the level-5 thin-clear threshold.
- Every zero- and one-echo row is identical to the corresponding pre-6b default, level-4, level-7, and idle tables.
- Every idle row still fails.

### Slice 6b coordinator amendment (supersedes the tables above)

The coordinator moved the three large-party spawns, because the original
positions overlapped HUD panels with the player at the arena centre: at
(-340, -150) a Hexcaller sat inside the controls panel, at (400, -250) its
break ring overlapped the Health panel, and at (120, 250) a Brute touched the
weapon panel. The shipped positions are Hexcallers at (-330, 250) and
(520, -40), and a Brute at t=8 at (300, 250). The 1.25 health multiplier is
unchanged. Final tables:

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
```

```text
Bell Court matrix (deterministic player bot, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.1s          10       10/49     0              3/3        0        0
arcanist_mender               hero      CLEARED   13.8s          120      95        0              2/0        30       0
arcanist_mender_vanguard      hero      CLEARED   15.8s          120      0/0       2 @ 10.6s      5/3        85       0
mender_arcanist_arcanist      hero      CLEARED   15.5s          40       65/15     0              8/2        90       0
mender_vanguard               hero      CLEARED   13.5s          95       70        0              1/1        80       0
vanguard_arcanist             hero      CLEARED   13.5s          20       65        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.5s          20       0         1 @ 6.7s       1/1        50       0
vanguard_mender_arcanist      hero      CLEARED   13.6s          104      95/120    0              3/4        85       0
vanguard_mender_vanguard      hero      CLEARED   14.2s          25       40/57     0              4/5        90       0
vanguard_solo                 hero      FAILED    4.9s           15       -         -              1/0        0        7
vanguard_vanguard             hero      FAILED    5.6s           15       15        0              1/0        0        6
```

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=4
```

```text
Bell Court matrix (deterministic player bot, echo level 4, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.8s          10       0/21      1 @ 8.1s       3/3        0        0
arcanist_mender               hero      CLEARED   13.8s          120      75        0              2/0        30       0
arcanist_mender_vanguard      hero      CLEARED   15.8s          65       0/0       2 @ 10.6s      5/3        60       0
mender_arcanist_arcanist      hero      CLEARED   16.2s          70       45/0      1 @ 12.1s      8/2        115      0
mender_vanguard               hero      CLEARED   13.5s          65       100       0              1/1        100      0
vanguard_arcanist             hero      CLEARED   13.5s          20       45        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.5s          20       0         1 @ 4.9s       1/1        50       0
vanguard_mender_arcanist      hero      CLEARED   13.6s          104      75/100    0              3/4        85       0
vanguard_mender_vanguard      hero      CLEARED   14.2s          25       20/37     0              4/5        90       0
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    5.6s           15       0         1 @ 4.0s       1/0        0        6
```

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=7
```

```text
Bell Court matrix (deterministic player bot, echo level 7, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    hero      CLEARED   13.1s          10       30/69     0              3/3        0        0
arcanist_mender               hero      CLEARED   13.9s          120      85        0              2/0        0        0
arcanist_mender_vanguard      hero      CLEARED   13.9s          120      60/11     0              4/3        85       0
mender_arcanist_arcanist      hero      FAILED    12.1s          40       85/90     0              6/2        90       5
mender_vanguard               hero      CLEARED   13.4s          95       100       0              1/1        90       0
vanguard_arcanist             hero      CLEARED   13.7s          62       85        0              1/1        0        0
vanguard_mender               hero      CLEARED   13.4s          120      85        0              1/1        100      0
vanguard_mender_arcanist      hero      CLEARED   13.5s          54       85/85     0              4/3        0        0
vanguard_mender_vanguard      hero      CLEARED   14.2s          62       90/77     0              4/4        60       0
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    5.6s           15       35        0              1/0        0        6
```

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
```

```text
Bell Court matrix (idle player, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_arcanist_vanguard    idle      FAILED    6.5s           15       65/104    0              2/1        0        6
arcanist_mender               idle      FAILED    9.0s           7        0         1 @ 8.1s       2/0        55       7
arcanist_mender_vanguard      idle      FAILED    8.0s           20       65/104    0              4/1        55       5
mender_arcanist_arcanist      idle      FAILED    8.0s           15       65/65     0              6/0        0        7
mender_vanguard               idle      FAILED    8.5s           7        0         1 @ 7.3s       2/0        0        7
vanguard_arcanist             idle      FAILED    9.0s           7        10        0              2/0        0        6
vanguard_mender               idle      FAILED    9.0s           7        0         1 @ 8.1s       2/0        55       7
vanguard_mender_arcanist      idle      FAILED    9.0s           7        0/65      1 @ 8.1s       6/0        55       6
vanguard_mender_vanguard      idle      FAILED    8.0s           20       65/104    0              4/1        55       5
vanguard_solo                 idle      FAILED    8.5s           7        -         -              2/0        0        7
vanguard_vanguard             idle      FAILED    8.5s           7        0         1 @ 7.3s       2/0        0        7
```

Observations:

- Parties that cover all three needs clear at echo levels 4, 5 and 7.
  Vanguard + Mender + Vanguard now also clears at level 4 (25 hero HP).
- Missing sustain (Arcanist + Arcanist + Vanguard) clears only thinly, with 10
  hero HP at every level.
- Missing interrupt (Mender + Arcanist + Arcanist) still clears at levels 4 and
  5, with 40–70 hero HP and 8 casts landed, and fails at level 7. The bot is a
  noisy proxy for this party; human playtests decide whether Hexcaller pressure
  needs another lever.
- Every zero- and one-echo row matches the pre-6b tables, and every idle row
  fails.

### Slice 7

Finished `slinger_gallery` and deterministic hero-number rotation: odd heroes
face Bell Court, even heroes face Slinger Gallery. Explicit scenario encounter
IDs still override rotation. Resolution (including restored pending saves), the
Trial panel, job annotations and coverage use the selected upcoming Trial;
failure reports keep the old Trial identity. Clear counts persist by stable ID
and their sum drives slot unlocks.

Six default-bot configurations were tried, counting the resumed starting layout
as the first: separated/repositioned opening crossfire; expanded crossfire; two
more Hexcallers; the selected HUD-safe seven-Slinger/seven-Hexcaller opening at
1.5 large-party health; an opening Brute; then the Brute delayed to t=8. The last
two made Arcanist + Vanguard fail, so configuration four was restored. No global
enemy, weapon, bot, XP, Bell Court or director simulation rules were changed.
The default rerun below exactly matches that selected configuration.

Final Gallery data (all positions are world coordinates):

- Seed 9203; trigger active-hero level 5 after choices; warning 3 s; grace 1 s;
  pack jitter radius 40 px.
- t=0 Slingers: (300, 40), (200, -140), (-180, 260), (540, 60), (-440, 280),
  (240, 280), (540, -30).
- t=0 Hexcallers: (-540, 280), (540, 150), (-100, -100), (-330, 270),
  (120, -90), (80, 20), (220, -30).
- t=4: four Skitters centred on (450, 260).
- t=8: Slingers at (-150, -20), (350, -30); Hexcaller at (330, 260).
- At least two echoes at start: extra t=0 Slinger at (440, -30), all enemy max
  health ×1.5 (Slinger/Skitter 67.5, Hexcaller 210), damage unchanged. Zero or
  one echo gets the base waves and health. Base/large totals: 21/22 enemies,
  1130/1180 kill XP. Automated bounds cover the full jitter disk, body + 40 px,
  and Hexcaller break ring/cast bar against all supplied HUD rectangles.

#### Default bot, choices answered with Might

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
```

```text
Slinger Gallery matrix (deterministic player bot, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   12.0s          97       53        0              4/6        90       0
arcanist_vanguard             hero      CLEARED   13.9s          9        0         1 @ 8.2s       2/8        0        0
mender_vanguard               hero      CLEARED   15.2s          41       70        0              5/7        60       0
vanguard_arcanist             hero      CLEARED   12.1s          120      9         0              4/7        0        0
vanguard_mender               hero      CLEARED   15.7s          56       0         1 @ 12.1s      6/8        60       0
vanguard_mender_arcanist      hero      CLEARED   14.5s          78       25/56     0              6/9        90       0
vanguard_mender_vanguard      hero      CLEARED   14.5s          78       0/120     1 @ 12.1s      6/10       30       0
vanguard_solo                 hero      FAILED    9.1s           50       -         -              5/7        0        16
vanguard_vanguard             hero      CLEARED   13.7s          106      42        0              5/7        0        0
```

#### Idle player

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
```

```text
Slinger Gallery matrix (idle player, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               idle      FAILED    9.5s           7        12        0              11/1       30       17
arcanist_vanguard             idle      FAILED    8.0s           37       27        0              7/7        0        20
mender_vanguard               idle      FAILED    8.0s           37       27        0              7/7        0        20
vanguard_arcanist             idle      FAILED    8.0s           37       9         0              9/2        0        13
vanguard_mender               idle      FAILED    9.5s           7        12        0              11/1       30       17
vanguard_mender_arcanist      idle      FAILED    12.0s          1        14/0      1 @ 8.1s       9/5        60       12
vanguard_mender_vanguard      idle      FAILED    12.1s          14       0/76      1 @ 8.1s       8/12       60       15
vanguard_solo                 idle      FAILED    8.9s           1        -         -              14/0       0        21
vanguard_vanguard             idle      FAILED    8.0s           37       27        0              7/7        0        20
```

#### Bot with level-4 echoes

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=4
```

```text
Slinger Gallery matrix (deterministic player bot, echo level 4, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   11.2s          102      58        0              4/5        120      0
arcanist_vanguard             hero      FAILED    10.6s          51       0         1 @ 7.7s       3/7        0        6
mender_vanguard               hero      CLEARED   15.2s          41       50        0              5/7        60       0
vanguard_arcanist             hero      CLEARED   12.5s          120      0         1 @ 10.6s      4/7        0        0
vanguard_mender               hero      CLEARED   16.9s          42       0         1 @ 8.1s       6/8        30       0
vanguard_mender_arcanist      hero      CLEARED   14.5s          78       5/36      0              6/9        90       0
vanguard_mender_vanguard      hero      CLEARED   14.5s          92       0/72      1 @ 12.1s      6/10       30       0
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      CLEARED   13.7s          106      22        0              5/7        0        0
```

#### Bot with level-7 echoes

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=7
```

```text
Slinger Gallery matrix (deterministic player bot, echo level 7, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   12.0s          97       98        0              3/7        60       0
arcanist_vanguard             hero      CLEARED   16.0s          23       35        0              2/7        0        0
mender_vanguard               hero      CLEARED   15.2s          41       90        0              5/6        60       0
vanguard_arcanist             hero      CLEARED   12.0s          120      29        0              4/7        0        0
vanguard_mender               hero      CLEARED   15.7s          56       0         1 @ 12.1s      6/8        60       0
vanguard_mender_arcanist      hero      CLEARED   14.5s          78       45/76     0              6/9        90       0
vanguard_mender_vanguard      hero      CLEARED   15.2s          70       0/98      1 @ 13.1s      6/9        30       0
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      CLEARED   17.7s          106      48        0              5/6        0        0
```

Observations and target assessment:

- **(a) Met in the reference mode:** Vanguard + Arcanist clears at 12.1 s
  (120/9 HP); Arcanist + Vanguard clears at 13.9 s (9 hero HP, echo lost).
  Both orders also clear at echo level 7, but the reverse order fails at level
  4 (10.6 s). Job coverage alone does not guarantee survival.
- **(b) Partly met:** Vanguard + Mender loses its echo at levels 4, 5 and 7;
  solo fails. Mender + Vanguard stays at 41 hero HP without losses and
  Vanguard + Vanguard at 106 HP without losses at all three echo levels, so
  those two missing-range parties miss the fail/thin-clear target. Adding a
  Brute broke the desired pair's reverse order; the selected configuration
  preserves that reference clear instead.
- **(c) Met:** Vanguard + Mender + Arcanist clears with 78 hero HP and no
  losses at all three echo levels. Vanguard + Mender + Vanguard clears with
  the Mender lost at all three levels, meeting the thin-clear definition.
- **(d) Met:** all nine Gallery idle rows fail (8.0–12.1 s). Arcanist + Mender
  can clear the bot rows without the interrupt tag, because damage can also
  break casts; this remains another balance/playtest caveat.
- **(e) Met:** the complete Bell Court tables are byte-identical to the Slice
  6b coordinator amendment for default, idle, echo level 4 and echo level 7.
  Each unified diff is empty, including table headers and whitespace.
- All 13 required test scripts pass, including Gallery layout, deterministic
  waves, two-echo adjustment, rotation/UI and mixed-Trial persistence checks.
  Headless parser/import and 600-frame smoke checks pass; no real save was
  created. Rendered readability and human roster-swapping verification were
  not performed under this task's no-editor/no-MCP constraint.

### Slice 7b

This redesign supersedes Slice 7's Gallery layout and tuning tables. The director
now reads encounter-local `enemy_overrides[enemy_id]` before adding an enemy to
the tree, using a fixed allow-list of exported float properties: `move_speed`,
`max_health`, `flee_distance`, `keep_distance`, `shot_damage`. It accepts finite
nonnegative ints/floats (strictly positive health), ignores unknown/invalid keys
without RNG draws, then applies large-party health scaling. Reset clears the
copied overrides. Enemy scene resources and the open arena are unchanged.

Final Gallery data:

- Seed 9203; level-5 trigger after choices; warning 3 s; grace 1 s. Jitter radius
  40 remains available, but all these entries are explicit `count: 1` spawns.
- t=0: Slingers at (360, -30), (540, 120), (-440, 280); Hexcallers at
  (-330, 260), (520, 0). Five opening enemies.
- t≥8: four Skitters at (300, 80), (410, 80), (300, 190), (410, 190).
- t≥18: Slingers at (-330, 150), (240, 280), (-540, 280); Hexcaller at
  (540, 270).
- Both later groups have `max_alive: 2`: a due wave waits until no more than two
  enemies survive, capping live enemies at six. An overdue wave cannot bypass
  the next group's occupancy check in the same tick.
- Slinger overrides: speed 400, flee 330, keep/approach 360, max HP 45, dart
  damage 35. Hexcaller overrides: speed 200, flee 260, keep/approach 380; all
  other stats and telegraph timings retain their defaults.
- At least two echoes: extra t=0 Slinger at (265, -302), all enemy maximum HP
  ×1.25 (Slinger/Skitter 56.25; Hexcaller 175). No damage/speed multiplier.
  Totals: 13/14 enemies, 580/630 kill XP for base/large parties.
- Every ranged spawn starts ≥320 px from centre, every distinct centre is ≥100
  px from all others including extra/later waves, and conservative body/break
  ring/cast-bar bounds plus 40 px clear all supplied HUD rectangles at 1280×720.
  Spawn centres are ≥248 px from the ±900/±550 arena walls. Cornering remains
  possible; no global wall or kiting rules changed.

Six distinct configurations were evaluated in all four modes, followed by an
identical rerun of the selected candidate; no seventh tuning configuration was
introduced:

| Candidate | Main changes | Reference result / rejection reason |
| --- | --- | --- |
| 1 | 3 Slingers + 1 Hexcaller opening; speed 360/240; default HP/damage; ×1.5 large health | both covered pair orders and covered triple clear, but both Mender orders clear comfortably and covered idle triple clears; extra Slinger also overlaps report margin |
| 2 | add second opening Hexcaller; Slinger speed 450, HP 135, damage 28; ×1.7 large health | every missing-range row fails, but both covered pair orders and covered triple fail; extra margin still invalid |
| 3 | Slinger speed 400, HP 75, damage 21; Hexcaller speed 200; ×1.25 large health; fix extra Slinger to y=-302 | Vanguard-led covered rows fail, Mender + Vanguard still clears at 42 HP without loss; later Slinger centre too close to opening Hexcaller |
| **4 (selected)** | HP 45, damage 35; move later Slinger to (-330, 150); valid full layout | all missing-range targets met; reverse covered order clears, Vanguard-led covered rows fail; covered idle triple still clears |
| 5 | damage 24; replace second opening Hexcaller with Slinger | covered triple clears, but Mender + Vanguard clears at 78 HP without loss; Vanguard + Arcanist fails and covered idle triple clears |
| 6 | damage 24; split opening Hexcallers left/right; local damage-break threshold 120 | covered triple clears, but both Mender orders and redundant triple clear comfortably; Vanguard + Arcanist fails; covered idle triple clears |

Candidate four prioritizes the explicitly primary missing-range target over
recovering the covered triple at the cost of comfortable missing-range clears.
The rejected break-threshold override was removed; the shipped Hexcaller break
threshold remains 60 everywhere. This is a partial tuning result, not full
acceptance of targets (a)–(d). The matrix policy, scenario scenes, weapons,
progression, Bell Court data and open-arena rules were not edited in this pass.

#### Default reference bot

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
```

```text
Slinger Gallery matrix (deterministic player bot, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   22.0s          120      75        0              0/3        60       0
arcanist_vanguard             hero      CLEARED   23.9s          120      0         1 @ 23.3s      1/3        0        0
mender_vanguard               hero      CLEARED   25.5s          80       0         1 @ 23.3s      1/1        150      0
vanguard_arcanist             hero      FAILED    12.6s          0        0         1 @ 5.8s       2/2        0        1
vanguard_mender               hero      FAILED    14.9s          0        0         1 @ 6.2s       2/2        30       1
vanguard_mender_arcanist      hero      FAILED    12.1s          15       72/120    0              3/1        30       1
vanguard_mender_vanguard      hero      FAILED    20.8s          0        0/120     1 @ 12.1s      3/1        90       4
vanguard_solo                 hero      FAILED    8.4s           0        -         -              1/2        0        3
vanguard_vanguard             hero      FAILED    12.5s          0        120       0              1/2        0        2
```

#### Idle player

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
```

```text
Slinger Gallery matrix (idle player, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               idle      FAILED    10.6s          0        0         1 @ 8.6s       2/1        60       6
arcanist_vanguard             idle      FAILED    5.8s           0        0         0              2/0        0        5
mender_vanguard               idle      FAILED    5.8s           0        0         0              2/0        0        5
vanguard_arcanist             idle      FAILED    5.8s           0        30        0              1/1        0        2
vanguard_mender               idle      FAILED    10.6s          0        0         1 @ 8.6s       2/1        60       6
vanguard_mender_arcanist      idle      CLEARED   22.7s          120      70/85     0              0/2        90       0
vanguard_mender_vanguard      idle      FAILED    22.7s          0        0/0       2 @ 10.6s      1/2        90       3
vanguard_solo                 idle      FAILED    5.8s           0        -         -              2/0        0        5
vanguard_vanguard             idle      FAILED    5.8s           0        0         0              2/0        0        5
```

#### Echo level 4

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=4
```

```text
Slinger Gallery matrix (deterministic player bot, echo level 4, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   22.0s          120      85        0              0/3        90       0
arcanist_vanguard             hero      CLEARED   23.9s          120      0         1 @ 23.3s      1/3        0        0
mender_vanguard               hero      FAILED    28.3s          0        0         1 @ 10.3s      1/2        90       1
vanguard_arcanist             hero      FAILED    12.6s          0        0         1 @ 5.8s       2/2        0        1
vanguard_mender               hero      FAILED    14.9s          0        0         1 @ 6.2s       2/2        30       1
vanguard_mender_arcanist      hero      FAILED    12.1s          15       52/100    0              3/1        30       1
vanguard_mender_vanguard      hero      FAILED    14.9s          0        0/100     1 @ 12.1s      3/1        60       1
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    12.5s          0        100       0              1/2        0        2
```

#### Echo level 7

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=7
```

```text
Slinger Gallery matrix (deterministic player bot, echo level 7, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   21.5s          120      95        0              0/3        60       0
arcanist_vanguard             hero      CLEARED   25.3s          120      7         0              1/3        0        0
mender_vanguard               hero      CLEARED   27.8s          80       0         1 @ 26.5s      1/1        150      0
vanguard_arcanist             hero      FAILED    12.7s          0        0         1 @ 8.1s       2/2        0        1
vanguard_mender               hero      FAILED    12.5s          0        40        0              2/2        60       1
vanguard_mender_arcanist      hero      FAILED    12.1s          15       92/140    0              3/1        30       1
vanguard_mender_vanguard      hero      FAILED    20.8s          0        0/140     1 @ 12.1s      3/1        90       4
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    19.8s          0        0         1 @ 16.1s      1/2        0        5
```

#### Bell Court comparison

Before any changes, the complete default, `--idle`, `--echo-level=4`, and
`--echo-level=7` outputs were captured. All four final Bell Court tables are
**byte-identical** to those baselines, including headers and whitespace; each
unified diff is empty. All four final Gallery tables also exactly reproduce the
selected fourth candidate. Logs and empty diffs are in `/tmp/echo-slice7b/`.

#### Observations and target assessment

- **(b) met:** Vanguard + Mender and Vanguard + Vanguard fail at echo levels
  4/5/7; solo fails. Mender + Vanguard fails at level 4, and clears at levels 5
  and 7 with 80 hero HP but its echo lost, meeting the requested thin-clear
  definition. The previous 106-HP redundant-Vanguard and 41-HP reverse-Mender
  no-loss clears are gone.
- **(a) partially met:** Arcanist + Vanguard clears at every tested echo level,
  but Vanguard + Arcanist fails at 12.6–12.7 s. Its echo falls at 5.8 s at
  level 4 and 8.1 s at levels 5/7, so the range check alone does not establish
  a viable covered party in both orders.
- **(c) partially met:** redundant Vanguard + Mender + Vanguard fails at all
  three levels; covered Vanguard + Mender + Arcanist also fails at 12.1 s at
  all three levels. Candidates five and six recover that covered clear but
  miss the primary missing-range target in the reference mode.
- **(d) partially met:** eight idle rows fail, but Vanguard + Mender + Arcanist
  clears at 22.7 s with 120 hero HP. Arcanist + Mender also remains comfortable
  in bot mode (120 hero HP, 0 casts landed / 3 broken by damage), so Hexcaller
  pressure and the contribution of active play remain unresolved tuning gaps.
- **(e) met:** every Bell Court table is unchanged. Structured instrumentation
  of the selected default run observes peaks of five or six Gallery enemies;
  Slingers accumulate only 0–1 enemy-seconds within Lance range per scenario,
  despite some wall contact. This verifies reduced melee access and occupancy,
  not rendered readability or human gameplay feel.

#### Validation

All 13 required scripts pass, including the 22 encounter cases covering local
numeric overrides, invalid/unknown keys (including forbidden exported numeric
properties), pre-ready health, reset isolation, later-wave scaling, deterministic
stats/positions/seeds, HUD bounds, spacing, range distance and occupancy gates.
Headless editor import, all four fixed-60-Hz matrices, the 600-frame smoke run,
and `git diff --check` pass with no `SCRIPT ERROR`, `Parse Error`, or `ERROR:`
lines in final command logs. No real save was created. No graphical editor,
Godot MCP, subagents, commits or pushes were used; visual and interactive
verification remains pending under the task constraints. README contains no
Gallery-specific wave/stat numbers, so it needed no change in this pass.

### Slice 7c (coordinator retune, supersedes the Slice 7b values)

Slice 7b's overrides (Slinger 400 px/s and 35 dart damage, Hexcaller 200 px/s)
made covered Vanguard-led parties fail: the melee hero bot chased untouchable
kiters, and the darts killed the Arcanist echo by about 6 s. The coordinator
swept five override sets with the waves and the large-party values unchanged:
240/20, 300/28, 270/32, 300/25 and 290/26 (Slinger speed and dart damage,
with Hexcaller speed between 140 and 160). The shipped overrides are:

- Slinger: `move_speed` 300, `flee_distance` 300, `keep_distance` 360,
  `max_health` 45, `shot_damage` 25.
- Hexcaller: `move_speed` 160, `flee_distance` 250, `keep_distance` 400.

The Bell Court default table is byte-identical to the Slice 6b amendment.
Final Gallery tables:

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
```

```text
Slinger Gallery matrix (deterministic player bot, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   21.4s          120      120       0              0/3        0        0
arcanist_vanguard             hero      CLEARED   24.0s          120      95        0              1/2        0        0
mender_vanguard               hero      CLEARED   25.6s          95       95        0              1/1        130      0
vanguard_arcanist             hero      CLEARED   25.3s          29       0         1 @ 21.8s      2/2        0        0
vanguard_mender               hero      CLEARED   23.0s          70       100       0              2/3        110      0
vanguard_mender_arcanist      hero      CLEARED   29.3s          120      75/120    0              4/3        160      0
vanguard_mender_vanguard      hero      FAILED    12.6s          0        0/40      1 @ 12.1s      3/1        60       2
vanguard_solo                 hero      FAILED    12.9s          0        -         -              1/2        0        2
vanguard_vanguard             hero      FAILED    23.3s          0        62        0              2/2        0        2
```

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
```

```text
Slinger Gallery matrix (idle player, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               idle      CLEARED   24.0s          69       20        0              4/0        210      0
arcanist_vanguard             idle      FAILED    6.4s           0        95        0              2/0        0        5
mender_vanguard               idle      FAILED    6.4s           0        95        0              2/0        0        5
vanguard_arcanist             idle      FAILED    8.0s           15       65        0              2/1        0        5
vanguard_mender               idle      CLEARED   24.0s          69       20        0              4/0        210      0
vanguard_mender_arcanist      idle      CLEARED   22.3s          100      100/120   0              1/1        170      0
vanguard_mender_vanguard      idle      CLEARED   24.5s          72       50/0      1 @ 12.8s      2/2        180      0
vanguard_solo                 idle      FAILED    8.0s           15       -         -              4/0        0        5
vanguard_vanguard             idle      FAILED    6.4s           0        95        0              2/0        0        5
```

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=4
```

```text
Slinger Gallery matrix (deterministic player bot, echo level 4, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   21.4s          120      100       0              0/3        0        0
arcanist_vanguard             hero      CLEARED   24.0s          120      75        0              1/2        0        0
mender_vanguard               hero      CLEARED   25.6s          95       75        0              1/1        130      0
vanguard_arcanist             hero      CLEARED   25.3s          29       0         1 @ 21.4s      2/2        0        0
vanguard_mender               hero      CLEARED   23.0s          70       80        0              2/3        110      0
vanguard_mender_arcanist      hero      CLEARED   29.3s          120      55/100    0              4/3        160      0
vanguard_mender_vanguard      hero      FAILED    17.3s          0        0/75      1 @ 10.6s      3/2        30       0
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    23.3s          0        42        0              2/2        0        2
```

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --echo-level=7
```

```text
Slinger Gallery matrix (deterministic player bot, echo level 7, <= 60 s of fight per scenario)
scenario                      bot side  outcome   time           hero HP  echo HP   echoes lost    casts L/B  healing  left
arcanist_mender               hero      CLEARED   21.1s          120      140       0              0/3        0        0
arcanist_vanguard             hero      CLEARED   24.0s          120      115       0              1/2        0        0
mender_vanguard               hero      CLEARED   25.6s          95       75        0              1/1        90       0
vanguard_arcanist             hero      CLEARED   21.8s          70       35        0              2/2        0        0
vanguard_mender               hero      CLEARED   21.8s          95       70        0              2/3        110      0
vanguard_mender_arcanist      hero      CLEARED   29.3s          95       65/140    0              4/3        130      0
vanguard_mender_vanguard      hero      FAILED    23.2s          0        40/115    0              4/2        120      2
vanguard_solo                 hero      SKIPPED   no echoes      -        -         -              -          -        -
vanguard_vanguard             hero      FAILED    23.3s          0        82        0              2/2        0        2
```

Observations:

- Every pure-melee party (solo Vanguard, Vanguard + Vanguard, and Vanguard +
  Mender + Vanguard) fails at echo levels 4, 5 and 7.
- Every party with an Arcanist clears at every echo level. Vanguard +
  Arcanist is the thinnest: 29 hero HP with the echo lost.
- Parties with a Mender also clear, because the Sling is a 340 px projectile.
  Mender's capability tags do not include `range`, so the Trial panel calls
  Vanguard + Mender uncovered while the bot clears. Playtests should decide
  whether to tag the Sling as a range answer or to weaken it against kiters.
- In idle mode, a Mender echo or two echoes can carry a hero who stands still.
  The Bell Court has no such case.
