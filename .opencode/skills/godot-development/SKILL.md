---
name: godot-development
description: Use when editing Godot scenes, GDScript, resources, input actions, collision, simulation, or project.godot in Echo Party.
---

# Godot Development

## Before Editing

1. Read `AGENTS.md` and the relevant files under `docs/`.
2. Inspect the scene and every attached script involved in the behavior.
3. Decide whether the change is domain/simulation behavior or presentation.
4. Preserve current controls and collision layers unless the task explicitly
   changes them.

## Implementation

- Target Godot 4.7 and use current APIs.
- Prefer typed GDScript where it improves editor diagnostics.
- Use signals for meaningful cross-node events rather than fragile parent-path
  calls.
- Keep tunable gameplay values named and colocated with the behavior they tune.
- Give random simulation decisions a seeded `RandomNumberGenerator` when they
  must be reproducible.
- Avoid editing text scenes through broad substitutions. Verify node paths,
  resource IDs, collision layers, and signal connections after scene changes.
- Keep permanent records independent of scene paths and translated names.

## Validation

Run parser/import validation after GDScript or scene edits:

```bash
godot --headless --editor --path . --quit
```

Run the gameplay smoke test before completion:

```bash
godot --headless --path . --quit-after 600
git diff --check
```

Use the `godot-playtest` skill when correctness depends on rendered output,
input, animation, timing, camera behavior, or gameplay feel.
