# Game Design

This is a living design outline, not a promise of final content or balance.

## Vision

Echo Party is a single-player roguelite that recreates the satisfaction of a
large, interdependent MMO party. The player creates that party over multiple
runs, one adventurer at a time.

The central question is not only "How strong can this hero become?" but "What
does the party need me to leave behind?"

## Design Pillars

1. **Interdependence over self-sufficiency.** Jobs solve different problems,
   and difficult encounters require combinations of roles and abilities.
2. **The party is progression.** A failed run can still create a valuable new
   party member or extend an existing echo's build history.
3. **Authored history, autonomous action.** The player owns each echo's build;
   predictable tactical rules control it during combat.
4. **Meaningful roster pressure.** Limited party and memorial capacity makes
   keeping, replacing, and preserving heroes consequential.
5. **Readable complexity.** Combat must communicate intent, targets, ranges,
   cooldowns, and synergies clearly as party size grows.

## Vocabulary

- **Active hero:** the only directly controlled adventurer in the current run.
- **Echo:** a previous active hero returning under computer control.
- **Build history:** ordered job, attribute, and skill choices by level.
- **Party roster:** echoes available at the start of the next run, subject to
  the current party-size limit.
- **Memorial:** persistent storage for selected echoes outside the active
  roster. "Podium" remains an alternative name to test with players.

## Run Loop

1. Start as a level-one novice with the selected echoes.
2. Explore and fight encounters designed around party roles.
3. Gain levels and choose attributes and skills.
4. At the advancement level, select a first job.
5. Find equipment and consumables that last for this run.
6. Defeat a milestone encounter or die.
7. Record the active hero's ordered build history.
8. Compose the next party: add or replace an echo, use a preservation item,
   or move a hero through a memorial slot.
9. Begin again with a new novice.

## Echo Rules

An echo is not a recording of exact movement or button presses. Its build is
replayed deterministically at each level, while a job-specific tactical policy
chooses movement, targets, and abilities.

Tactical behavior should be inspectable and adjustable through a small set of
priorities, such as protecting the active hero, maintaining distance, healing
below a health threshold, or focusing marked enemies. Machine learning is out
of scope until conventional AI has proven insufficient.

If an echo exceeds the highest level in its build history, the player chooses
its next attribute or skill when it levels. That choice extends the echo's
history for future runs. This is part of party progression, not a temporary
run bonus.

### First-Echo Vertical Slice

The current temporary rules are intentionally narrower than the eventual
roster loop. Active-hero defeat snapshots a strict, ordered `HeroRecord` in
memory, increments the visible run number, and immediately starts a full-health
level-1 Novice with Knife and 0 XP. Only the newest record is retained: its echo
replaces any previous echo and replays the recorded level, attributes, derived
stats, job, and loadout. There is no disk persistence, roster choice, or
memorial behavior in this slice.

The echo follows the active hero while idle and uses deterministic target and
range-aware weapon selection within a leash around that hero. Vanguard closes
to melee range; Arcanist approaches when out of range and retreats when an
enemy is too close. Enemy rewards are shared progression: every enemy defeat,
including an echo kill, grants XP to the current active run. Echoes have health
and can take enemy contact damage. A defeated echo is absent for the remainder
of that run and returns only when a later fallen active hero creates the newest
record.

## Death And Roster Resolution

The active hero becomes a candidate echo after a run. If the party has room,
the candidate can join it. If it is full, the player normally chooses an echo
to replace.

Run-only preservation consumables can allow the current roster to remain
unchanged, discarding the candidate. Memorial slots allow valuable echoes to
be stored and later swapped into a party slot. Exact capacities are balance
questions; the prototype should test two party members before assuming that a
party of twenty remains readable or fun.

## Progression Layers

Permanent progression should create options rather than simply multiply
damage:

- new echoes and extended build histories;
- additional party slots up to a tested cap;
- memorial slots up to a tested cap;
- new jobs, skills, enemies, regions, and encounter combinations; and
- additions to the possible loot pool.

Equipment is found, equipped, and lost within a run. Unlocks may add items to
future drop pools, but should not guarantee stronger starting equipment.

### Prototype Attribute Rules

The current vertical slice uses stable attribute IDs `might` and `vitality`.
Heroes begin at level 1 with 0 XP, 100 max health, 25 attack damage, and the
`novice` job. Every 100 total XP grants a level and exactly one ordered build
choice. Level 2 offers Might or Vitality. Level 3 is the advancement level at
200 total XP and offers `vanguard` or `arcanist` instead of an attribute.
Level 4 and every later level return to attributes; progression is temporarily
unlimited in this prototype. Might adds 5 attack damage; Vitality adds 20 max
health and raises current health by the same amount rather than fully healing.
Derived stats and job state are replayed from the same ordered `choices` array.

