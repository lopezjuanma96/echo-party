# AI Development Environment

Echo Party uses project-local OpenCode configuration so agent behavior and
tooling evolve with the repository. Restart OpenCode after changing
`opencode.json`, an agent, a skill, or the Godot MCP addon.

## Agents

| Agent | Model | Role |
| --- | --- | --- |
| `fast-implementer` | DeepSeek V4.1 Flash | Routine bounded edits |
| `engineer` | GPT-5.6 Sol | Normal feature work |
| `hard-problem` | GPT-5.6 Sol, high | Security and final escalation |
| `reviewer` | GLM-5.3, high | Independent read-only review |
| `visual-worker` | GPT-5.6 Luna, high | Low-cost visual iteration and playtesting |
| `level-designer` | Kimi K3, high | Expensive advanced encounter design |

These assignments are experiments, not permanent architecture. The coordinator
should change a model when repeated results justify it. Qwen3.8 Max is the
first alternative to trial for advanced visual or level work.

The Fireworks model assignments are OpenCode-specific and are not assumed to be
available through T3 Code.

## T3 Code Orchestration

When a session runs in T3 Code, the coordinator delegates roles with T3's
`delegate_task` instead of OpenCode agents. Delegated children start without
the coordinator's conversation history, so every prompt must say which files
to read, what may be edited, and what to report.

| Role | T3 provider / model | Options | Responsibilities |
| --- | --- | --- | --- |
| Coordinator | `claudeAgent` / `claude-opus-5-5` | session default | Scoping, integration, review, validation, docs, user decisions |
| Designer | `claudeAgent` / `claude-sonnet-5-5` | `effort: high` | Ideas, design specs, implementation slices, explorations |
| Implementer | `acpRegistry_kimi_cli` / `kimi-code/k3.1-pro` | `thinking: high`, `mode: auto` | Dense GDScript, scenes, and headless tests |
| Playtester | `codex` / `gpt-6-luna` | `reasoningEffort: medium` | Godot MCP runtime checks and selective screenshots |

Notes:

- Kimi's `mode: auto` is Kimi CLI's "Never Ask" mode. Without it the child
  can stop and wait for approvals that nobody in the parent thread can grant.
  The Kimi K3.1 subscription is cancelled and lasts until about 2026-11-30.
  After that, give the implementer role to `claude-sonnet-5-5` or
  `codex` / `gpt-6.1-sol`.
- Codex reads the project-local `.codex/config.toml`, which exposes only the
  restricted Godot MCP tool allowlist and disables `godot_exec`. The project
  must be trusted in `~/.codex/config.toml` for that file to load.
- Children do not discover `.opencode/skills/` automatically. Name skill files
  in the prompt, for example `.opencode/skills/godot-development/SKILL.md` for
  implementers and `.opencode/skills/godot-playtest/SKILL.md` for the
  playtester.
- All children share the main checkout unless `isolation: worktree` is used.
  Run only one editing child at a time. Read-only design or test children may
  run alongside it if they stay out of the files being edited.
- The playtester needs the Godot editor open with the MCP plugin listening on
  `127.0.0.1:6550`. An agent shell may lack display variables. If launching the
  editor from there, pass the user's session values, for example
  `WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 setsid nohup godot --editor --path . &`.
  Detach it like this, because harness background commands are killed at
  their time limit.
- In the first probe, a 2-second `godot_game_time` step timed out while the
  game was running. Use shorter steps, and confirm elapsed time from runtime
  state rather than from the call returning. Runtime digests truncate large
  node sets, so actors worth observing should expose `_mcp_state()`.
- An open Godot editor keeps its own copy of each open scene. If agents edit
  that `.tscn` on disk and the editor then saves, on run, Ctrl+S, or "save
  before closing", the stale copy overwrites their work. This wiped the
  Slice 4–5 HUD from `src/main/main.tscn`; it was rebuilt from agent
  transcripts. Restart the editor, or reload changed scenes, before saving
  anything in it while agents are editing scenes. Checkpoint the working tree
  after every verified slice: a commit when the user allows it, otherwise an
  archive outside the repo.
- The bridge accepts one client. The Codex app-server can leave a
  `godot-mcp` process from a finished playtest connected, and the next run is
  then rejected with "another client is already connected". Before each
  playtest, check `ss -tnp | grep 6550`. Stop leftover `godot-mcp` processes
  only once their playtest task has finished.
- Kimi's plan has a rolling 5-hour usage quota. Through T3's ACP bridge,
  hitting it never surfaces an error. The task "completes" empty within
  seconds, or mid-task with a progress sentence as its summary. When a Kimi
  task ends early or empty:
  1. Run `kimi -p "Reply with exactly: ok" -m kimi-code/k3.1-pro`. A 429
     there means the quota is spent.
  2. Check `git status` and run the tests.
  3. Then either move the slice to the fallback implementer or send a
     continuation task that lists what is missing and requires a final
     report.
