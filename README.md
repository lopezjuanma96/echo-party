# Echo Party

Echo Party is a top-down 2D party roguelite about building the adventuring
party that future runs will inherit.

Every run begins with a novice. The active hero levels up, chooses a job,
learns skills, and eventually falls. Their recorded build can return as an
AI-controlled echo in later runs. Progress comes primarily from creating a
roster whose jobs and abilities cooperate against encounters no single hero
can solve.

The project takes inspiration from the interdependent party play of classic
MMORPGs, but uses an original setting, characters, systems, and assets.

## Status

Pre-production. The current combat prototype includes:

- one arena with Drifter, Skitter, Slinger, Brute, and Hexcaller enemies mixed by hero level;
- a player-controlled Novice that advances to Vanguard, Arcanist, or Mender at level 3;
- seven weapon-defined basic attacks, job-exclusive loadouts, and the Mend ability;
- renewable, deterministically seeded enemies and ordered level-up choices;
- two rotating level-5 Trials: Bell Court (interrupt/area/sustain) and Slinger Gallery (interrupt/area/range), with a Trial panel, job annotations, and after-action reports;
- up to two inspectable tactical echoes with slot-based commands, HUD rows, and shared XP;
- a persistent roster resolution screen after death, with party and memorial slots, swapping, and Echo Anchors;
- history extension: an echo that outlevels its record asks you to author its next attribute; and
- persistent numbered heroes, Trial-clear slot unlocks, and one Echo Anchor per clear.

See [Game Design](docs/game-design.md), [Roadmap](docs/roadmap.md), and
[Architecture](docs/architecture.md) for the current plan.

## Development

Requirements:

- Godot 4.7 or a compatible Godot 4 release

Open `project.godot` in Godot or run:

```sh
godot --editor --path .
```

Run the project from the command line with:

```sh
godot --path .
```

Run the focused domain, progression, party, combat, feedback, and encounter checks with:

```sh
godot --headless --path . --script res://tests/test_roster.gd
godot --headless --path . --script res://tests/test_save.gd
godot --headless --path . --script res://tests/test_hero_progression.gd
godot --headless --path . --script res://tests/test_echo.gd
godot --headless --path . --script res://tests/test_party.gd
godot --headless --path . --script res://tests/test_extension.gd
godot --headless --path . --script res://tests/test_resolution.gd
godot --headless --path . --script res://tests/test_persistence_flow.gd
godot --headless --path . --script res://tests/test_mender.gd
godot --headless --path . --script res://tests/test_enemies.gd
godot --headless --path . --script res://tests/test_casters.gd
godot --headless --path . --script res://tests/test_feedback.gd
godot --headless --path . --script res://tests/test_encounter.gd
```

Scenario scenes under `tests/scenarios/` start a chosen party at a chosen level
for playtesting (run one with `godot --path . res://tests/scenarios/<file>`).
The `vanguard_mender_arcanist_5` scenes exercise two echoes, with and without
the Bell Court; `vanguard_mender_vanguard_5_hurt` exercises healing with two
echoes. Every `*_5_court.tscn` scene starts the Bell Court at level 5 through
its 3-second warning. `vanguard_mender_arcanist_5_focus2` sets the command
address to Echo 2 and focuses a Brute through the right-click path, so a
tester without a mouse can read the result from `_mcp_state`. The
`resolution_*` scenes open the roster screen directly: `resolution_room` (a
free memorial slot), `resolution_full_anchor` (everything full, one Anchor),
`resolution_swap_only` (no candidate), and `resolution_two_slots` (all five rows
and an Anchor). `vanguard_mender_4_extend` grants 100 XP at start so the
hero's level-5 modal opens, then the Mender echo's extension modal;
`vanguard_mender_arcanist_4_extend2` starts both echoes at level 4 (records at
levels 4 and 6) and grants 200 XP: the hero and Echo 1 are asked twice, while
Echo 2 stays inside its record and never prompts. `persist_new_slot` and
`persist_reload_slot` share the isolated `user://playtest_saves/pw1.json` slot;
the former resets it, while the latter loads it without scenario overrides.
`vanguard_mender_5_court_clear_slot` uses isolated slot `pw2` and clears the
Court immediately to expose the first unlock and Anchor award.

