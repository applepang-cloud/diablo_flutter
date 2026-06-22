# Diablo Flutter

An isometric action-RPG built in **Flutter** with `CustomPaint`, inspired by
[mitallast/diablo-js](https://github.com/mitallast/diablo-js) (an HTML5 Diablo II
clone). A learning project for isometric rendering, A\* pathfinding, and sprite
animation.

🎮 **Play (vector build):** https://applepang-cloud.github.io/diablo_flutter/

## Features

- Procedurally generated isometric dungeons (rooms + corridors, multi-floor)
- Click-to-move with **A\*** pathfinding + 5×5 sub-tile collision (wall sliding)
- Three monster types with chase AI, plus melee combat and a **fireball** spell
- Diablo-style combat: 120 base damage, 40% crit, per-monster resistance
- Health/mana orbs, XP/levels, gold, **potion belt** (number keys), looting
- Destructible barrels, wall torches, cursor highlight, Tab minimap
- **Swappable graphics**: drop in sprite sheets, or run on built-in vector art

## Controls

| Input | Action |
|-------|--------|
| Left click | Move / attack |
| `F` or right click | Cast fireball |
| `1` `2` | Drink health potion |
| `3` `4` / `E` | Drink mana potion |
| `Tab` | Toggle minimap |

## Run locally

```bash
flutter pub get
flutter run -d chrome     # or: -d windows
```

## Graphics — vector vs sprites

This repo ships **no image assets** and runs on original vector art. To get a
sprite look, drop sprite sheets into `assets/` and update the config — see
**[assets/README.md](assets/README.md)** for the full, two-step swap guide.

> ### ⚠️ About the original Diablo II sprites
> The reference project's sprites are extracted from **Diablo II (© Blizzard
> Entertainment)**. They are **not** included here — they're gitignored and used
> only for *local, personal study*. As a safeguard, a release build that bundles
> those copyrighted images **refuses to run** (`distributionBlocked()` in
> `lib/main.dart`); the public Pages build uses only the legal vector fallback.
> Use your own or open-licensed (CC0) art for anything you intend to distribute.

## Tests

```bash
flutter test
```

Covers boot/HUD, dungeon generation, the game loop, end-to-end melee combat,
sprite-sheet geometry, resistance math, and A\* pathfinding.

## Tech notes

- Single-file game in [`lib/main.dart`](lib/main.dart).
- Isometric projection: `screenX ∝ (x−y)`, `screenY ∝ (x+y)/2`; entities depth-
  sorted by `x+y`.
- Sprite direction mapping ported from the original `diablo.js`.
