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
its next attribute when it levels. That choice extends the echo's history for
future runs. This is part of party progression, not a temporary run bonus.

Extension is a live choice through the same level-up modal as the hero's. The
title names the echo (`ECHO 1 · Hero 2 (Mender) · LEVEL 6 — CHOOSE AN
ATTRIBUTE`) and offers Might or Vitality; echoes always have a job, so
extension levels are attributes. The hero's choice comes first, then each
echo in slot order, one prompt per level gained, and no XP is lost. The choice
replaces the echo's record in the roster immediately and becomes durable at the
next save point. A defeated echo, or one whose hero falls while its choice is
open, keeps only the levels it chose. Failure still counts as progression.

### Current Echo Runtime

Active-hero defeat snapshots a strict, ordered `HeroRecord`, increments the
persistent hero number, and starts a full-health level-1 Novice with Knife and
0 XP once the roster screen (see Death And Roster Resolution) is resolved.
Normal play starts with one party slot and one memorial slot; Trial clears
unlock their second slots.

Every echo starts as a level-1 Novice and applies its recorded attribute or job
choice automatically at each level, deriving the same stats and loadout in order
rather than restoring the fallen hero's terminal state immediately. Each enemy
reward grants its full XP once to the active hero and every living echo. Past
the end of its record an echo keeps gaining levels, each one pending until the
player chooses its attribute (see Echo Rules); its world label reads
`ECHO 1 · Lv 6*` while a choice is pending.

Echoes use slot-specific follow anchors and deterministic target and
range-aware weapon selection within a leash around the active hero. Vanguard
closes to melee range; Arcanist approaches when out of range and retreats when
an enemy is too close. Mender prioritizes Mend for a friendly at 60% health or
less, retreats from nearby enemies, and limits pursuit to a support leash. An
echo carrying an interrupting weapon prefers a casting enemy within 450 pixels,
switches to that weapon in range, and shows the `interrupt` intent. Manual focus
still wins. Echoes take damage independently; a defeated echo is absent and
stops receiving XP for the remainder of that run without removing its slot
mate.

### Echo Commands

The mouse wheel cycles the command address `All → Echo 1 → Echo 2 → All`,
limited to spawned slots. It returns to `All` after every command and when the
addressed echo falls. Right-click an enemy to focus the addressed echoes; the
purple target ring identifies the selected enemy and shows each focusing echo's
slot. Focus ends when that enemy dies, leaves the active hero's leash, or
regroup is ordered.

`Q` toggles hold position for the addressed echoes: they keep their targets and
attack enemies in weapon range but do not approach or retreat. On `All`, the
command holds everyone unless everyone is already holding, in which case it
releases everyone. `R` clears focus and hold, then moves the addressed echoes
back to their follow anchors before normal tactical behavior resumes. Per-slot
HUD rows expose command, tactical intent, cooldowns, and health. A short world
label (`ECHO 2 · Lv 5`, plus the command when it is not follow) sits higher for
each later slot, and focus-marker digits distinguish the echoes.

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

When the active hero falls, the run ends and the roster screen can open before
the next run. The rules as shipped:

- **Who qualifies.** Only a hero who chose a job (level 3 or later) becomes the
  candidate. A hero that never advanced has no role, is not offered, and a
  one-line notice says so.
- **When the screen opens.** It opens when there is a candidate or the memorial
  holds at least one hero (so swapping stays reachable after a short run).
  Otherwise the next run starts at once. The tree is paused while it is open.
- **Placement is mandatory.** A candidate must be placed or discarded before the
  run can start. Capacity starts at 1 party slot and 1 memorial slot. The first
  Trial clear earns `party_slot_2`; the third total clear earns
  `memorial_slot_2`. An earned slot is usable at the next resolution, never by
  adding an echo to a run in progress.