Run the deterministic balance matrix (Bell Court, then Slinger Gallery) with:

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --leave-choices
```

The nine `*_5_gallery.tscn` scenes explicitly start Slinger Gallery at level 5,
including both Vanguard/Arcanist orders, missing-range parties, solo, and two-echo
comparisons. `--echo-level=4` and `--echo-level=7` override recorded echo levels
for either table (solo is skipped).

The matrix answers every level-up and extension modal with the first option
(Might) so the XP earned in the fight cannot stall a row; `--leave-choices`
leaves them open and reproduces the earlier tables.

By default, a harness-only player bot uses Mend when a friendly in range is at
60% health or less, reuses the echo's target and weapon priorities, aims and
attacks off cooldown, and moves to roughly 90% of weapon range using its job's
melee, ranged, or support posture. It does not dodge or change real-player
controls. The `bot side` column identifies the hero bot; `--idle` reproduces the
original idle-player comparison. The bot is a tuning proxy, not a substitute
for human playtesting.

### Current controls

- Move: `WASD` or arrow keys
- Dodge roll: `Space`
- Aim: mouse pointer
- Basic attack: left mouse button
- Job ability (Mend): `E` (listed in the controls panel)
- Select available weapon slot: `1` / `2`
- Cycle command address `All → Echo 1 → Echo 2 → All`: mouse wheel
- Focus an enemy for addressed echoes: right mouse button near that enemy
- Regroup addressed echoes and clear focus/hold: `R`
- Toggle addressed hold-position/follow stance: `Q`; on `All`, hold everyone unless everyone is already holding

The command address returns to `All` after every command and when the addressed
echo falls.
- Choose an attribute or job while leveling: `1` / `2` / `3` or the modal buttons
- Roster screen (modal, only while it is open): `1`-`5` pick a row, `Backspace` or `Esc` cancels a selection, `X` discards the fallen hero with an Echo Anchor, `Enter` confirms a pending loss or discard (otherwise starts the run), plus a mouse button for each action

The controls use named Godot input actions so they can be exposed through a
keybinding menu later.

The arena starts with wandering Drifters. From level 3, Skitter packs chase the
party and Slingers kite at range, firing a dodgeable dart at the most wounded
friendly. From level 4, Brutes telegraph an area slam that punishes anyone
standing in melee, and Hexcallers cast a locked 2-second damage circle that a
Lance hit (or 60 damage) interrupts. Contact and slams can damage the active hero or echo, and
dodge rolls avoid active-hero damage while the roll is active. On active-hero defeat, the completed build is captured and the next numbered run starts at the center as a full-health level-1
Novice with Knife, 0 XP, and cleared attack/dodge/input state.

**Roster resolution.** Normal play starts with one party echo slot and one
memorial slot. The first Trial clear unlocks party slot 2; the third total clear
unlocks memorial slot 2. Newly unlocked slots are available at the next
resolution, and nothing joins a run in progress. Only a fallen hero who chose a
job (level 3 or later) becomes a candidate. A hero that never advanced is not
offered and a notice says so. When there is a candidate, or the memorial holds
someone, the game pauses on the roster screen before the next run: rows for the
candidate, each party slot, and each memorial slot (`1`-`5`); pick a hero, then
a destination. Moves that lose nobody commit at once and show the result
(`Hero 1 → Memorial 1 · Hero 2 → Party 1`). A move that would lose a hero (the
candidate into an occupied party slot with a full memorial, or into an occupied
memorial slot) shows that hero's name and needs a second press on the same row
(or `Enter`). Party and memorial heroes can also be swapped or moved to empty
slots. **Start run** stays disabled until the candidate is placed or discarded.
Discarding costs one Echo Anchor (two presses of `X` or the button) and leaves
the roster untouched; with no Anchor it is disabled. Each Trial clear grants
one Anchor, up to one held. It belongs to the current run, is saved only with
an open resolution, and is dropped unspent when the next run begins. The screen
also shows whether the party's jobs cover the next Trial's needs, which job the
next hero should fill, the Anchor count, and the next unlock. Each echo spawns
near the new active hero as a level-1 Novice and automatically replays its
recorded attribute and job choices as it levels.

**Saving.** The normal save is `user://echo_party_save.json` (on Linux,
`~/.local/share/godot/app_userdata/Echo Party/echo_party_save.json`). The game
writes on death after chosen echo extensions are committed, when a resolution
is confirmed, and on each Trial clear. Hero numbers, unlocks, clear counts,
party, and memorial persist. Relaunching an open resolution restores its
candidate and Anchor count. Quitting mid-run abandons unsaved run progress;
settings and run state are not saved. Corrupt saves are copied to a `.corrupt`
backup, and saves from a newer version remain untouched and read-only. Headless
runs and ordinary scenarios use memory-only storage unless an isolated test or
playtest slot is explicitly selected.

**History extension.** Echoes keep gaining XP past the end of their record. Each
level beyond it opens the same level-up modal, titled with the echo
(`ECHO 1 · Hero 2 (Mender) · LEVEL 6 — CHOOSE AN ATTRIBUTE`) and offering Might
or Vitality; the hero's choices come first, then echoes in slot order, with one
prompt per level and no XP lost. The echo's world label shows `ECHO 1 · Lv 6*`
while a choice is pending. A chosen level extends the echo's record in the
roster at once and becomes durable at the next save point; the echo replays it
from level 1 next run. A defeated echo, or one whose hero falls with a choice
still open, keeps only the levels it already chose. Extension never resets an
echo's cooldowns or loadout.

