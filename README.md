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

- one arena and one enemy family;
- a player-controlled Novice that advances to Vanguard or Arcanist at level 3;
- five weapon-defined basic attacks and job-exclusive loadouts;
- renewable, deterministically seeded enemies and ordered level-up choices;
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

Run the focused progression and XP reward checks with:

```sh
godot --headless --path . --script res://tests/test_hero_progression.gd
godot --headless --path . --script res://tests/test_echo.gd
```

### Current controls

- Move: `WASD` or arrow keys
- Dodge roll: `Space`
- Aim: mouse pointer
- Basic attack: left mouse button
- Select available weapon slot: `1` / `2` or mouse wheel
- Choose an attribute or job while leveling: `1` / `2` or the modal buttons

The controls use named Godot input actions so they can be exposed through a
keybinding menu later.

The movement sandbox currently includes wandering enemies. Contact can damage
the active hero or echo, and dodge rolls avoid active-hero contact damage while
the roll is active. On active-hero defeat, the completed build is captured in
memory and the next numbered run starts at the center as a full-health level-1
Novice with Knife, 0 XP, and cleared attack/dodge/input state.

The temporary first-echo rules keep only the newest fallen hero. It replaces
the prior echo and spawns near the new active hero with its recorded level,
attributes, job, stats, and loadout replayed. There is no disk persistence,
roster, or memorial yet. The echo follows the active hero and deterministically
selects nearby enemies and range-appropriate weapons. Echo kills grant XP to
the current active run through the same enemy reward signal. Enemy contact can
defeat the echo; a defeated echo stays absent for the rest of that run and only
returns if a later active hero is recorded as the new echo.

The Novice has only a short, quick Knife arc, so slot 2 does nothing. At level
3, Vanguard immediately equips Sword and Lance (a medium wide arc and a long
narrow thrust), while Arcanist immediately equips Wand and Staff (a shorter,
quicker projectile and a longer, slower projectile). Every basic attack uses
the hero's progression-derived damage and costs no mana.

Each enemy grants 50 XP once. The seeded spawner replaces defeated enemies
after a short delay and keeps seven in the arena; its delay stops while combat
is paused. A level is gained every 100 total XP. Level 2 offers Might or
Vitality, level 3 (200 total XP) offers Vanguard or Arcanist with no attribute
choice, and level 4 onward returns to attributes. The centered choice modal
pauses combat while remaining interactive; if several levels were gained,
choices are resolved in order. Progression is temporarily unlimited, so every
level after advancement continues to add an attribute choice.

## Licensing

Project source code is available under the [MIT License](LICENSE).
Third-party assets are not automatically covered by that license. Every asset
added to the repository must be recorded in
[THIRD_PARTY_ASSETS.md](assets/third_party/THIRD_PARTY_ASSETS.md) with its
source and license.
