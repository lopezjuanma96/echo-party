# M2 Party Dependency Plan (remaining items)

Working implementation plan for the M2 items still open after party commands
landed. Sonnet 5.5 drafted it (design role) and the coordinator amended it. When
a slice lands, its decisions move into `docs/game-design.md`,
`docs/architecture.md`, `README.md`, and `docs/roadmap.md`. This file is not
the source of truth for shipped rules.

## Coordinator Amendments (override the spec below)

1. **Scenario hook is scene-based and lands in Slice 1, not Slice 5.**
   - The Godot MCP's `run` action accepts `scene_path` and `frozen` but cannot
     pass command-line arguments.
   - Add `tests/scenarios/scenario_launcher.gd`: a root `Node` with
     `@export var player_job: StringName`, `@export var echo_job: StringName`
     (empty means no echo), `@export var level: int`, and
     `@export var encounter_id: StringName` (empty means none; used from
     Slice 5).
   - In `_ready()` it instances `res://src/main/main.tscn` as a child and calls
     a public `Main.apply_scenario(player_job, echo_job, level, encounter_id)`.
     That call builds deterministic progressions (attributes alternate
     `might`/`vitality`), records the echo, and spawns it.
   - Add scenario scenes as each slice needs them, named
     `tests/scenarios/<player>_<echo>_<level>[_<encounter>].tscn`, e.g.
     `tests/scenarios/mender_vanguard_5.tscn`.
   - The launcher also exports `player_health_fraction`,
     `echo_health_fraction`, and `enemy_population` (-1 keeps the default, 0
     isolates). It registers the scenario-only `playtest_capture` action (F12),
     which saves the rendered frame as a PNG under
     `user://playtest_captures/`.
   - Wherever the spec below says `-- --scenario=a:b:n[:court]`, use the
     matching scenario scene instead.
2. **Structured MCP state.**
   - Slice 1 adds `func _mcp_state() -> Dictionary` to the player, the echo,
     and the drifter enemy. Every later enemy and the encounter director add
     one too.
   - Include live values: position, health, max_health, job_id, weapon id and
     cooldown, ability_id and cooldown, current/display intent, command
     status, and enemy_id/state/cast progress.
   - Include the identifying config the playtester needs. Keep it cheap, with
     no allocation-heavy work.
   - Return only plain `String`, number, bool, array, or dictionary values.
     The MCP drops `StringName`, `Vector2`, and `Object` values, so write
     `String(enemy_id)`, `pos_x`/`pos_y`, and `String(node.name)`.
     `Main._mcp_state()` covers run-level HUD state.
3. **Decisions G1–G7 go ahead with the defaults below** unless the user
   overrides them. Each slice updates the docs for the decisions it lands.
