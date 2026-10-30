# Exploration: Commanding Several Echoes

> **Status: exploration only. No decision has been made.** Nothing here changes
> controls or design rules. If a direction is adopted, update
> `docs/game-design.md`, `README.md`, and the roadmap in that same change.

## Problem

With one echo, `RMB` (focus), `R` (regroup), and `Q` (hold/follow) are simple.
M3 adds party slots and "larger parties and formation tools" is later
exploration. The open design question already in `game-design.md` is how much
command authority the active hero has "without turning the player into a raid
manager" (pillar 3: authored history, autonomous action).

## Current Baseline (from code)

- `main.gd` owns a single `echo` and routes `echo_focus` / `echo_regroup` /
  `echo_hold` straight to it. `command_echo_focus_at` picks the nearest enemy
  within `FOCUS_CLICK_RADIUS` of the mouse using deterministic tie-breaks.
- `EchoActor` stores commands as loose fields: `focused_target` (a node ref),
  `is_regrouping`, `is_holding_position`. `get_command_status()` derives one
  label. Regroup is a self-clearing one-shot; hold is a toggle.
- HUD, focus marker, and world label all assume exactly one echo.
- Keys in use: `WASD`, `Space`, `1`/`2`, wheel, `LMB`, `RMB`, `Q`, `R`.
  `game-design.md` leaves skill keys undecided, with "keys surrounding WASD" as
  a candidate. That **collides with `Q`/`R`** and must be resolved before skills.

## Constraints

1. **Real-time and busy hands.** Left hand: movement, dodge, weapon slots, soon
   skills. Right hand: aim and attack. Any command that needs a free hand or
   sustained attention competes with survival. Target budget: a common command
   in under ~300 ms without releasing movement or aim.
2. **Readability.** Pillar 5. The player must see which echo got which order,
   and what it is doing now. Orders must not need a menu to inspect.
3. **Determinism.** Commands are discrete, logged events (tick, address,
   verb, target ID) so a failure replays. Echo iteration order must be stable
   (roster slot), never node or dictionary order. Reference targets by stable
   ID (`stable_spawn_order` exists), not only node refs.
4. **Controller later.** No mouse-click targeting as the only path. Right stick
   aims, so focus must work via aim-cone/nearest-to-aim selection. Button budget
   on a pad is tight: face buttons and triggers are mostly taken by attack, dodge,
   and skills.
5. **Accessibility and remapping.** Named input actions (already used). Avoid
   timing-sensitive chords and holds; offer toggle-vs-hold options; never rely
   on color alone to say who is addressed.
6. **Design intent.** Echoes are mostly autonomous. Commands should *override
   or nudge* policy, not replace it. If the player must micromanage to win, the
   tactical policy and build history stop mattering.

## Command Models

Shared vocabulary: **verbs** are focus, regroup, hold/follow (current), plus
possible later verbs such as retreat, hold-here, and use-skill. **Address** is
who receives it: party, one slot, or a role group.

### A. Party-wide commands only

- **Keyboard/mouse:** today's scheme, unchanged. Every verb applies to all echoes.
- **Controller sketch:** D-pad directions as verbs (up focus, down regroup,
  left/right hold/follow); focus targets the enemy nearest the aim direction.
- **Scales:** 2: fine. 3: acceptable if roles are complementary. 4+: blunt;
  "hold" is wrong for a healer and right for an archer, and the player has no way to
  say so.
- **Cost:** lowest. Loop over a roster array instead of one `echo`; per-echo
  marker/HUD rows. Roughly a day.
- **Risks:** one-size-fits-all overrides make support echoes behave badly;
  players will hold back to avoid this and ignore commands.
