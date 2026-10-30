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
replaces any previous echo but also starts as a level-1 Novice. Each enemy
reward grants equal XP to the active hero and echo. At each echo level, its
recorded attribute or job choice is applied automatically, deriving the same
stats and loadout in order rather than restoring the fallen hero's terminal
state immediately. There is no disk persistence, roster choice, or memorial
behavior in this slice.

The echo follows the active hero while idle and uses deterministic target and
range-aware weapon selection within a leash around that hero. Vanguard closes
to melee range; Arcanist approaches when out of range and retreats when an
enemy is too close. Mender prioritizes Mend for a friendly at 60% health or
less, retreats from nearby enemies, and limits pursuit to a support leash.
An echo carrying an interrupting weapon (Vanguard's lance) prefers a casting
enemy within 450 pixels over other targets, switches to the interrupting weapon
once the caster is in its range, and shows the `interrupt` intent while closing
on or attacking it. Manual focus still wins.
Every enemy defeat, including an echo kill, advances both
the active hero and the echo. For now, an echo stops at the highest level whose
choice is complete in its record; extending that history remains later work.
Echoes have health and can take enemy contact damage. A defeated echo is absent
for the remainder of that run and returns only when a later fallen active hero
creates the newest record.

### Echo Commands

The current party-command slice adds three deterministic overrides. Right-click
an enemy to focus it; the purple target ring identifies the selected enemy, and
the focus ends when that enemy dies, leaves the active hero's leash, or regroup
is ordered. `Q` toggles a hold-position stance: the echo keeps its target and
attacks enemies in weapon range but does not approach or retreat. `R` clears
focus and hold, then moves the echo back to the active hero before normal
tactical behavior resumes. The HUD exposes the current command, tactical
intent, echo cooldowns, and echo health so these overrides remain inspectable.

### Echo Intent Feedback

The echo shows what it is doing, and how soon it can act again, without a
dedicated inspection screen. A status overlay below the echo shows its health,
the selected weapon's cooldown, and (for jobs with an ability) a pip that fills
as the ability recharges and turns solid when ready. An intent glyph and a line
to the intent target use the same colour per intent, and each glyph has its own
shape so colour is never the only signal:

| Intent | Glyph | Colour |
|---|---|---|
| attack | crossed lines | red |
| approach | chevron toward the target | cyan |
| retreat | chevron away from the target | orange |
| hold | two bars | grey |
| follow | three dots | blue |
| regroup | ring with dot | blue |
| heal | plus | green |
| interrupt | zigzag | yellow |
| idle | none | none |

The shown intent changes at most every 0.25 seconds. During a fight, waiting on
weapon cooldown shows as attack (or interrupt against a casting target) rather
than hold; the hold stance still shows hold. The HUD lists the intent with its
target and range (`Interrupt → Hexcaller · 212 px`, `Mend → Hero 2 · 38%`) and
every cooldown (`Mace Ready · Sling 0.4s · Mend 3.4s`). When Mend lands, the
healed ally also gets a green ring and a floating amount, not only the caster.

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
200 total XP and offers `vanguard`, `arcanist`, or `mender` instead of an attribute.
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

The prototype has seven stable weapon IDs. Novices equip only `knife`, a short,
quick melee arc; their second slot therefore does nothing. Vanguards equip
`sword`, a medium and wider melee arc, and `lance`, a long and narrow melee
thrust. Arcanists equip `wand`, a shorter and quicker projectile, and `staff`,
a longer and slower projectile. Menders equip `mace`, a wide melee arc, and
`sling`, a medium-range projectile. Advancing changes the loadout immediately
and selects its first slot. Weapons use progression-derived attack damage
multiplied by their `damage_multiplier`; both Mender weapons use the default
0.8 multiplier, so 25 base damage deals 20.

Two weapons carry role flags:

- `lance` hits are marked `interrupts`, which breaks an enemy cast outright.
- `staff` bolts splash for 60% damage on other enemies within 80 pixels of an
  enemy hit. Wall hits do not splash.

Basic attacks are otherwise single-target, so splash makes the staff the
Arcanist's answer to packs.

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

The first ability, Mend, is immediate and costs no mana. The remappable
`ability_1` action defaults to `E`. Mend heals the friendly actor with the
lowest health fraction within 240 pixels for 60, or 30 when targeting the
caster. It has a 6-second cooldown; with no wounded target it does nothing and
spends no cooldown. The 50% self-heal fraction is the default tuning for
limiting solo Mender sustain.

## Initial Jobs

The combat proof uses three first jobs:

- **Vanguard:** holds attention, interrupts, and protects an ally.
- **Arcanist:** deals ranged elemental damage and exploits controlled enemies.
- **Mender:** provides backline sustain with weak offense and Mend.

Jobs have exclusive weapon loadouts and may grant abilities. Vanguard uses
Sword/Lance, Arcanist uses Wand/Staff, and Mender uses Mace/Sling. Mana and
passives are not implemented yet.

Each job lists capability tags that Trials check: Vanguard provides
`interrupt` and `area`, Arcanist provides `area` and `range`, and Mender
provides `sustain`. Novice provides none.

Names and abilities are placeholders. The jobs test whether recorded and newly
controlled heroes form meaningfully different parties.

## Prototype Enemy Population

The arena maintains a population of seven enemies. Each defeated enemy awards
its XP once to the current active run, regardless of whether the active hero
or echo made the kill, and is replaced after a short delay. Spawn choices use
fixed seeds, stay inside the arena, avoid the active hero, and prefer
separation from existing enemies. Because spawning follows paused simulation
time, replacements cannot appear behind a level-choice modal.

Enemy variants test specific party skills. The mix depends on the active
hero's level, and a separate seeded type stream chooses each variant, so
spawn positions stay reproducible:

| Level | Mix |
| --- | --- |
| 1–2 | Drifters only |
| 3 | Drifter 55 / Skitter pack 25 / Slinger 20 |
| 4+ | Drifter 40 / Skitter pack 20 / Slinger 15 / Brute 15 / Hexcaller 10 |

The variants:

- **Drifter** (`drifter`): a red square that wanders and deals contact damage.
  50 HP, 50 XP.
- **Skitter** (`skitter`): an orange triangle that tests area damage. It
  spawns in packs of four within a 40-pixel cluster, pulses during a 0.8 s
  spawn grace, then chases the nearest friendly and deals 8 contact damage
  every 0.6 s. 45 HP, 10 XP each, so a level-5 hero cannot one-shot it.
  - A pack takes one replacement slot, but its members count individually
    toward the population afterward. The arena can briefly exceed seven until
    enough enemies die.
- **Brute** (`brute`): a dark-red octagon that tests protection.
  - It chases the nearest friendly. Within 70 pixels it winds up for 0.9 s,
    behind a red ground circle that fills and flashes dark crimson at the end.
  - The slam deals 50 to every friendly within 88 pixels. The Brute then
    recovers for 0.7 s, desaturated and stationary, before a 0.8 s cooldown.
  - It deals no contact damage and cannot be interrupted. 600 HP, 70 XP.
  - A moving hero can leave the circle in time, but an echo standing in melee
    takes the slam.
- **Hexcaller** (`hexcaller`): a magenta hexagon that tests interruption and
  range. It keeps about 340 pixels from the nearest friendly (flees below 240,
  approaches above 440).
  - It casts for 2.0 s. At cast start it locks a radius-110 magenta circle on
    the nearest friendly's position; the circle stays there and fills with
    progress. On resolve, every friendly inside takes 55.
  - A white radius-34 break ring and a 44×4 cast bar mark the cast as
    interruptible. A `lance` hit breaks it, as do 60 cumulative damage during
    the cast (for example, three Mender hits of 20). A break cancels the cast,
    stuns it for 1.5 s, and shows a floating "INTERRUPTED" for 0.8 s.
  - The first cast comes 1.0 s after spawn grace, with a 2.0 s cooldown after
    each cast. 140 HP, 80 XP.
- **Slinger** (`slinger`): a teal diamond that tests range and protection. It
  keeps about 380 pixels from the nearest friendly (flees below 260).
  - Every 2.4 s it fires at the friendly with the lowest health fraction within
    600 pixels, nearest on ties. A 0.6 s windup shows a red aim line that tracks
    its target for 0.45 s and freezes for the last 0.15 s. The line ends at the
    target with a small marker rather than continuing through other friendlies.
  - The dart travels at 420 for up to 640 pixels, stops at walls, and deals 14
    to the first friendly it touches. A dodge-rolling hero takes none. 45 HP,
    50 XP.

Telegraph colours follow one rule: red or orange marks incoming damage, white
marks interruptible, and green or cyan marks friendly effects. The Brute's
last-0.1-second outline is therefore dark crimson, not white. Every telegraph
lasts at least 0.6 seconds. Each variant also differs in shape, so recognising
it does not depend on colour alone.

## Trial: The Bell Court

A Trial is a scripted encounter that names the party needs it checks. The first
is **The Bell Court** (`bell_court`), which needs **interrupt, area, and
sustain**. It fires once per run when the active hero reaches level 5 with no
level choice pending. It also fires in run 1 with no echo (decision G5), so the
first hero meets it with only their own job.

- **Warning (3.0 s).** A banner names the Court and its needs. Open-arena
  spawning pauses and the remaining drifters vanish without awarding XP.
- **Active.** Every Court enemy spawns with 1.0 s of spawn grace.
  - At t=0: two Brutes at (-150, -170) and (360, -150), and a Hexcaller at
    (420, 150).
  - At t=4 s: a Skitter pack of four at (-440, 220).
  - At t=12 s: a Skitter pack of four at (460, 230).
  - These centres and the 40-pixel pack jitter stay on-screen and outside the
    HUD panels when the player is at the arena centre.
  - Pack jitter and enemy seeds come from the encounter's own seeded random
    stream (seed 7117), so the Court replays identically.
- **Cleared** when every wave has spawned and no Court enemy is alive. Normal
  spawning resumes. The only reward is kill XP (about 300).
- **Failed** if the active hero is defeated first. The next run starts as usual
  and the Court re-arms.

Intended outcomes, from which the Court is tuned:

| Pair | Covers | Expectation |
| --- | --- | --- |
| Vanguard + Mender | interrupt, area, sustain | clears; margin may vary by player/echo order |
| Vanguard + Arcanist | interrupt, area | no sustain; fails or clears only thinly |
| Arcanist + Mender | area, sustain | no reliable interrupt; circles land, heals offset some |
| Vanguard + Vanguard | interrupt, area | no sustain; fails or clears only thinly |
| Novice or solo | little or none | usually fails |

The Vanguard echo prioritises casters and uses the Lance, so it interrupts
without help. The Arcanist echo does not interrupt, though a player-controlled
Arcanist can break casts with the Wand. The deterministic harness bot is only a
balance proxy; human playtesting remains the exit-condition evidence.

### Telling the player what is needed (decision G4)

Testers must be able to see the need before they choose a job:

- **Trial panel.** A top-centre panel is visible from run start:
  `TRIAL · Bell Court · Lv 5` with an INTERRUPT / AREA / SUSTAIN chip each.
  A covered chip reads `✓ NEED` and the covering job; an uncovered chip reads
  `✗ NEED` and `Missing`, so state never relies on colour alone. Coverage is the
  echo's recorded job plus the active hero's job once chosen. The echo's final
  recorded job counts from the start of the run, before the echo replays its
  choice, because the panel is for planning the next hero.
- **Job modal.** At level 3 each job button lists the uncovered needs it fills,
  e.g. `Fills Trial need: SUSTAIN ★`. Every option that fills a need gets the ★.
- **Trial report.** For 10 seconds after a clear, or at the start of the next
  run after a failure, a panel lists casts landed and broken, damage taken per
  enemy (hero and echo), healing done, whether the echo survived, and a
  `Missing: SUSTAIN → Mender provides SUSTAIN` line for each uncovered need.

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
