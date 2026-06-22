# Graphics assets — how to swap art

This game loads **sprite sheets** for characters/monsters and **single images**
for objects. Everything is wired through one config block in
[`lib/main.dart`](../lib/main.dart) (search for `GRAPHICS CONFIG`), so re-theming
is: **drop a PNG → update two numbers**.

> ⚠️ The Diablo II sprites originally used here are © Blizzard Entertainment and
> are **gitignored** (not shipped). This repo contains only the folder structure
> and these docs. With no images present the game runs on built-in **vector art**.
> Add your own / open-licensed art to get a sprite look. See `COPYRIGHT_NOTICE.txt`.

## Folder layout

```
assets/
├── characters/
│   ├── hero/       idle.png  walk.png  attack.png            (player)
│   ├── skeleton/   idle.png  walk.png  attack.png  death.png (monster 1)
│   ├── fallen/     idle.png  walk.png  attack.png  death.png (monster 2)
│   └── imp/        idle.png  walk.png  attack.png  death.png (monster 3)
└── objects/
    ├── barrel.png   destructible barrel (single image)
    ├── coins.png    gold drop (single image)
    └── potions.png  potion drop (row of icons; 1st=health, 2nd=mana)
```

## Sprite-sheet format

A character sheet is a **grid**:

```
        frames (columns) →
      ┌────┬────┬────┬────┐
dirs  │ d0 │ d0 │ d0 │ d0 │   row 0 = facing direction 0
(rows)├────┼────┼────┼────┤
  ↓   │ d1 │ d1 │ d1 │ d1 │   row 1 = facing direction 1
      └────┴────┴────┴────┘   ... one row per direction
```

- **rows = facing directions** (`dirs`): use **8** or **16**.
- **columns = animation frames** (`frames`): the walk/attack cycle length.
- `frameWidth  = imageWidth  / frames`
- `frameHeight = imageHeight / dirs`
- The renderer anchors each frame by its feet, picks the row from the entity's
  facing, and cycles columns over time.
- A still image (object, or a 1-frame death) is just `frames = 1`, `dirs = 1`.

## To swap a character's art

1. Replace e.g. `assets/characters/hero/walk.png` with your sheet.
2. In `lib/main.dart`, find the config and set the right numbers:

```dart
const kHeroCfg = CharCfg(
  'assets/characters/hero', 16, 0.5,        // folder, dirs, on-screen scale
  AnimCfg('idle.png', 8),                    // 8 frames
  AnimCfg('walk.png', 8),                    // 8 frames
  AnimCfg('attack.png', 9),                  // 9 frames
);
```

   - `dirs`  → rows in your sheet (8 or 16)
   - the second arg of each `AnimCfg` → columns (frames) in that sheet
   - `scale` → bigger/smaller on screen

3. `flutter run`. That's it — no other code changes.

## To swap an object

Replace `assets/objects/barrel.png` (etc.) and keep it a single image. Paths are
the `kBarrelPath` / `kCoinsPath` / `kPotionsPath` consts in `lib/main.dart`.

## Tip: finding a sheet's frame/row counts

If you don't know your sheet's grid, open it and count cells, or read its pixel
size and divide. Frame layout must be uniform (every cell the same size).
