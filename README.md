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
- the Bell Court, a level-5 Trial that rewards a Vanguard + Mender party, with a visible Trial panel, level-3 job annotations, and an after-action report;
- an inspectable tactical echo built by replaying the previous hero's record; and
- defeat followed by a fresh numbered run beside that echo.

Persistent roster and memorial resolution remain planned work.

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

Run the focused progression, echo, Mender, enemy, caster, feedback, and encounter checks with:

```sh
godot --headless --path . --script res://tests/test_hero_progression.gd
godot --headless --path . --script res://tests/test_echo.gd
godot --headless --path . --script res://tests/test_mender.gd
godot --headless --path . --script res://tests/test_enemies.gd
godot --headless --path . --script res://tests/test_casters.gd
godot --headless --path . --script res://tests/test_feedback.gd
godot --headless --path . --script res://tests/test_encounter.gd
```

Scenario scenes under `tests/scenarios/` start a chosen party at a chosen level
for playtesting (run one with `godot --path . res://tests/scenarios/<file>`).
The `*_5_court.tscn` scenes (`vanguard_mender`, `mender_vanguard`,
`vanguard_arcanist`, `arcanist_mender`, `vanguard_vanguard`, and
`vanguard_solo`) start the Bell Court immediately at level 5, still through its
3-second warning.

Run the deterministic Bell Court balance matrix with:

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
```

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
- Select available weapon slot: `1` / `2` or mouse wheel
- Focus an enemy for the echo: right mouse button near that enemy
- Regroup the echo and clear focus/hold: `R`
- Toggle echo hold-position/follow stance: `Q`
- Choose an attribute or job while leveling: `1` / `2` / `3` or the modal buttons

The controls use named Godot input actions so they can be exposed through a
keybinding menu later.

The arena starts with wandering Drifters. From level 3, Skitter packs chase the
party and Slingers kite at range, firing a dodgeable dart at the most wounded
friendly. From level 4, Brutes telegraph an area slam that punishes anyone
standing in melee, and Hexcallers cast a locked 2-second damage circle that a
Lance hit (or 60 damage) interrupts. Contact and slams can damage the active hero or echo, and
dodge rolls avoid active-hero damage while the roll is active. On active-hero defeat, the completed build is captured in
memory and the next numbered run starts at the center as a full-health level-1
Novice with Knife, 0 XP, and cleared attack/dodge/input state.

The temporary first-echo rules keep only the newest fallen hero. It replaces
the prior echo and spawns near the new active hero as a level-1 Novice. Every
enemy reward grants the same XP to the active hero and echo; as the echo levels,
it automatically replays the fallen hero's recorded attribute and job choices
in order. It stops at the highest fully recorded level until history extension
is implemented. There is no disk persistence, roster, or memorial yet. The echo
follows the active hero and deterministically selects nearby enemies and
range-appropriate weapons. A Mender echo casts Mend when a nearby friendly is
at 60% health or less, including during hold and regroup. A Vanguard
echo prefers casting enemies within 450 pixels, switches to the Lance, and shows
the `interrupt` intent. Right-clicking a
nearby enemy overrides target selection with a marked focus target. Hold stance
attacks without moving; regroup clears focus and hold until the echo returns to
the active hero. The HUD shows the current command, the
tactical intent (`Intent: Interrupt → Hexcaller · 212 px`), the echo's weapon and
ability cooldowns, and its health, and the world label mirrors command and
health state. Below the echo, a status overlay draws a health bar, a thin
weapon-cooldown bar, an ability pip that fills as Mend recharges, an intent
glyph (distinct shapes, not only colours), and a line to the intent target. The
displayed intent holds for at least 0.25 seconds, so a one-tick Mend and a wait
for weapon cooldown during a fight (shown as attack, not the hold stance)
stay readable. Enemy contact can
defeat the echo; a defeated echo stays absent for the rest of that run and only
returns if a later active hero is recorded as the new echo.

**The Bell Court.** A Trial panel at top centre shows, from run start, the
needs of the level-5 Bell Court (`INTERRUPT`, `AREA`, `SUSTAIN`) with a `✓` and
the covering job or a `✗`. Coverage is the echo's recorded job plus your own job
once chosen, and the panel works in run 1 with no echo. At level 3 each job
button notes the uncovered needs it fills (`Fills Trial need: SUSTAIN ★`). When
the active hero reaches level 5 with no choice pending, the arena clears and a
3-second banner announces the Court. Two Brutes and a Hexcaller arrive first,
then Skitter packs at 4 and 12 seconds. Clearing it awards about 300 XP and
resumes normal spawning. A report panel then lists casts landed and broken,
damage taken per enemy (hero and echo), healing done, whether the echo
survived, and a `Missing:` line for each uncovered need. If the hero falls
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