- `gpt-6-luna` tends to stop after the first step when a plan needs long
  manual steering, such as walking into enemies to take damage. Give it
  deterministic starting states through scenario scene exports, such as
  `player_health_fraction` in `tests/scenarios/scenario_launcher.gd`. Verify
  the logic headlessly first, and limit the playtest to real input, rendered
  output, and HUD fit. State in the prompt that every step must be attempted.
  Use `reasoningEffort: high`.
- In T3, Codex receives MCP `screenshot_game` images as base64 text that
  `gpt-6-luna` cannot view. Scenario scenes register a scenario-only
  `playtest_capture` action (F12). Sending it through `godot_input` saves the
  rendered frame to
  `~/.local/share/godot/app_userdata/Echo Party/playtest_captures/`. The game
  prints the path, and the PNG can be opened from disk. Use
  `enemy_population = 0` on a scenario for isolated checks, so incidental kills
  cannot open the level-up modal.
- The MCP serializer silently drops `StringName`, `Vector2`, `NodePath`, and
  `Object` values in `_mcp_state()`. Return plain `String`s, numbers, bools,
  arrays, and dictionaries, for example `String(job_id)`, `pos_x`/`pos_y`,
  and node names as `String`.

Loop for each feature slice:

1. The designer produces or refines a spec with acceptance criteria, headless
   test ideas, and MCP playtest questions.
2. The coordinator approves the slice, escalating product decisions to the
   user and updating `docs/` when a decision changes.
3. The implementer builds the slice with headless tests, then runs the
   validation commands from `AGENTS.md`.
4. The coordinator reviews the diff and reruns the validation.
5. The playtester answers the slice's runtime questions through the MCP.
6. The coordinator sends concrete findings back to the implementer as a new
   task containing the original brief and the findings. After two failed
   correction rounds, change the model or take over.

## Godot MCP

The repository pins
[`@satelliteoflove/godot-mcp`](https://github.com/satelliteoflove/godot-mcp)
at `4.1.11`. It supplies screenshots, runtime state, input injection,
deterministic time stepping, editor logs, and profiler data through a Godot
editor addon.

The package and addon were selected because they are MIT licensed, source
available, versioned, tested, require only a localhost WebSocket by default,
and separate read/write tools. Version `4.1.11` was inspected before
installation. Its npm integrity at installation time was:

```text
sha512-XYAPURo4Yyw7eOijZ15fyrf21hbFi+Dw+lO2xELvPQ1F2QBo6ZiZKzQQw9yF5jruiIJ4fnP5sPdt0lpKHQQedw==
```

The MCP remains powerful local code. Project policy therefore:

- pins the npm package instead of following `latest`;
- disables its local usage log;
- denies all Godot tools to agents by default;
- grants a restricted allowlist only to `visual-worker`;
- denies `godot_exec` explicitly (OpenCode exposes it as
  `godot_godot_exec` because MCP tools receive their server-name prefix);
- keeps the addon bound to `127.0.0.1`; and
- favors reviewable file edits and structured state over editor mutation and
  screenshots.

To use it, open the project in Godot and confirm **Project > Project Settings >
Plugins > Godot MCP** is enabled. Then restart OpenCode so it loads the local
MCP process. A Godot editor permits only one bridge client at a time.

## Asset Tooling

The default free 2D editor recommendation is
[`Pixelorama`](https://github.com/Orama-Interactive/Pixelorama), an MIT-licensed
pixel-art editor built with Godot. It is not installed automatically because
the repository does not need a system-wide application or experimental asset
MCP to run.

Potential future trials:

- [Pixelorama-MCP](https://github.com/abidoo22/Pixelorama-MCP) for deterministic
  pixel operations and Godot exports. It is young and should be audited again.
- [pixel-mcp](https://github.com/willibrandon/pixel-mcp) for an Aseprite-based
  workflow. Aseprite binaries are paid and source-available rather than open
  source.
- [MCP for Blender](https://github.com/ahujasid/mcp-for-blender) only for work
  that genuinely benefits from 3D-to-2D orthographic rendering. Its arbitrary
  Blender Python execution makes it a high-trust tool.

Pinokio is an application launcher, not a Blender or sprite MCP. Its community
install scripts execute arbitrary commands, so it is not part of this setup.

## Updating Tools

Before updating the Godot MCP or adding an asset tool:

1. Check repository ownership, recent maintenance, license, release tag, and
   package provenance.
2. Inspect install scripts, network access, filesystem writes, arbitrary-code
   facilities, and dependency lockfiles.
3. Pin the exact version or commit and record its integrity when available.
4. Trial it on a throwaway branch with the narrowest permissions.
5. Verify OpenCode config with `opencode agent list` and `opencode mcp list`.
