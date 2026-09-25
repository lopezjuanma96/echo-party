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
- a player-controlled novice;
- sword and bolt basic attacks;
- enemy XP rewards and ordered Might/Vitality level-up choices; and
- defeat and immediate arena reset.

Jobs, echoes, and persistent roster resolution remain planned work.

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
```

### Current controls

- Move: `WASD` or arrow keys
- Dodge roll: `Space`
- Aim: mouse pointer
- Basic attack: left mouse button
- Equip sword or bolt: `1` / `2` or mouse wheel
- Choose Might or Vitality while leveling: `1` / `2` or the modal buttons

The controls use named Godot input actions so they can be exposed through a
keybinding menu later.

The movement sandbox currently includes wandering enemies. Contact removes
health over time, dodge rolls avoid contact damage while active, and defeat
returns the player to the center at full health. As a temporary prototype
rule, this immediate defeat reset keeps the current run's level, XP, and build
choices.

The sword attacks in a short 20-degree arc. The bolt travels until it hits an
enemy or wall, or reaches its maximum range. Both basic attacks cost no mana
and have independent weapon cooldowns.

Each enemy grants 50 XP once. A level is gained every 100 total XP, and each
level queues one ordered attribute choice. The centered choice modal pauses
combat while remaining interactive; if several levels were gained, choices
are resolved one at a time.

## Licensing

Project source code is available under the [MIT License](LICENSE).
Third-party assets are not automatically covered by that license. Every asset
added to the repository must be recorded in
[THIRD_PARTY_ASSETS.md](assets/third_party/THIRD_PARTY_ASSETS.md) with its
source and license.