## Encounter Philosophy

Enemies should create explicit role checks rather than merely gaining health:

- armor that rewards magic or armor breaking;
- dangerous casts that reward interruption;
- swarms that reward area control;
- focused pressure that rewards protection and healing;
- positioning mechanics that reward mobility; and
- linked enemies that require coordinated target priority.

Early encounters should be survivable by a novice alone. Later encounters may
be intentionally unreasonable without complementary echoes.

## Combat And Controls

Combat is real-time and movement is directly controlled with a keyboard or
controller. The initial keyboard scheme uses `WASD` or arrow keys for movement
and `Space` for a directional dodge roll. Click-to-move remains a possible
alternative control scheme rather than the default.

Skills use remappable action slots. A skill may execute immediately around the
caster, use the actor's facing direction, wait for a ground coordinate, or
require a valid unit target. Range and targeting rules belong to the skill,
not to its keybinding. The exact default keys will be tested once skills exist.

### Basic Attacks

Basic attacks come from the equipped weapon rather than the hero's job. A
weapon may be restricted to one or more jobs, but it grants the same basic
attack to every job allowed to equip it. Basic attacks cost no mana, require a
direction and an attack input, and use a weapon-specific internal cooldown.

The default mouse scheme aims relative to the active hero and attacks with the
left button. This maps naturally to aiming with a gamepad's right stick. Number
keys and the mouse wheel switch equipped weapons in the prototype.

Basic attacks may be melee shapes such as an arc or thrust, or physical ranged
attacks such as a bolt that travels until it hits something or reaches its
maximum distance.

The prototype has five stable weapon IDs. Novices equip only `knife`, a short,
quick melee arc; their second slot therefore does nothing. Vanguards equip
`sword`, a medium and wider melee arc, and `lance`, a long and narrow melee
thrust. Arcanists equip `wand`, a shorter and quicker projectile, and `staff`,
a longer and slower projectile. Advancing changes the loadout immediately and
selects its first slot. All five use progression-derived attack damage.

### Skills

Skills are primarily learned from jobs and improved with level points. Unlike
basic attacks, skills generally consume mana. Activating a skill enters one of
four targeting modes:

1. **Immediate:** resolves without a click, usually on the caster or in a
   radius around them.
2. **Directional:** waits for a (click in) direction, then performs a melee or ranged
   action along it.
3. **Ground:** waits for a (click in) visible map coordinate within range, then places an
   area effect there.
4. **Unit:** waits for a (click in) valid self, ally, enemy, or other target within range.

Skill-slot keys remain undecided. Function keys and keys surrounding `WASD`
are both candidates and must be remappable.

## Initial Jobs

The combat proof uses only two first jobs:

- **Vanguard:** holds attention, interrupts, and protects an ally.
- **Arcanist:** deals ranged elemental damage and exploits controlled enemies.

For this vertical slice, jobs are distinguished only by exclusive weapon
loadouts: Vanguard uses Sword/Lance and Arcanist uses Wand/Staff. Skills, mana,
and passives are not implemented yet.

Names and abilities are placeholders. The pair exists to test whether a
recorded defender and a newly controlled damage dealer, or the reverse, feels
meaningfully different.

## Prototype Enemy Population

The arena maintains seven wandering enemies. Each defeated enemy awards its XP
once to the current active run, regardless of whether the active hero or echo
made the kill, and is replaced after a short delay. Spawn choices use fixed
seeds, stay inside the arena, avoid the active hero, and prefer separation from
existing enemies. Because spawning follows paused simulation time,
replacements cannot appear behind a level-choice modal.

## Open Design Questions

- Does an extended echo history persist immediately or only after surviving a
  checkpoint?
- Can the active hero issue focus, retreat, and formation commands to echoes?
- Should roster resolution happen after every death or only after meaningful
  progress?
- What party size remains readable without turning the player into a raid
  manager?
- How much procedural generation helps replayability without weakening
  authored role checks?

## Explicit Non-Goals For The First Milestone

- imitation learning or reinforcement learning;
- a large procedural world;
- persistent equipment;
- more than one echo at a time;
- advanced job tiers;
- online multiplayer; and
- final art, audio, story, or balance.