4. **Single echo only.** Do not add multi-echo plumbing in M2. Where new echo
   state is introduced, keep it on the echo instance and do not make it a
   global (see `docs/exploration/multi-echo-commands.md`, "What M2 Work
   Should Avoid").
5. **Determinism.** Every new random choice uses an injected or seeded
   `RandomNumberGenerator`. Do not use `randf()` or `randi()` globals.

---

## Facts verified in the code

- No ability, mana, or skill system exists; jobs differ only by weapon loadout.
- Enemies are random-walk contact damagers that never target anyone.
- `HeroActor.take_damage` has 0.35 s i-frames, so incoming damage caps at about
  `hit / 0.35 s` per actor regardless of enemy count.
- `friendly_actors` is only on the Echo scene. The Player is not in it.
- Bolts have collision mask 5 (walls and enemies) and never hit friendlies.
- Existing tests build `PlayerScript.new()` outside the tree. New `HeroActor`
  fields must not require the tree except inside `use_ability()`.

## A. Rationale

The exit condition needs a tester to see a future need, recognise the gap in
the current party, and pick a job to fill it.

- **Enemies:** four variants make jobs matter. For example, Hexcaller needs an
  interrupt and Brutes need sustain.
- **Third job, Mender:** fills the missing sustain capability and introduces
  the first ability and cooldown.
- **Encounter, Bell Court:** a level-5 trial needing Interrupt, Area, and
  Sustain. Only Vanguard + Mender covers all three. The need is shown from
  run start, and the job modal marks the option that fills the gap.
- **Feedback:** cooldown bars, echo intent glyphs, and target lines make it
  clear why the party failed or won. The trial report names the missing role.

## B. Third Job: Mender (`mender`)

Support role: backline sustain with weak offense. `HeroProgression.JOB_IDS`
becomes `[vanguard, arcanist, mender]`, and the modal option index maps to
`JOB_IDS[i]`. The change is additive, so existing records remain valid.

### Weapons

Weapons use the existing `WeaponDefinition` .tres pattern and are registered in
`WeaponCatalog.WEAPONS`. Loadout: `LOADOUTS[&"mender"] = [&"mace", &"sling"]`.

| id | kind | cooldown | range | arc / speed | notes |
|---|---|---|---|---|---|
| `mace` | MELEE | 0.50 | 70 | 100° | `damage_multiplier = 0.8` |
| `sling` | PROJECTILE | 0.50 | 340 | speed 600, color `Color(0.95,0.78,0.30)` | `damage_multiplier = 0.8` |

At base, Mender deals 20 per hit against 25 for the other jobs.

### New `WeaponDefinition` fields

The defaults are inert, so existing .tres files only change where noted:

- `damage_multiplier := 1.0`
- `interrupts := false`, set to `true` on `lance.tres`
- `splash_radius := 0.0`, set to `80` on `staff.tres`
- `splash_fraction := 0.6`

Apply `damage_multiplier` in `_swing_melee` and `_fire_projectile`. The bolt
receives `interrupts`, `splash_radius`, and `splash_fraction` through new
optional `launch()` parameters. When a bolt hits an enemy, the other `enemies`
within the radius take `damage * fraction`. Wall hits do not splash.

### Ability "Mend" (`mend`)

- Defined as an `AbilityDefinition` .tres in `src/combat/abilities/` and
  registered in a static `AbilityCatalog`, like `WeaponCatalog`.
- Fields: `id`, `display_name`, `cooldown = 6.0`, `radius = 240`,
  `heal_amount = 60`, `self_heal_fraction = 0.5`, `color`.
- Immediate mode: no click needed.
- Heals the friendly actor with the lowest `health/max_health` within the
  radius, caster included.
- Heals others for 60 and self for 30, so a solo Mender is weak and wants a
  party.
- If nobody is wounded, Mend does nothing, spends no cooldown, and the HUD
  shows "No one needs healing".
- Ties go to the active hero, then by node name.
- Cooldown is 6.0 s after use. Mend is the minimal mechanic that gives the
  cooldown feedback something to show.

### Job registry

Add a static `src/domain/job_catalog.gd`, like `WeaponCatalog`, with per-job
fields:

- `display_name`
- `ability_id`: `mend` for Mender, empty for the others
- `posture`: `frontline` (melee), `ranged`, or `support`
- `provides` tags: Vanguard `[interrupt, area]`, Arcanist `[area, range]`,
  Mender `[sustain]`, Novice `[]`

The catalog replaces the duplicated `_job_display_name` match in `main.gd` and
the `JOB_ARCANIST` check in `echo.gd`. The `provides` tags are display only:
they mean "this job's kit reliably answers this", and mechanics never gate on
them.

### `HeroActor` additions

Shared by the player and the echo:

- Fields: `ability_id`, `ability_cooldown_left`, `total_healing_done`.
- Methods: `can_use_ability()`, `use_ability()`, `heal(amount)`.
- `tick_combat` decrements the ability cooldown.
- `apply_job_loadout` sets `ability_id` and resets the cooldown.
- `reset_actor` clears the cooldown.
- `Player.reset_for_new_run` resets the loadout manually without calling
  `apply_job_loadout`, so it must also clear `ability_id` and the cooldown.

Related changes:

- FX: a procedural expanding green ring, like `SlashEffect`, in the
  `transient_combat` group.
- Add `groups=["friendly_actors"]` to the Player node in `main.tscn`.
- Player input: a new action `ability_1`, defaulting to `E`, added to
  `DEFAULT_KEY_BINDINGS` and to `_is_combat_input_pressed()` so that
  `suppress_combat_input` covers it.
- Modal: a third button `ChoiceThree` with shortcut `3` and a `pressed`
  connection, shown only at the advancement level.

### Echo AI for Mender

Checked in priority order every physics tick:

1. **Mend.** When the ability is ready, choose the friendly (active hero or
   self) within 240 with the lowest health fraction. Cast if that fraction is
   `<= 0.6` (`@export mend_threshold`). Intent becomes `&"heal"` and the intent
   target is that ally. This works during hold and regroup too.
2. **Retreat.** When an enemy is within 140, move toward the active hero if
   more than 70 from it, otherwise away from the enemy.
3. **Attack.** `choose_weapon_for_distance` picks the mace within 70,
   otherwise the sling.
4. **Approach.** Approach only while within 260 of the active hero
   (`support_leash`). Otherwise hold near the hero.

The existing `JOB_ARCANIST` retreat check becomes `posture == &"ranged"` (180),
with unchanged behaviour.

## C. Enemy Variants

### Shared changes to `enemy.gd`

- `class_name EnemyActor`, `@export enemy_id := &"drifter"`, and
  `@export enemy_name`.
- `take_damage(amount: float, interrupts: bool = false)`. Single-argument
  callers still work.
- A virtual `_on_damaged(amount, interrupts)` and `is_casting() -> bool`
  (default false).
- `@export spawn_grace := 0.0`. While above 0, the enemy takes no damage, does
  nothing, and its body pulses.
- `signal dealt_damage(enemy_id, target, applied)`, with `applied` computed
  from health before and after. Used for trial reporting.

### Variant implementation

- Variants `extends EnemyActor`, override `_physics_process` without calling
  super, and reuse `_damage_contact` where relevant.
- A static `EnemyTargeting` helper provides `nearest_friendly(from)` and
  `weakest_friendly(from, max_dist)`. Both read the `friendly_actors` group,
  skip actors where `is_defeated`, and break ties with
  `name.naturalnocasecmp_to`.
- Telegraphs are drawn by a `Telegraph` Node2D that calls `queue_redraw()`
  while active. Make it the enemy's first child at z_index 0. A negative
  z_index hides it under the arena floor, which was a Slice 2 bug. A
  world-locked circle such as the Hexcaller's needs `top_level = true` or a
  separate node, so it does not follow the enemy.

`drifter` (existing): 50 hp, speed 90, 10 contact damage every 0.5 s, 50 XP,
red square. Its behaviour does not change.

| id | tests | hp / speed / XP | look |
|---|---|---|---|
| `skitter` | area | 30 / 150 / 10 | 22 px orange triangle `#f2a33a`, 0.8 s spawn grace with alpha pulse |
| `brute` | protection | 160 / 70 / 70 | 58 px octagon `#7a1f2b` |
| `hexcaller` | interruption, range | 70 / 85 / 80 | 24 px hexagon `#c2409a` |
| `slinger` | range, protection | 45 / 100 / 50 | 26 px teal diamond `#2fbf9b` |

### Skitter

- Chases the nearest friendly and deals 8 contact damage every 0.6 s.
- Spawns in packs of 4 inside a 40 px cluster.

### Brute

- Chases the nearest friendly. Within 70 it enters a 0.9 s **windup**, then
  slams for 35 damage to every friendly within radius 88 of itself.
- Then a 0.7 s stationary **recover**, then a 0.8 s cooldown in which it may
  move. The full cycle takes about 2.4 s.
- No contact damage. Not interruptible.
- Telegraph: a red ground circle that fills from alpha 0.15 to 0.55, with a
  white outline in the last 0.1 s. The body desaturates during recovery.
- A moving player escapes easily (0.9 s at speed 260). An echo standing in
  melee takes the slam, which is the protection need.

### Hexcaller

- Keeps about 340 from the nearest friendly: flees below 240 and approaches
  above 440.
- Casting takes 2.0 s. At cast start it targets the nearest friendly and locks
  a radius-110 circle on that position. On resolve, every friendly inside
  takes 45.
- Cast cooldown is 3.5 s. The first cast comes 1.0 s after spawn grace ends.
- Interrupt rule: a hit with `interrupts = true` (the lance) breaks the cast,
  as does 60 or more cumulative damage during it (three 25-damage hits or
  three Mender hits of 20). On break, the cast cancels, the Hexcaller is
  stunned for 1.5 s, and a floating "INTERRUPTED" shows for 0.8 s.
- Telegraph: a magenta circle that fills with progress, a thin white radius-34
  "break ring" around the body that marks it interruptible, and a 44×4 cast
  bar above it.
- It outranges melee: Vanguard must close about 210 px. The wand (430) reaches
  it, and the sling (340) barely does.

### Slinger

- Keeps about 380 from the nearest friendly and flees below 260.
- Every 2.4 s it fires at the friendly with the lowest health fraction within
  600, breaking ties by distance.
- Windup lasts 0.6 s. A thin red aim line tracks the target for the first
  0.45 s and freezes for the last 0.15 s.
- The dart is a new `EnemyShot` Area2D script, not a reused `Bolt`. Speed 420,
  14 damage, 640 max distance. Its mask is walls plus friendly layer 2, and it
  calls `take_damage` on the first friendly it hits.

### Readability rules

- Red or orange means an incoming damage zone.
- A white ring means interruptible.
- Green or cyan means a friendly effect.
- Every telegraph lasts at least 0.6 s.
- Each enemy differs in both shape and colour.

### Open-arena mix

- The spawner uses a separate type RNG (`seed ^ 0x5eed`), so the position
  stream and the existing spawner tests stay unchanged.
- A static `EnemyCatalog` maps each id to a scene.
- The spawner gains `threat_level`, which `Main` sets from the active hero's
  level.
- Unlocks by level:
  - Level 1–2: drifters only.
  - Level 3: skitter and slinger (drifter 55 / skitter 25 / slinger 20).
  - Level 4: brute and hexcaller (drifter 40 / skitter 20 / slinger 15 /
    brute 15 / hexcaller 10).
- `set_population(n)` also trims pending respawns. The director uses it to
  pause and resume spawning.

## D. Encounter: The Bell Court (`bell_court`)

Needs `[interrupt, area, sustain]`. The director moves through
`IDLE → WARNING → ACTIVE → CLEARED`.

### Trigger and phases

- **Armed** once per run. It fires when the active hero's level is at least 5,
  no level choice is pending (the modal pauses the tree anyway), and the
  director is `IDLE`.
- **WARNING, 3.0 s.**
  - A centre banner reads "THE BELL COURT — Needs: Interrupt · Area ·
    Sustain".
  - `set_population(0)` runs. Remaining drifters fade and are `queue_free`d
    silently, with no XP.
- **ACTIVE.** Every encounter enemy spawns with `spawn_grace = 1.0`.
  - At t=0: Brutes at (-340,-220) and (340,-220), and a Hexcaller at
    (0,-420).
  - At t=12 s: skitter pack A (4) at (-780,40).
  - At t=24 s: skitter pack B (4) at (780,40).
  - Pack jitter and enemy seeds come from the director's RNG (seed 7117).
- **CLEARED** when every wave has spawned and no enemies remain alive.
  - `set_population(7)` resumes the normal loop.
  - The only reward is kill XP: about 300 in total (140 for the Brutes, 80 for
    the Hexcaller, 80 for the skitters).
- **Active hero dies:** `director.reset_for_new_run()` frees the director's
  enemies, resumes spawning, and re-arms. The run-start HUD shows the failure
  report.

### Placement

- The director is a sibling of `Enemies` and parents its own enemies, so the
  spawner's child-count population is unaffected.
- Its `enemy_defeated(xp)` signal connects to the same
  `Main._on_enemy_defeated`.
- `stable_spawn_order = 1_000_000 + n`.

### Why Vanguard + Mender is rewarded

| pair | covers | what goes wrong |
|---|---|---|
| Vanguard + Mender | interrupt, area, sustain | nothing: clears with margin (target) |
| Vanguard + Arcanist | interrupt, area | no sustain: the frontline dies to slams and darts |
| Arcanist + Mender | area, sustain | no reliable interrupt: circles land, partly offset by heals |
| Vanguard + Vanguard | interrupt, area | no sustain |
| Novice or solo | none | dies |

The Vanguard echo AI prioritises casters and uses the lance, so it interrupts
automatically. The Arcanist echo AI does not interrupt. A player-controlled
Arcanist still can with the wand, so the pair is strongly but not absolutely
rewarded.

### How a tester notices

1. **Trial panel.** A `HUD/Trial` panel at top centre is visible from run
   start: "TRIAL · Bell Court · Lv 5", with INTERRUPT / AREA / SUSTAIN chips.
   Each chip shows ✓ plus the covering job, or ✗. Coverage combines the echo's
   job with the active hero's job once chosen.
2. **Job modal.** At level 3, each option is annotated. For example, the
   Mender button reads "Fills Trial need: SUSTAIN ★". Every option that covers
   an uncovered need gets the ★.
3. **Trial report.** Shown for 10 s after a clear, or at the next run start
   after a failure. It lists:
   - casts landed and casts broken;
   - damage taken per enemy id, split between hero and echo;
   - healing done;
   - whether the echo survived;
   - "Missing: SUSTAIN → Mender provides SUSTAIN".

The director keeps the counters. Damage comes from the enemies'
`dealt_damage` signal, and healing from `total_healing_done`.

## E. Echo Intent and Cooldown Feedback

### Echo overlay

Add `src/echo/echo_status_overlay.gd`, a Node2D child of the echo, and shift
`EchoLabel` up 16 px. Below the label it draws:

- a 48×6 health bar;
- a thin, 3 px weapon-cooldown bar;
- an ability pip on the right that fills as Mend recharges and is solid when
  ready;
- an intent glyph beside the bars.

| intent | glyph | colour |
|---|---|---|
| attack | crossed lines | red `#e5484d` |
| approach | chevron toward the target | cyan |
| retreat | chevron away from the target | orange |
| hold | two bars | grey |
| follow | three dots | blue |
| regroup | ring with dot | blue |
| heal | plus | green `#5bd98a` |
| interrupt | zigzag | yellow `#ffd23f` |
| idle | none | — |

A 2 px line in the intent colour connects the echo to its intent target (the
ally, for heal). Manual focus keeps its purple ring.

### Echo logic

- New intents `heal` and `interrupt`. `interrupt` applies when the target
  `is_casting()` and the echo is approaching or attacking it with an
  interrupting weapon.
- Add `intent_target` and `get_intent_summary()`, e.g. "Interrupt → Hexcaller
  · 212 px" or "Mend → Hero 2 · 38%".
- Add `get_display_intent()` with a 0.25 s minimum dwell. It shows an in-fight
  `hold` caused by weapon cooldown as `attack`, so it is not confused with the
  hold stance. Keep the raw `current_intent` values, because tests assert
  them.
- Vanguard `choose_target` prefers a casting enemy within 450. Manual focus
  still wins.
- Vanguard weapon choice prefers the lance when the target is casting and
  within 132.

### HUD

- **RunStatus echo rows.**
  - Intent shows `Intent: <summary>`.
  - A new `Cooldowns: Sword 0.2s · Lance Ready · Mend 3.4s` row.
  - The panel grows to fit.
- **Weapon panel.** Grows to about 130 px and gains:
  - a cooldown bar for the selected weapon;
  - a `[E] Mend — Ready / 3.4 s` row, hidden for jobs with no ability;
  - a `[Space] Dodge — Ready` pip.
- **Left column.**
  - Shift Progression down: RunStatus 233→~383, Progression ~395→~493.
  - Add `E | Ability` to the Instructions.
  - `_test_hud_panels_do_not_overlap` must still pass, with 12 px gaps and a
    bottom edge at most 720. Update its numbers.

## F. Implementation Slices

Each slice updates docs for what it changes: `docs/game-design.md` (jobs,
enemies, controls, Bell Court), `README.md` (controls, status),
`docs/architecture.md` (ability, enemy, and encounter boundaries), and
`docs/roadmap.md` (tick M2 items).

### Slice 1 — Mender and Mend (plus scenario hook and `_mcp_state`)

**Goal:** a playable third job with an ability and a cooldown.

**Add:**

- `src/domain/job_catalog.gd`
- `src/combat/ability_definition.gd`
- `src/combat/ability_catalog.gd`
- `src/combat/abilities/mend.tres`
- `src/combat/weapons/mace.tres`
- `src/combat/weapons/sling.tres`
- `src/combat/heal_pulse_effect.gd`
- `tests/scenarios/scenario_launcher.gd`
- `tests/scenarios/mender_vanguard_5.tscn`
- `tests/scenarios/vanguard_mender_5.tscn`

**Edit:**

- `hero_progression.gd`
- `weapon_catalog.gd`
- `weapon_definition.gd` (`damage_multiplier` only, for now)
- `hero_actor.gd`
- `player.gd`
- `echo.gd`
- `enemy.gd` (`_mcp_state` only)
- `main.gd` (including `apply_scenario`)
- `main.tscn`

**Acceptance:**

- The level-3 choice offers three jobs through keys `1` / `2` / `3` and the
  buttons.
- The Mender loadout is `[mace, sling]`.
- `E` heals the most-wounded friendly within 240 for 60 (30 for self). With no
  one wounded it does nothing and spends no cooldown. The cooldown is 6 s.
- Existing records and tests still pass.
- The echo Mender casts Mend at a health fraction of 0.6 or less.
- The scenario scenes start in the described state.

**Headless tests** in `tests/test_mender.gd`:

- `JOB_IDS` order, and a Mender progression JSON round-trip.
- `get_loadout(mender)`.
- Heal target selection: the lower fraction wins, ties break correctly, and
  the self-heal is 50%.
- No cooldown is spent when no one is wounded.
- The cooldown ticks down and resets.
- `damage_multiplier` makes a 25-damage Mender deal 20.
- An echo Mender casts Mend with intent `heal` when the hero is at 0.5, and
  does not when the hero is at 0.8.
- Extend `test_hero_progression` and `test_echo` with the new job.
- Test `apply_scenario` outside the scenario scene.

**Playtest:**

- Run `tests/scenarios/mender_vanguard_5.tscn`.
- Attack a drifter, let the echo or player get hurt, then press `E`.
- Read `_mcp_state` for the player and echo: `ability_cooldown_left` and
  `health`.
- Questions: does `E` feel responsive? Is the 6 s cooldown readable? Does the
  modal's third button fit?

### Slice 2 — Enemy foundation, Skitter, Brute, staff splash, lance flag

**Goal:** chasing enemies that test area damage and protection, plus the
open-arena mix.

**Add:**

- `src/enemy/enemy_targeting.gd`
- `src/enemy/enemy_catalog.gd`
- `src/enemy/skitter.{gd,tscn}`
- `src/enemy/brute.{gd,tscn}`
- `src/enemy/telegraph.gd`

**Edit:**

- `enemy.gd` (per section C)
- `enemy_spawner.gd` (type table, `threat_level`, `set_population`)
- `weapon_definition.gd`
- `lance.tres` and `staff.tres`
- `bolt.gd`
- `hero_actor.gd`
- `main.gd` (sets the threat level)

**Acceptance:**

- Skitter and Brute chase the nearest friendly, with the telegraph timings in
  section C.
- Staff splash hits neighbours for 60%.
- The existing spawner tests pass unchanged.
- Only drifters spawn at levels 1–2.
- Seeded spawn-type sequences are reproducible.

**Headless tests:**

- Brute windup lasts 0.9 s (±1 physics frame), and the slam deals 35 within
  radius 88.
- The slam deals 0 to a hero outside the radius and 0 to a dodge-rolling hero.
- Skitter chase target selection and tie-break.
- Staff splash on a cluster: 25 to the target, 15 to neighbours.
- The spawner type sequence for a fixed seed and threat level, with the
  position sequence unchanged.
- `take_damage(x)` still works with one argument.

**Playtest:**

- Run `tests/scenarios/arcanist_vanguard_4.tscn`.
- Read enemy states and health.
- Questions:
  - Does the Brute telegraph read in time?
  - Does the Vanguard echo take slams?
  - Are skitter packs dangerous within the i-frame cap?
  - Is the staff splash visible?

### Slice 3 — Hexcaller, Slinger, echo interrupt behaviour

**Goal:** interruption and range checks, and the Vanguard echo AI that answers
them.

**Add:**

- `src/enemy/hexcaller.{gd,tscn}`
- `src/enemy/slinger.{gd,tscn}`
- `src/enemy/enemy_shot.{gd,tscn}`

**Edit:**

- `echo.gd` (Vanguard casting priority, lance preference, `interrupt` intent)
- `enemy_catalog.gd`
- `enemy_spawner.gd` (unlock table)

**Acceptance:**

- The Hexcaller casts, locks its circle, and resolves for 45 at 2.0 s.
- A lance hit cancels the cast, as does 60 cumulative damage. The stun lasts
  1.5 s.
- The Slinger targets the friendly with the lowest health fraction, shows its
  windup aim line, and fires a dodgeable 14-damage dart.
- The Vanguard echo selects casting enemies within 450 and switches to the
  lance.

**Headless tests:**

- Interrupts: one lance hit breaks the cast, three wand hits break it, two do
  not.
- The circle stays put when the target moves.
- The circle damages only friendlies inside it.
- Slinger target choice between health fractions 0.4 and 1.0.
- The Vanguard echo prefers a caster over a nearer drifter, but manual focus
  still wins.

**Playtest:**

- Use a vanguard/vanguard level-4 scenario with a spawned Hexcaller; add an
  exported debug spawn list to the launcher if needed.
- Read `echo.current_intent`, the Hexcaller's `is_casting()`, and its cast
  progress.
- Questions:
  - Does the break ring say "interrupt me"?
  - Is 2.0 s long enough for the echo to reach the Hexcaller?
  - Can a player Arcanist interrupt at range with the wand?
  - Is the dart dodgeable?

### Slice 4 — Echo intent and cooldown feedback

**Goal:** roadmap item 4.

**Add:** `src/echo/echo_status_overlay.gd`.

**Edit:**

- `echo.gd`
- `echo.tscn`
- `main.gd`
- `main.tscn`
- `tests/test_echo.gd` (layout numbers)

**Acceptance:** everything in section E works, the HUD layout test passes, and
the HUD fits 1280×720.

**Headless tests:**

- `get_intent_summary()` strings for attack, interrupt, and heal.
- The 0.25 s dwell and the cooldown-to-attack mapping.
- Cooldown fractions: 0 when ready, 1 right after use.
- HUD panel rects do not overlap.

**Playtest:**

- Screenshot the overlay in the attack, heal, hold, and regroup states, and
  the Weapon panel with a cooling weapon, Mend, and dodge.
- Questions:
  - Is each glyph distinct at normal zoom?
  - Does the target line clutter fights?
  - Does the pip show when Mend returns?
  - Do labels flicker?

### Slice 5 — Bell Court, Trial panel, modal annotations, report

**Goal:** roadmap item 3 and the notice loop.

**Add:**

- `src/encounter/encounter_director.gd`
- `src/encounter/encounter_catalog.gd` (needs, timeline, positions)
- `src/domain/party_needs.gd` (pure coverage logic)
- `HUD/Trial` and `HUD/TrialReport` nodes
- `_court` scenario scenes for the pairs in section D

**Edit:** `main.gd`, `main.tscn`, `enemy_spawner.gd`, and the scenario
launcher (`encounter_id` support).

**Acceptance:**

- The state machine behaves as in section D.
- Coverage matches the table in section D.
- The modal ★ marks are correct.
- The report matches the events.
- Death mid-Court resets the director.
- Run 1 works without an echo.

**Headless tests:**

- `party_needs.covered()` for every pair.
- Trigger conditions: level 4 versus 5, a pending choice, once per run.
- The wave timeline at t=0, 12, and 24, by stepping `_physics_process`.
- The spawner pauses during the encounter and resumes after.
- Enemies get the right `stable_spawn_order`.
- Counter attribution for casts, damage per enemy id, and healing.
- `reset_for_new_run()` frees the director's enemies.

**Playtest:**

- Run the `_court` scenario for each pair in section D and record win or loss,
  time, and remaining HP.
- Read the director state, enemy counts, and player and echo health.
- Targets: Vanguard + Mender usually clears. Vanguard + Vanguard, Vanguard +
  Arcanist, and solo usually fail. If Vanguard + Arcanist wins easily, raise
  the Brute slam to 40 or cut the Mend cooldown to 5 s.

### Slice 6 — Docs and tuning pass

Record the decisions, tune from playtest evidence, and keep a short tuning log.
Then run the full headless suite, `godot --headless --path . --quit-after 600`,
and `git diff --check`. The final playtest repeats the pair matrix and checks
the exit condition: do testers deliberately choose a job for the next run's
need?

## G. Decisions Taken With Defaults (user may override)

1. **New control `E` (`ability_1`).** Accepted and remappable, like the other
   actions.
2. **Weapon rule changes.** The lance `interrupts`, the staff gets splash, and
   `damage_multiplier` is added. The design doc is updated to match.
3. **Open arena.** Enemies may chase, and the mix scales with level. Drifters
   remain wanderers and are the only type at levels 1–2.
4. **Trial needs are shown from run start.** The exit condition requires
   players to know the need.
5. **The trial also triggers in run 1, with no echo.**
6. **The echo does not dodge telegraphs** in M2; this is the protection need.
7. **Self-heal is 50% and the Mender damage multiplier is 0.8.** These are the
   first knobs to turn if Mender proves too strong solo.

## Tuning Notes From Playtests (for Slice 6)

- **Skitters are one-shot.** At level 4 with the scenario's Might picks,
  heroes hit for 35 and Mender for 28, against 30 Skitter HP. The echo cleared
  most of a pack before the first capture, so packs do not test area damage
  yet. Consider about 45 HP, so one hit plus a staff splash kills one.
- **Brute final outline.** The white outline in the last 0.1 s of windup is
  nearly invisible on the light floor. It also conflicts with "white means
  interruptible". Use a darker or saturated end flash.
- **Heal feedback.** The Mend pulse shows only at the caster. Add a target
  flash or number in Slice 4.
- **Instructions panel.** It does not list `E` yet; Slice 4 adds it.
- **Casters die too fast.** The level-4 Vanguard echo kills a 70 HP Hexcaller
  with two 35-damage lance hits, about 1.3 s after spawn and before its first
  cast resolves. The interrupt check never happens naturally. A 45 HP Slinger
  is similarly fragile. Tune HP against level-4/5 damage (35–40) in Slice 6,
  or let the Bell Court's grace and positioning carry the check.
- **Slinger aim line.** It extends to the full 600 px range and passes through
  other friendlies, so the target can be ambiguous. End the line at the target,
  or mark the target.

## M2 Tuning Log

### Deterministic harness

`tests/court_matrix.gd` loads each real `*_5_court.tscn` scenario and now drives
the player with a harness-only bot by default. Each physics tick it uses Mend
when a friendly within its radius is at 60% health or less; otherwise it reuses
the echo's caster priority, nearest-target tie-breaks, and weapon choice. It
aims, attacks off cooldown, and moves to about 90% of weapon range using the
job's frontline, ranged, or support posture. It does not dodge and does not
simulate input events or change live player controls. `--idle` preserves the
old idle-player comparison, and the `bot side` column distinguishes the modes.

### Settled changes

| Change | Before | After | Reason |
| --- | --- | --- | --- |
| Brute HP | 160 → 240 in the partial pass | **600** | Repeated slam cycles make sustain matter instead of letting every pair burst the Brutes down. |
| Brute slam | 35 | **50** | No-sustain parties cannot comfortably ignore the telegraph. |
| Hexcaller HP | 70 → 105 in the partial pass | **140** | It survives long enough for landed casts and interrupts to occur. |
| Hexcaller circle damage | 45 | **55** | A landed cast is meaningful to a level-5 hero. |
| Hexcaller post-cast cooldown | 3.5 s | **2.0 s** | The interrupt check recurs during the opening fight. |
| Skitter HP | 30 | **45** | Level-5 35-damage hits and 28-damage Mender hits no longer one-shot it; one direct Staff hit plus splash can still kill it. |
| Slinger HP | 45 | **45 (unchanged)** | No further change was needed for the Court matrix. |
| Initial Court positions | Brutes (-340,-220), (340,-220); Hexcaller (0,-420) | **Brutes (-150,-170), (360,-150); Hexcaller (420,150)** | Keeps spawns visible and away from HUD panels at the arena centre. |
| Skitter pack A | t=12 s at (-780,40) | **t=4 s at (-440,220)** | Overlaps the area check with the opening slam/cast pressure and stays on-screen. |
| Skitter pack B | t=24 s at (780,40) | **t=12 s at (460,230)** | Prevents a long isolated tail and stays on-screen. |
| Brute final outline | White | **Dark crimson `#40040c`, 4 px** | Readable on the light floor; white remains reserved for interruptible casts. |
| Slinger aim line | Full 600 px targeting range | **Ends at the target (capped by the 640 px shot range), with an 18 px marker** | Identifies the intended friendly without drawing through the party. |
| Mend | 60 ally / 30 self, 6 s cooldown | **Unchanged** | 5 s and 4 s trials did not save the weaker intended pairing's echo; they mostly added healing to the stronger order. |

The Lance still has `interrupts = true`; the Staff still splashes 60% damage
within 80 pixels. The final wave centres plus 40-pixel jitter fit the 1280×720
view and avoid the stated HUD rectangles when the player is at screen centre.

### Idle matrix before tuning

```text
scenario                 outcome   time     hero HP  echo HP  echo lost  casts L/B  healing  left
arcanist_mender          FAILED    11.4s    20       0        9.6s       2/0        60       2
mender_vanguard          CLEARED   27.1s    75       5        -          1/1        0        0
vanguard_arcanist        FAILED    26.1s    30       0        15.1s      5/0        0        9
vanguard_mender          FAILED    11.4s    20       0        9.6s       2/0        60       2
vanguard_solo            FAILED    9.6s     5        -        -          2/0        0        3
vanguard_vanguard        CLEARED   27.1s    75       5        -          1/1        0        0
```

### Bot matrix before final tuning

This used the partial 240/105/45 HP values and the original 12/24-second waves.

```text
scenario                 bot side  outcome   time     hero HP  echo HP  echo lost  casts L/B  healing  left
arcanist_mender          hero      FAILED    37.2s    45       0        15.1s      7/0        60       9
mender_vanguard          hero      CLEARED   26.6s    75       120      -          1/0        0        0
vanguard_arcanist        hero      CLEARED   25.7s    120      75       -          1/0        0        0
vanguard_mender          hero      CLEARED   25.7s    85       75       -          1/0        0        0
vanguard_solo            hero      CLEARED   25.8s    85       -        -          1/0        0        0
vanguard_vanguard        hero      CLEARED   26.2s    120      85       -          0/1        0        0
```

### Bot matrix after tuning

```text
scenario                 bot side  outcome   time     hero HP  echo HP  echo lost  casts L/B  healing  left
arcanist_mender          hero      FAILED    28.2s    15       0        24.2s      7/0        120      1
mender_vanguard          hero      CLEARED   14.6s    95       80       -          1/1        140      0
vanguard_arcanist        hero      CLEARED   13.5s    20       65       -          1/1        0        0
vanguard_mender          hero      CLEARED   13.5s    20       0        6.7s       1/1        50       0
vanguard_solo            hero      FAILED    4.9s     15       -        -          1/0        0        7
vanguard_vanguard        hero      FAILED    5.6s     15       15       -          1/0        0        6
```

Both Vanguard+Mender orders clear. Mender player + Vanguard echo has a useful
margin; Vanguard player + Mender echo is a **thin clear at 20 hero HP with the
echo lost at 6.7 s**, not a clean party victory. Vanguard+Arcanist also clears,
but only thinly at 20 hero HP. Arcanist+Mender, solo Vanguard, and
Vanguard+Vanguard fail. Successful rows include both a landed and a broken
cast, so the interrupt mechanic participates in the result.

### Idle matrix after tuning

```text
scenario                 bot side  outcome   time     hero HP  echo HP  echo lost  casts L/B  healing  left
arcanist_mender          idle      FAILED    9.0s     7        0        8.1s       2/0        55       7
mender_vanguard          idle      FAILED    8.5s     7        0        7.3s       2/0        0        7
vanguard_arcanist        idle      FAILED    9.0s     7        10       -          2/0        0        6
vanguard_mender          idle      FAILED    9.0s     7        0        8.1s       2/0        55       7
vanguard_solo            idle      FAILED    8.5s     7        -        -          2/0        0        7
vanguard_vanguard        idle      FAILED    8.5s     7        0        7.3s       2/0        0        7
```

Times are active-fight seconds after the warning. Failed-row HP is the last
snapshot before the run reset. The bot is only a deterministic proxy: it does
not dodge, make human targeting mistakes, or evaluate readability and fun. The
M2 exit condition still requires human playtesting, including whether testers
deliberately choose jobs for future party needs. In particular, the global
600 HP Brute may feel too durable in the open arena, and the thin intended-pair
clear needs human confirmation; no visual verification is claimed here.
