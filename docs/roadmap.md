# Roadmap

Milestones are ordered by risk, not by the amount of visible content.

## M0: Foundation

- Establish project conventions and a data-driven hero/build model.
- Add deterministic simulation support through seeded randomness.
- Set up automated tests for build replay and save/load behavior.
- Select a CC0 placeholder art set and document its license.

Exit condition: the project runs locally and serialized build histories can be
round-tripped without involving a scene.

## M1: Combat Proof

- Add one arena and keyboard/controller movement.
- Implement one enemy family with a readable attack.
- Implement health, damage, experience, and level-up choices.
- Add novice advancement into Vanguard or Arcanist.
- Implement one tactical AI echo.
- Record the active hero on death and restart beside that echo.
- Add basic combat and level-up UI.

Exit condition: a player can complete two consecutive runs and experience the
second run differently because the first hero returned as an echo.

## M2: Party Dependency

- Add enemies that test protection, interruption, area damage, and range.
- Add simple party commands: focus target, regroup, and stance.
- Add a third complementary job.
- Add the first encounter that strongly rewards a specific job combination.
- Improve feedback for echo intent and ability cooldowns.

Exit condition: testers deliberately build a hero for a future party need.

Status: every item above is implemented (variant enemies, party commands,
Mender, the Bell Court Trial, and echo intent/cooldown feedback). A deterministic
bot-proxy tuning pass is recorded in the M2 plan. The exit condition and final
balance still need human playtest evidence.

## M3: Roster Roguelite

- Implement replacement decisions after death.
- Add party-slot progression with a conservative initial cap.
- Add memorial storage and swapping.
- Add run-only roster preservation items.
- Extend echo histories when they surpass their recorded level.
- Version save data and handle migrations.

Exit condition: roster decisions create meaningful tradeoffs across several
runs without an obvious dominant strategy.

Status: all six systems above are implemented. The runtime supports two
slot-addressed echoes, roster resolution and memorial swapping, and player-
authored history extension. Persistent saves carry the roster, hero counter,
unlocks, clear counts, and pending resolutions. The first Trial clear unlocks
party slot 2, the third total clear unlocks memorial slot 2, and each clear
awards one run-only Echo Anchor (maximum one held). Bell Court and Slinger
Gallery now alternate by persisted hero number, with per-Trial clear counts and
next-Trial roster advice. The four-mode tuning matrix is recorded in the M3
plan. The Gallery caps its groups at six enemies, and its kiters use stat
overrides local to the Gallery. In the bot matrix every pure-melee party fails
it and every party with an Arcanist clears it; parties with a Mender also clear,
through the Sling. Human playtests must still show that roster swapping,
readability, and the lack of a dominant strategy hold up, so M3's exit
condition is not yet established.

## M4: Dungeon Slice

- Add a small sequence of authored or assembled rooms.
- Add run-only equipment, consumables, and loot tables.
- Add a boss requiring multiple roles.
- Add one coherent visual and audio pass.
- Add onboarding and a complete run summary.

Exit condition: a new player can understand, play, fail, inherit a hero, and
recognize why the next party is more capable.

## Later Exploration

- advanced and branching jobs;
- region and encounter generation;
- unlockable additions to loot pools;
- larger parties and formation tools;
- long-term collection goals;
- accessibility and control remapping; and
- behavior learned from play traces, only if it offers clear value over
  inspectable tactical policies.