Every enemy reward grants the same XP to the active hero and every living echo.
Echoes follow slot-specific anchors and deterministically select nearby enemies
and range-appropriate weapons. A Mender echo casts Mend when a nearby friendly
is at 60% health or less, including during hold and regroup. A Vanguard echo
prefers casting enemies within 450 pixels, switches to the Lance, and shows the
`interrupt` intent. Focus overrides target selection; hold attacks without
moving; regroup clears focus and hold until the echo reaches its follow anchor.
The HUD has one block per slot for command, tactical intent, cooldowns, and
health. World labels, focus-marker digits, and status overlays distinguish each
echo. The displayed intent holds for at least 0.25 seconds so one-tick Mend and
cooldown waits stay readable. Enemy contact can defeat each echo independently;
a defeated echo stays absent for the rest of that run and stops receiving XP.

**Trial rotation.** Odd hero numbers face Bell Court; even numbers face Slinger
Gallery. Both trigger at active-hero level 5 after choices are answered. The
roster screen names the next hero's Trial before you place or swap echoes.
Gallery needs `INTERRUPT`, `AREA`, and `RANGE`, favouring Vanguard + Arcanist;
it uses Slinger/Hexcaller crossfire and Skitter pressure, with a stronger
encounter for two echoes. Clears of either Trial count toward the same slot
unlocks. Final waves and tuning tables are in the game design and M3 plan.

**The Bell Court.** A Trial panel at top centre shows, from run start, the
needs of the upcoming Trial (Bell Court: `INTERRUPT`, `AREA`, `SUSTAIN`) with a `✓` and
the covering job or a `✗`. Coverage uses every roster echo's final recorded job
in slot order plus your own job once chosen, and works in run 1 with no echo. At level 3 each job
button notes the uncovered needs it fills (`Fills Trial need: SUSTAIN ★`). When
the active hero reaches level 5 with no choice pending, the arena clears and a
3-second banner announces the Court. Two Brutes and a Hexcaller arrive first,
then Skitter packs at 4 and 12 seconds. Starting with two echoes adds two
Hexcallers and a Brute and gives Court enemies 25% more health; the zero- and
one-echo Court is unchanged. Clearing awards 300 XP (530 with two echoes), one
Echo Anchor (maximum one held), and any earned capacity unlock, then resumes
normal spawning. A report panel then lists casts landed and broken,
damage taken per enemy (hero and lumped echo damage), healing done, each echo's
survival by slot and job, and a `Missing:` line for each uncovered need. If the hero falls
mid-Court, the same report appears at the start of the next run.

The Novice has only a short, quick Knife arc, so slot 2 does nothing. At level
3, Vanguard equips Sword and Lance, Arcanist equips Wand and Staff, and Mender
equips Mace and Sling. Mender weapons deal 80% of progression-derived damage.
Lance hits interrupt enemy casts, and Staff
bolts splash 60% damage onto enemies within 80 pixels of the target.
Mend immediately heals the most-wounded friendly within 240 pixels for 60, or
30 for the caster, with a 6-second cooldown. If nobody is wounded it does
nothing and spends no cooldown. A green ring and a floating `+60` also appear
on the healed ally. The weapon panel shows a cooldown bar for the selected
weapon, Mend's cooldown with no-target feedback, and the dodge roll's cooldown.

Current enemy numbers:

- Drifter: 50 HP, 10 contact damage every 0.5 seconds.
- Skitter: 45 HP, 8 contact damage every 0.6 seconds, four per pack.
- Slinger: 45 HP, 14 dart damage every 2.4 seconds after a 0.6-second windup.
- Brute: 600 HP, 50 slam damage in radius 88 after a 0.9-second windup.
- Hexcaller: 140 HP, 55 circle damage after a 2-second cast, with a 2-second
  post-cast cooldown; a Lance hit or 60 damage during the cast interrupts it.

Each enemy grants its XP once: Drifter 50, Skitter 10, Slinger 50, Brute 70, Hexcaller 80. The seeded spawner replaces defeated enemies
after a short delay and keeps seven in the arena; its delay stops while combat
is paused. A level is gained every 100 total XP. Level 2 offers Might or
Vitality, level 3 (200 total XP) offers Vanguard, Arcanist, or Mender with no
attribute choice, and level 4 onward returns to attributes. The centered choice
modal pauses combat while remaining interactive; if several levels were gained,
choices are resolved in order. Progression is temporarily unlimited, so every
level after advancement continues to add an attribute choice.

## Licensing

Project source code is available under the [MIT License](LICENSE).
Third-party assets are not automatically covered by that license. Every asset
added to the repository must be recorded in
[THIRD_PARTY_ASSETS.md](assets/third_party/THIRD_PARTY_ASSETS.md) with its
source and license.
