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

Pre-production. The first milestone is a combat proof of concept with:

- one arena and one enemy family;
- a player-controlled novice;
- two first jobs with complementary abilities;
- level-up choices and job advancement;
- death, build recording, and run restart; and
- one AI-controlled echo that follows its recorded build.

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

## Licensing

Project source code is available under the [MIT License](LICENSE).
Third-party assets are not automatically covered by that license. Every asset
added to the repository must be recorded in
[THIRD_PARTY_ASSETS.md](assets/third_party/THIRD_PARTY_ASSETS.md) with its
source and license.
