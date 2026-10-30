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

When coordinating from T3 Code, delegate the visual-worker playtest role to the
Codex provider's `gpt-6-luna` model. It is the current fast, low-cost option for
Godot test loops there; the Fireworks model assignments are OpenCode-specific
and are not assumed to be available through T3.

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