- **References:** *Mount & Blade* F1-F3 group orders (works because units are
  fungible); *Diablo*/*Torchlight* pets (no orders at all, the zero-cost floor).

### B. Selection / modifier addressing

- **Keyboard/mouse:** a held modifier chooses the addressed echo, e.g. hold
  `Alt` and tap a number or press `Alt+RMB`. Numbers already pick weapons, so
  the modifier is mandatory. Alternative: `Tab` cycles a persistent "selected
  echo" shown on the HUD (stateful, so ambiguous under stress).
- **Controller sketch:** hold a bumper; face button picks echo 1-4 or the
  right stick flicks to a portrait.
- **Scales:** 2: easy but rarely worth the chord. 3-4: usable but slow; under
  pressure players fall back to party-wide. 4+: becomes an RTS control group
  problem.
- **Cost:** low-medium. Needs an address parameter on every command and HUD
  portraits with slot numbers.
- **Risks:** chords during dodge-heavy combat; selection state errors ("I
  commanded the wrong one"); poor controller ergonomics.
- **References:** *Baldur's Gate*, *Pillars of Eternity* (selection + pause;
  works because of pause, painful in pure real-time); *Dragon Age: Origins*
  (cycle character, pause to order).

### C. Role-addressed commands

- **Keyboard/mouse:** verbs address a role group instead of a slot: e.g.
  `Q` = "front line hold/follow", `R` = regroup everyone, `Shift+RMB` = focus
  by ranged echoes only. Roles derive from job (`vanguard` = front line,
  `arcanist` = ranged). Duplicate jobs resolve by roster slot order.
- **Controller sketch:** D-pad left/right selects group (front/back), a button
  issues the last-used verb; or two bumpers map to the two groups.
- **Scales:** 2: groups of one, so equals B without the chord. 3-4: good:
  few groups (2-3) regardless of party size. 4+: scales by role count, not echo
  count, matching the "interdependence" fantasy.
- **Cost:** medium. Needs a role taxonomy per job (data-driven, stable IDs),
  and a rule for Novices (no role until level 3).
- **Risks:** teaches an extra taxonomy; fails when two echoes of one role want
  different orders; role changes with job tiers later.
- **References:** *Mount & Blade* formation classes (infantry/archers/cavalry);
  *Dragon's Dogma* pawn vocations make the same orders mean different things.
  *FFXIV* trust NPCs avoid this entirely by not taking commands.

### D. Radial wheel with optional slow-time

- **Keyboard/mouse:** hold a key (e.g. `Tab`) to open a wheel; flick toward a
  wedge for address + verb, release to commit. Optionally scale game time to
  ~10-25% while open, or fully pause (`get_tree().paused` is already used for
  the level-up modal).
- **Controller sketch:** hold a trigger or bumper; right stick selects wedge;
  the best-supported model on pads (*Mass Effect* style).
- **Scales:** 2-4: excellent. 4+: wheels need nesting (address then verb).
  More expressive orders (retreat, use skill X) fit here later.
- **Cost:** highest of the "live" options: wheel UI, input capture that frees
  the mouse from aiming while open, time-scale handling, and tests that
  deterministic sim runs through it. Roughly 3-5 days with polish.
- **Risks:** breaks the flow it is meant to protect (stopping time repeatedly
  makes combat feel turn-based); slow-time can undermine the dodge and
  positioning that are the core skill. Players may spam it as a crutch.
- **References:** *Mass Effect 1-3* (power wheel with time slow; praised on
  controller); *Dragon Age: Inquisition* tactical camera (clunky, rarely used
  after early game); *Baldur's Gate 3* is turn-based, so not comparable.

### E. Per-echo standing orders (gambits), set between fights

- **Keyboard/mouse:** orders live in a roster/pre-run screen: per echo, a
  small ordered list of rules ("Hold ground if Vanguard is adjacent to the
  hero", "Heal hero below 50%", "Prioritize marked enemies"). Mid-combat input is
  limited to optional party-wide overrides (`R` regroup, one stance toggle).
- **Controller sketch:** menu only; in-combat reuses model A's D-pad.
- **Scales:** 2-4+: scales best because combat cost is zero per echo.
  Complexity moves into UI and AI authoring.
- **Cost:** high up front (condition/action data model, editor UI, inspection
  of why an echo acted) but aligns with `game-design.md`: "tactical behavior
  should be inspectable and adjustable through a small set of priorities".
  Deterministic by construction: rules are ordered, data-driven, and ID-based.
- **Risks:** pre-fight setup is slow and can be tuned to death; rules cannot
  react to surprises the player sees; shifts fun from action to spreadsheet if
  the rule count grows. Needs a hard cap (3-4 rules).
- **References:** *Final Fantasy XII* gambits (loved by systems players, but
  often cited as playing itself); *Dragon Age: Origins* tactics slots (good
  with limited slots, tedious when unlimited); *Dragon's Dogma* pawn
  inclinations (a few dials, readable).

### F. Contextual ping (single button)

- **Keyboard/mouse:** one command key or `MMB` "pings" what is under the cursor.
  Enemy: focus. Empty ground: move/hold there. Echo: regroup it. Ping again on the
  same thing to cancel. `RMB` focus is effectively a partial version of this today.
- **Controller sketch:** one button/bumper; target is nearest to the right-stick
  aim, with soft magnetism; hold for regroup.
- **Scales:** 2: great. 3-4: good if orders default to the whole party, with a
  modifier to narrow. 4+: needs a grouping model (A or C) beneath it.
- **Cost:** medium. Needs ground-position hold, a context-resolution rule, and
  clear feedback for what the ping resolved to.
- **Risks:** wrong-context resolution ("I wanted regroup, I got focus");
  ground-targeting needs the cursor, which also aims.
- **References:** *Dragon's Dogma* (`Go` / `Come` / `Help`: three-button,
  liked, but only ~1-3 pawns); *Apex Legends* ping (very readable, but human
  allies); *Pikmin* (cursor-throw, gets hectic at scale).

### Cross-cutting: formation presets

Not a standalone model; a layer on A, C, or E. A key cycles tight / spread /
front-heavy offsets from the active hero. Good for readability (visible geometry)
and cheap, but offsets compete with each echo's own tactical policy (e.g. the
Arcanist retreat) unless presets only set the follow anchor. Defer beyond 2 echoes.

## Comparison

Scores are relative judgements, not measurements.

| Model | Combat-flow cost | 2 echoes | 3-4 echoes | 4+ | Controller | Impl. cost | Determinism / logging |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A Party-wide | Very low | Good | OK | Poor | Easy | Low | Trivial |
| B Modifier select | High (chord) | Overkill | OK | Poor | Awkward | Low-med | Easy, needs addr. |
| C Role-addressed | Low | = B, fewer keys | Good | Good | OK | Medium | Easy, stable roles |
| D Wheel / slow-time | Medium (time stop) | Good | Good | OK (nested) | Best | High | Needs time-scale care |
| E Standing orders | Zero in combat | OK (setup) | Good | Best | Menu only | High | Best (data-driven) |
| F Contextual ping | Very low | Good | OK | Needs A/C | Good | Medium | Easy, ID-based |

## Recommendation (provisional, for discussion)

Combine the cheap live layer with the scalable autonomous layer, and keep
the expensive live layer in reserve:

1. **M2 (one echo, now):** no new player-facing commands. Refactor so command
   state is per echo and addressed (see "Avoid in M2"). Fix the `Q`/`R` vs
   skill-key collision decision. Keep `RMB` focus as the seed of model F.
2. **M3 (two echoes):** **A + F + the first slice of E.**
   - Party-wide `R` regroup and `Q` stance, `RMB` focus applies to both.
   - Each echo gets one **default stance** (follow/hold) and optionally one
     priority dial chosen on the roster screen, a tiny version of E that
     respects "readable, inspectable" and costs nothing in combat.
   - One narrowing modifier on `RMB`/`Q` (e.g. `Shift` = nearest echo only,
     `Alt` = other one) only if playtests show party-wide is insufficient.
3. **Defer (3+ echoes, roughly M4+):** C (role groups) as the in-combat
   addressing layer once the party has distinct roles, and D (wheel) only if
   playtests show real need, with *pause* preferred over slow-time first.
   Formation presets last.
4. **Do not build** full B-style per-echo selection as the primary system, or
   unlimited gambit lists.

Rationale: with two echoes the party-wide model is mostly right, and
standing orders fix the cases where it is wrong without taxing the player's hands.
Role addressing is the most natural scaling path because jobs already exist as
stable IDs and the game's identity is complementary roles.

### User direction to evaluate (2026-10-30)

The user proposed reusing the **mouse wheel** for echo addressing. Today the
wheel cycles weapon slots, but that only exists to test the per-job weapon
pairs and is not expected to remain a combat control. Weapon slots would stay
on `1` / `2`.

This is a cheap form of model B. The wheel cycles a persistent addressed target
(`All`, then each echo by roster slot), and `RMB` focus, `Q` stance, and `R`
regroup apply to that target. It suits this control scheme better than a
modifier chord: the wheel sits under the aiming hand, takes no extra key, and
leaves the movement hand alone. To manage the stateful-selection risk:

- Default to `All` and show the addressed echo clearly on both the HUD and the
  echo itself, using shape or text as well as color.
- Consider snapping back to `All` after a command or a short timeout.
  Prototype experiment 7 tests this.
- Plan a controller equivalent, such as a bumper cycling the same list.

Adopting this changes a current control, so the change that adopts it must
update `README.md` controls and `docs/game-design.md`. It does not need to be
built while there is only one echo. The M2 hygiene below (per-echo addressed
orders) keeps it cheap to add later.

## What M2 Work Should Avoid (and Prefer)

- **Do not** add more per-echo bool flags on `EchoActor`. Replace
  `is_regrouping` / `is_holding_position` / `focused_target` with a small
  `EchoOrders` object (stance enum, optional focus target ID, regroup request,
  later: policy ID). One owner, serializable, loggable.
- **Do** make `main.gd` hold `echoes: Array[EchoActor]` ordered by roster slot,
  even while length is 0 or 1, and route commands through a `PartyCommander`
  taking `(address, verb, payload)`; address is party today, slot/role later.
  Do not hardcode `echo` in input handling.
- **Do** rename or alias input actions toward neutral names (`party_regroup`,
  `party_hold`, `party_focus`) before they leak into saved keybindings, and
  keep modifier actions (`command_modifier_a`) reserved.
- **Do** reference focus targets by stable ID plus lookup, so command logs and
  replay tests do not depend on node identity.
- **Do** keep the click-to-target selection logic in one reusable function
  with an aim-direction variant (stick-aimed focus later) instead of baking the
  mouse position into `command_echo_focus_at`.
- **Do** make HUD and the focus marker per-echo (row/tint/glyph per slot);
  address must be shown with shape or text, not color alone.
- **Avoid** self-clearing orders that mutate inside physics code with
  side effects; make expiry rules explicit (focus ends on death, leash, regroup).
- **Avoid** settling on `Q`/`R` for good. Treat them as placeholders until skill
  keys are chosen.
- **Avoid** pause/time-scale code paths that assume only the level-up modal
  pauses; a command wheel would need its own owner.

## Cheap Prototype Experiments

Each can be a throwaway branch or debug flag; none needs final UI. Log commands
(tick, address, verb, target ID) and outcome (died, damage taken) in all of them.

1. **Two-echo party-wide baseline.** Spawn two echoes (Vanguard + Arcanist) from
   debug records, current controls. Measure command rate and deaths.
   *Questions:* Do players use `R`/`Q` more or less than with one? Do they ask
   to address one echo? Which echo do they say they wish they could order?
2. **Narrowing modifier.** Add `Shift+RMB` / `Shift+Q` for "other echo".
   *Questions:* Does anyone discover it unprompted? Does a wrong-echo mistake
   happen? Does movement or dodge quality drop while holding it?
3. **Default stance per echo.** Pre-run toggle (hold / follow) on each echo, plus
   `R` only in combat. *Questions:* Does it replace mid-combat `Q`? Do players
   set it once, or fiddle every run? Do they trust echoes more or less?
4. **Pause-wheel Wizard of Oz.** A hold-key menu that pauses the tree and shows
   four wedges. *Questions:* How often is it opened? Does opening it feel like
   a flow break or a relief? Does combat difficulty collapse? Compare 100%
   pause against 20% slow-time.
5. **Ping-only focus.** Remove stance keys, keep one ping button that resolves
   enemy/ground/echo. *Questions:* Is the resolution predictable? Do players
   misfire? Is aim-based selection (no mouse position) good enough to simulate a
   controller?
6. **Fake 4-echo stress test.** Four scripted dummy echoes, party-wide
   commands only. *Questions:* Is party-wide still tolerable? At what
   count do players stop caring about the state of any individual echo?
   Is the HUD readable?

7. **Wheel addressing.** With two echoes, the wheel cycles `All` / echo 1 /
   echo 2, and weapon cycling leaves the wheel. Try sticky selection against
   snapping back to `All` after each command. *Questions:* Do players notice
   which echo they are addressing? How often does a wrong-echo order happen,
   compared with experiment 2? Does wheel use interfere with aiming?

**Decision gates to look for:** if players issue under ~1 command per fight with
two echoes, the commands are not the bottleneck and standing orders are enough;
if wrong-target orders are common, prefer role groups over slot selection; if
players beg for a wheel, test pause before slow-time.