| Action | Result |
| --- | --- |
| candidate → empty party or memorial slot | joins or is stored |
| candidate → occupied party slot | takes the slot; the occupant goes to the first free memorial slot, else is **lost** |
| candidate → occupied memorial slot | takes it; the occupant is **lost** |
| party ↔ memorial, party ↔ party | swap (party order sets slot numbers) |
| party/memorial → empty slot of the other zone | moves |
| discard candidate | costs one Echo Anchor; roster and memorial unchanged |

A move that loses a hero shows that hero's name and needs a second confirming
press; lost heroes are gone for good. Moves that lose nobody commit at once and
can be undone by moving the heroes again. Refusing a candidate with a discard
needs an Echo Anchor and a second confirming press.

**Echo Anchor.** A run-only preservation item (`anchor`) spent on the roster
screen to discard the fallen hero. Each Trial clear grants one, up to a maximum
of one held. It is saved only as part of an open resolution's `pending` entry;
an unspent Anchor is dropped when the next run begins. Later loot tables may
replace the clear-award source without changing the item rules.

The screen shows each hero as `Hero N · Job · Lv L`, whether the party's jobs
cover the next Trial's needs (`Roster covers: INTERRUPT ✓ Vanguard · AREA ✓
Vanguard · SUSTAIN ✗`), the job the next hero should fill, the Anchor count, and
the next capacity unlock, so a hero can be built for a need the roster lacks.
Memorial heroes are frozen: they do not gain XP, extend their history, or join
runs. M3 caps both zones at two slots; larger parties remain a later readability
question.

**Persistence.** Hero numbering, unlock IDs, per-Trial clear counts, party and
memorial records persist across launches. The save points are death after chosen
extensions are committed and `pending` is set, confirmed resolution with
`pending` cleared, and Trial clear with its unlock award. Reopening with a
pending entry restores that resolution and its Anchor before the first run.
Closing mid-run abandons the run and any unsaved extension choices.

## Progression Layers

Permanent progression should create options rather than simply multiply
damage:

- new echoes and extended build histories;
- party slots up to the M3 cap of two;
- memorial slots up to the M3 cap of two;
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
keys `1` and `2` switch equipped weapons in the prototype.

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
sustain**. Odd hero numbers face Bell Court and even hero numbers face
**Slinger Gallery** (`slinger_gallery`). Rotation uses the persisted hero number
and happens before roster resolution, so its Next Trial line, coverage and job
advice name the next run. Closing and reopening preserves the selection. Either
Trial fires once per run when the active hero reaches level 5 with no level
choice pending. It also fires in run 1 with no echo (decision G5), so the
first hero meets it with only their own job.

- **Warning (3.0 s).** A banner names the Court and its needs. Open-arena
  spawning pauses and the remaining drifters vanish without awarding XP.
- **Active.** Every Court enemy spawns with 1.0 s of spawn grace.
  - At t=0: two Brutes at (-150, -170) and (360, -150), and a Hexcaller at
    (420, 150).
  - At t=4 s: a Skitter pack of four at (-440, 220).
  - At t=12 s: a Skitter pack of four at (460, 230).
  - With **two echoes present at the start**, the Court adds two Hexcallers at
    t=0 at (-330, 250) and (520, -40), plus a Brute at t=8 at (300, 250).
    Every Court enemy has 1.25 times its normal maximum health (Brute 750,
    Hexcaller 175, Skitter 56.25); damage is unchanged. With zero or one echo,
    the original waves and stats are completely unchanged.
  - These centres and the 40-pixel pack jitter stay on-screen and outside the
    HUD panels when the player is at the arena centre.
  - Pack jitter and enemy seeds come from the encounter's own seeded random
    stream (seed 7117), so the Court replays identically.
- **Cleared** when every wave has spawned and no Court enemy is alive. Normal
  spawning resumes. Rewards are kill XP (300, or 530 with the two-echo spawns),
  one Echo Anchor (maximum one held), and any capacity unlock earned by the
  total clear count.
- **Failed** if the active hero is defeated first. The next hero faces the other
  Trial; the failure report still names the fallen hero's Court.

Intended outcomes, from which the Court is tuned:

| Party | Covers | Expectation |
| --- | --- | --- |
| Vanguard + Mender | interrupt, area, sustain | clears; margin may vary by player/echo order |
| Vanguard + Arcanist | interrupt, area | no sustain; fails or clears only thinly |
| Arcanist + Mender | area, sustain | no reliable interrupt; circles land, heals offset some |
| Vanguard + Vanguard | interrupt, area | no sustain; fails or clears only thinly |
| Novice or solo | little or none | usually fails |
| Two-echo parties with Vanguard and Mender | interrupt, area, sustain | two-echo Court clears at echo levels 4 to 7, with tighter margins than a one-echo Court |
| Arcanist + Arcanist + Vanguard | interrupt, area | no sustain; fails or clears only thinly |
| Mender + Arcanist + Arcanist | area, sustain, range | no reliable interrupt; circles land, so it should fail or clear only thinly (the bot still clears at levels 4–5; needs human playtest) |

The Vanguard echo prioritises casters and uses the Lance, so it interrupts
without help. The Arcanist echo does not interrupt, though a player-controlled
Arcanist can break casts with the Wand. The deterministic harness bot is only a
balance proxy; human playtesting remains the exit-condition evidence.

## Trial: The Slinger Gallery

**Slinger Gallery** (`slinger_gallery`) checks **interrupt, area, and range**.
Vanguard + Arcanist covers all three; Vanguard + Mender misses range. It uses
existing enemies and the same level-5 trigger, 3-second warning, 1-second spawn
grace, clear/failure rules and report as Bell Court. Seed **9203** controls enemy
seeds and any pack jitter. Positions below are world coordinates with the hero
at (0, 0); at 1280×720 that maps to screen (640, 360).

| Earliest active time | Enemies and spawn centres |
| --- | --- |
| 0 s | Three Slingers: (360, -30), (540, 120), (-440, 280); two Hexcallers: (-330, 260), (520, 0) |
| 8 s, once at most two enemies survive | Four Skitters: (300, 80), (410, 80), (300, 190), (410, 190) |
| 18 s, once at most two enemies survive | Three Slingers: (-330, 150), (240, 280), (-540, 280); Hexcaller: (540, 270) |

The Skitters form a loose square and converge into a melee pack. Each is an
explicit single spawn, so the catalog's retained **40 px** pack-jitter radius
adds no displacement to this layout. The optional wave `max_alive: 2` gate
prevents delayed groups from stacking into a mob: at most **six** enemies are
alive, including the large-party opening. Times are lower bounds, not forced
reinforcements while the previous group remains intact.

Gallery-only `enemy_overrides` apply before an enemy enters the tree:

| Enemy | Move speed | Flee below | Approach above | Base max HP | Dart damage |
| --- | --- | --- | --- | --- | --- |
| Slinger | 300 px/s | 300 px | 360 px | 45 | 25 |
| Hexcaller | 160 px/s | 250 px | 400 px | 140 (scene default) | — |

These are exported properties applied by stable enemy ID through an explicit
numeric allow-list. Other properties, unknown keys, nonnumeric/negative/nonfinite
values, and nonpositive maximum health are ignored. The open arena and Bell
Court retain their scene speeds (100/85), distances, Slinger damage (14), and
other constants. Gallery Slingers (300 px/s) outrun echoes (220) and the hero
(260) between their unchanged 0.6 s windups; their 300 px flee threshold still
puts them within Sling/Wand/Staff range, so ranged weapons answer them and pure
melee does not. The arena walls remain at x=±900, y=±550; spawn centres start at least
248 px from a wall, but eventual cornering remains possible. No wall AI changed.

With **two echoes present at encounter start**, add one Slinger at t=0 at
**(265, -302)** and multiply every Gallery enemy's maximum health by **1.25**:
Slinger/Skitter **56.25**, Hexcaller **175**. Damage and movement do not scale
further. Zero- and one-echo parties get the base five-enemy opening and health.
All spawn centres, complete potential jitter bounds, bodies and 40 px clearance
fit on screen and clear the supplied HUD panels at the arena centre; Hexcaller
bounds include the break ring and cast bar. All distinct spawn centres,
including later and extra waves, are at least **100 px** apart beyond jitter.
Every ranged spawn is at least **320 px** from centre.

Clearing awards kill XP (**580**, or **630** with two echoes), one Echo Anchor
(maximum one held), and capacity unlocks based on total clears across both
Trials. There are **13** base enemies, or **14** with two echoes. The failure
report keeps the Gallery name when the next hero rotates to Bell Court.

| Party (active hero first) | Intended outcome | Default bot result |
| --- | --- | --- |
| Vanguard + Arcanist | clear | clears thinly at 25.3 s; hero 29 HP, echo lost |
| Arcanist + Vanguard | clear | clears at 24.0 s; hero 120 HP |
| Vanguard + Mender | fail or clear thinly | **miss:** clears at 23.0 s, hero 70 HP (the Mender's Sling is ranged) |
| Mender + Vanguard | fail or clear thinly | **miss:** clears at 25.6 s, hero 95 HP (the Mender's Sling is ranged) |
| Vanguard + Vanguard | fail or clear thinly | fails at 23.3 s |
| Solo Vanguard | fail or clear thinly | fails at 12.9 s |
| Vanguard + Mender + Arcanist | clear | clears at 29.3 s; hero 120 HP |
| Vanguard + Mender + Vanguard | fail or clear thinly | fails at 12.6 s |
| Arcanist + Mender (no interrupt) | may clear, with meaningful pressure | clears at 21.4 s, hero 120 HP; comfortable |
| Idle hero, any tested party | fail | **miss:** five fail; idle parties with a Mender echo, or two echoes, clear |

The coordinator retuned the overrides after Slice 7b (see "Slice 7c" in the M3
plan). Every pure-melee party fails, at echo levels 4, 5 and 7. Every party
with an Arcanist clears, and so does every party with a Mender, because the
Mender's Sling is a ranged weapon even though `range` is not one of the
Mender's capability tags. Whether the Gallery should treat the Sling as a
range answer, or the Mender's tags should change, is an open question for
human playtesting. Rendered readability and roster-swapping playtests remain
pending.

### Telling the player what is needed (decision G4)

Testers must be able to see the need before they choose a job:

- **Trial panel.** A top-centre panel is visible from run start:
  `TRIAL · Bell Court · Lv 5` or `TRIAL · Slinger Gallery · Lv 5`, with chips
  for that Trial's needs (INTERRUPT / AREA / SUSTAIN or INTERRUPT / AREA / RANGE).
  A covered chip reads `✓ NEED` and the covering job; an uncovered chip reads
  `✗ NEED` and `Missing`, so state never relies on colour alone. Coverage uses
  every roster echo's final recorded job in slot order plus the active hero's
  job once chosen. Recorded jobs count from the start of the run, before echoes
  replay their choices, because the panel is for planning the active hero's job. While resolution is
  open, the fallen hero's job does not count toward the next Trial's coverage;
  the roster screen updates its own coverage after each move.
- **Job modal.** At level 3 each job button lists the uncovered needs it fills,
  e.g. `Fills Trial need: SUSTAIN ★`. Every option that fills a need gets the ★.
- **Trial report.** For 10 seconds after a clear, or at the start of the next
  run after a failure, a panel lists casts landed and broken, damage taken per
  enemy (hero and echo totals), healing done, each echo's survival by slot and
  job, and a `Missing: SUSTAIN → Mender provides SUSTAIN` line for each
  uncovered need.

## Open Design Questions

- Do repeated extension modals (up to three per level when both echoes are past
  their records) cause fatigue? If so, move extension choices to the roster
  screen; the domain call is the same.
- What party size remains readable without turning the player into a raid
  manager?
- How much procedural generation helps replayability without weakening
  authored role checks?

## Explicit Non-Goals For The First Milestone

- imitation learning or reinforcement learning;
- a large procedural world;
- persistent equipment;
- more than two echoes at a time;
- advanced job tiers;
- online multiplayer; and
- final art, audio, story, or balance.
