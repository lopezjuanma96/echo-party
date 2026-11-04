---
name: pixel-art-pipeline
description: Use when creating, importing, animating, licensing, or reviewing pixel-art sprites, tilesets, palettes, and 2D game assets for Echo Party.
---

# Pixel Art Pipeline

## Default Workflow

1. Define canvas size, pivot, baseline, palette, outline rules, directions, and
   animation names before drawing variants.
2. Prove one readable idle silhouette at actual game scale before producing a
   full sheet.
3. Prefer Pixelorama for editable source (`.pxo`) and export transparent PNG
   frames or a uniform spritesheet.
4. Keep editable source under `assets/` with its exports.
5. Import with lossless compression, nearest-neighbor filtering, and no mipmaps
   unless a tested zoomed-out use case requires them.
6. Build `SpriteFrames` or `TileSet` resources in Godot and verify pivots,
   frame dimensions, animation names, and loop timing.
7. Test silhouettes and attacks against the actual arena background, not only
   in the art editor.

## Agent-Generated Assets

- Start with the Luna `visual-worker` for inexpensive variants and screenshot
  checks.
- Use procedural or hand-authored placeholder shapes before cloud generation.
- Pixelorama MCP and Blender MCP are not installed. They permit executable
  addon code and remain opt-in experiments requiring a fresh source audit,
  pinned version, throwaway branch, and user approval.
- Blender is useful only when consistent orthographic renders from a low-poly
  model beat direct 2D work. It is not the default sprite pipeline.
- Do not use generic diffusion output as production pixel art without manual
  palette, silhouette, edge, and animation cleanup.

## Licensing

- Confirm that the asset and source model permit redistribution and commercial
  game use.
- Record creator, source URL, exact license, and modifications in
  `assets/third_party/THIRD_PARTY_ASSETS.md`.
- Never import an asset whose license is unclear.
