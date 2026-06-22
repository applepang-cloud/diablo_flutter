import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DiabloApp());

// === DISTRIBUTION LOCK ===
// The Diablo II sprites under assets/ are © Blizzard and must NOT be shipped.
// A *release/profile* build that actually bundles those sprites is blocked at
// runtime (see GameScreen). A build WITHOUT them (the published repo / Pages
// version, which falls back to original vector art) is legal and runs freely.
// Debug builds always run so you can develop locally with the sprites.
bool distributionBlocked(bool spritesPresent) => spritesPresent && !kDebugMode;

class _BlockedApp extends StatelessWidget {
  const _BlockedApp();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF120607),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.lock, color: Color(0xFFBB3333), size: 64),
              SizedBox(height: 16),
              Text('학습 전용 빌드 · 배포 불가',
                  style: TextStyle(
                      color: Color(0xFFBB3333),
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text(
                  '이 빌드는 디아블로 II 스프라이트(© Blizzard)를 포함하고 있어\n'
                  '릴리스/프로파일 빌드에서는 실행할 수 없습니다(배포 방지).\n'
                  '디버그 모드(flutter run)에서만 플레이하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

class DiabloApp extends StatelessWidget {
  const DiabloApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diablo Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const GameScreen(),
    );
  }
}

// ============================================================ Tile / Map

enum Tile { empty, floor, wall }

class Dungeon {
  final int w, h;
  late List<List<Tile>> grid;
  final List<math.Rectangle<int>> rooms = [];
  final math.Random rng;

  Dungeon(this.w, this.h, this.rng) {
    grid = List.generate(h, (_) => List.filled(w, Tile.empty));
    _generate();
  }

  Tile at(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return Tile.empty;
    return grid[y][x];
  }

  bool walkable(int x, int y) => at(x, y) == Tile.floor;

  void _carveRoom(math.Rectangle<int> r) {
    for (int y = r.top; y < r.bottom; y++) {
      for (int x = r.left; x < r.right; x++) {
        grid[y][x] = Tile.floor;
      }
    }
  }

  void _carveH(int x1, int x2, int y) {
    for (int x = math.min(x1, x2); x <= math.max(x1, x2); x++) {
      grid[y][x] = Tile.floor;
    }
  }

  void _carveV(int y1, int y2, int x) {
    for (int y = math.min(y1, y2); y <= math.max(y1, y2); y++) {
      grid[y][x] = Tile.floor;
    }
  }

  void _generate() {
    const attempts = 60;
    for (int i = 0; i < attempts; i++) {
      final rw = 4 + rng.nextInt(7);
      final rh = 4 + rng.nextInt(7);
      final rx = 1 + rng.nextInt(w - rw - 2);
      final ry = 1 + rng.nextInt(h - rh - 2);
      bool overlap = false;
      for (final o in rooms) {
        if (rx - 1 < o.left + o.width &&
            rx + rw + 1 > o.left &&
            ry - 1 < o.top + o.height &&
            ry + rh + 1 > o.top) {
          overlap = true;
          break;
        }
      }
      if (overlap) continue;
      final room = math.Rectangle(rx, ry, rw, rh);
      _carveRoom(room);
      if (rooms.isNotEmpty) {
        final prev = rooms.last;
        final px = prev.left + prev.width ~/ 2;
        final py = prev.top + prev.height ~/ 2;
        final cx = rx + rw ~/ 2;
        final cy = ry + rh ~/ 2;
        if (rng.nextBool()) {
          _carveH(px, cx, py);
          _carveV(py, cy, cx);
        } else {
          _carveV(py, cy, px);
          _carveH(px, cx, cy);
        }
      }
      rooms.add(room);
    }
    // walls around floors
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (grid[y][x] == Tile.floor) continue;
        bool nearFloor = false;
        for (int dy = -1; dy <= 1 && !nearFloor; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (at(x + dx, y + dy) == Tile.floor) {
              nearFloor = true;
              break;
            }
          }
        }
        if (nearFloor) grid[y][x] = Tile.wall;
      }
    }
  }
}

// ============================================================ Pathfinding

class Point {
  final int x, y;
  const Point(this.x, this.y);
}

class _Node {
  final int x, y;
  final double g, f;
  final _Node? parent;
  _Node(this.x, this.y, this.g, this.f, this.parent);
}

List<Point> findPath(Dungeon d, Point start, Point goal) {
  if (!d.walkable(goal.x, goal.y)) return [];
  final closed = <int>{};
  final best = <int, double>{};
  int key(int x, int y) => y * d.w + x;
  final pq = PriorityQueue<_Node>((a, b) => a.f.compareTo(b.f));
  pq.add(_Node(start.x, start.y, 0, _h(start.x, start.y, goal.x, goal.y), null));
  const dirs = [
    [1, 0], [-1, 0], [0, 1], [0, -1],
    [1, 1], [1, -1], [-1, 1], [-1, -1]
  ];
  int guard = 0;
  while (pq.isNotEmpty && guard++ < 30000) {
    final cur = pq.removeFirst();
    final ck = key(cur.x, cur.y);
    if (closed.contains(ck)) continue;
    closed.add(ck);
    if (cur.x == goal.x && cur.y == goal.y) {
      final path = <Point>[];
      _Node? n = cur;
      while (n != null) {
        path.add(Point(n.x, n.y));
        n = n.parent;
      }
      return path.reversed.toList();
    }
    for (final dir in dirs) {
      final nx = cur.x + dir[0], ny = cur.y + dir[1];
      if (!d.walkable(nx, ny)) continue;
      if (dir[0] != 0 && dir[1] != 0) {
        if (!d.walkable(cur.x + dir[0], cur.y) ||
            !d.walkable(cur.x, cur.y + dir[1])) continue;
      }
      final nk = key(nx, ny);
      if (closed.contains(nk)) continue;
      final step = (dir[0] != 0 && dir[1] != 0) ? 1.414 : 1.0;
      final ng = cur.g + step;
      final prev = best[nk];
      if (prev == null || ng < prev) {
        best[nk] = ng;
        pq.add(_Node(nx, ny, ng, ng + _h(nx, ny, goal.x, goal.y), cur));
      }
    }
  }
  return [];
}

double _h(int x, int y, int gx, int gy) {
  final dx = (x - gx).abs(), dy = (y - gy).abs();
  return (dx + dy) + (1.414 - 2) * math.min(dx, dy);
}

class PriorityQueue<T> {
  final List<T> _heap = [];
  final int Function(T, T) cmp;
  PriorityQueue(this.cmp);
  bool get isNotEmpty => _heap.isNotEmpty;
  void add(T v) {
    _heap.add(v);
    int i = _heap.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (cmp(_heap[i], _heap[p]) < 0) {
        final t = _heap[i];
        _heap[i] = _heap[p];
        _heap[p] = t;
        i = p;
      } else {
        break;
      }
    }
  }

  T removeFirst() {
    final top = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      int i = 0;
      final n = _heap.length;
      while (true) {
        final l = 2 * i + 1, r = 2 * i + 2;
        int s = i;
        if (l < n && cmp(_heap[l], _heap[s]) < 0) s = l;
        if (r < n && cmp(_heap[r], _heap[s]) < 0) s = r;
        if (s == i) break;
        final t = _heap[i];
        _heap[i] = _heap[s];
        _heap[s] = t;
        i = s;
      }
    }
    return top;
  }
}

// ============================================================ Entities

class Player {
  double x, y;
  double hp = 240, maxHp = 240;
  double mana = 100, maxMana = 100;
  int level = 1, xp = 0, xpNext = 60, gold = 0, kills = 0;
  // potion belt (original-style: number keys 1-0)
  int healthPotions = 3, manaPotions = 2;
  double speed = 3.4;
  List<Point> path = [];
  Monster? target;
  double attackCd = 0;
  double facing = 0;
  // animation
  double animTime = 0; // walk-cycle phase
  bool moving = false;
  double attackAnim = 0; // 0..1 swing progress
  Player(this.x, this.y);

  double get attackRange => 1.4;
  // original: 120 base damage, 40% critical chance
  double get baseDamage => 120 + level * 10.0;
  double get critChance => 0.40;
  double get critMult => 2.0;
}

enum MonsterKind { skeleton, zombie, demon }

class Monster {
  double x, y;
  double hp, maxHp;
  final MonsterKind kind;
  final double speed, dmg;
  final int xpValue;
  final int resistance; // 0-70: % physical damage reduction
  List<Point> path = [];
  double attackCd = 0, hitFlash = 0, repathCd = 0;
  // animation
  double animTime = 0, facing = 0, attackAnim = 0;
  bool moving = false;
  // death animation
  bool dying = false;
  double deathTime = 0;
  Monster(this.x, this.y, this.kind, this.hp, this.maxHp, this.speed, this.dmg,
      this.xpValue, this.resistance);

  factory Monster.make(double x, double y, MonsterKind k, int floor) {
    switch (k) {
      case MonsterKind.skeleton:
        return Monster(x, y, k, 120.0 + floor * 30, 120.0 + floor * 30, 2.1,
            10 + floor.toDouble(), 8 + floor * 2, 10);
      case MonsterKind.zombie:
        return Monster(x, y, k, 240.0 + floor * 50, 240.0 + floor * 50, 1.3,
            16 + floor.toDouble(), 12 + floor * 2, 35);
      case MonsterKind.demon:
        return Monster(x, y, k, 420.0 + floor * 80, 420.0 + floor * 80, 2.5,
            24 + floor * 2.0, 22 + floor * 3, 50);
    }
  }

  double get range => 1.3;
}

class Fireball {
  double x, y, vx, vy, life, dmg;
  Fireball(this.x, this.y, this.vx, this.vy, this.dmg, this.life);
}

enum PropKind { barrel, bones, torch }

class Prop {
  final double x, y;
  final PropKind kind;
  bool broken = false;
  double flicker = 0; // for torches
  Prop(this.x, this.y, this.kind);
}

enum LootKind { gold, healthPotion, manaPotion }

class Loot {
  final double x, y;
  final int gold;
  final LootKind kind;
  double bob = 0;
  Loot(this.x, this.y, this.gold, this.kind);
}

class FloatText {
  double x, y, life;
  final String text;
  final Color color;
  final bool big;
  FloatText(this.x, this.y, this.text, this.color, this.life,
      {this.big = false});
}

// ============================================================ Sprites
// Real Diablo II sprite sheets (map.png): grid of [steps] columns (frames)
// x [angles] rows (directions). Used for LOCAL LEARNING ONLY (© Blizzard).

class SpriteSheet {
  final ui.Image image;
  final int angles, steps;
  SpriteSheet(this.image, this.angles, this.steps);
  double get frameW => image.width / steps;
  double get frameH => image.height / angles;

  // original direction mapping (diablo.js): row index from a screen-space dir
  int angleFor(double facing) {
    final cx = math.cos(facing), cy = math.sin(facing);
    final sx = cx - cy, sy = (cx + cy) * 0.5; // isometric screen direction
    var a = ((math.atan2(sy, sx) / math.pi + 2.75) * angles / 2 + angles / 2)
        .round();
    a %= angles;
    if (a < 0) a += angles;
    return a;
  }
}

class CharAnims {
  final SpriteSheet? idle, walk, attack, death;
  final double scale;
  CharAnims({this.idle, this.walk, this.attack, this.death, this.scale = 0.5});
}

class Sprites {
  final CharAnims hero;
  final Map<MonsterKind, CharAnims> monsters;
  final ui.Image? barrel, coins, potions;
  Sprites(this.hero, this.monsters, this.barrel, this.coins, this.potions);
}

// ----------------------------------------------------------------------------
// ┌─ GRAPHICS CONFIG ─────────────────────────────────────────────────────────
// │ To swap art: drop your own PNG sheet at the listed path, then update its
// │ `dirs` (rows = facing directions) and `frames` (cols = animation frames).
// │ A sheet is a grid: width = frames * frameWidth, height = dirs * frameHeight.
// │ `scale` resizes the sprite on screen. Single image (no anim) => use 1 frame.
// │ See assets/README.md for the full guide.
// └───────────────────────────────────────────────────────────────────────────
class AnimCfg {
  final String file; // path under the character folder
  final int frames; // columns in the sheet
  const AnimCfg(this.file, this.frames);
}

class CharCfg {
  final String dir; // folder holding this character's sheets
  final int dirs; // rows (facing directions: 8 or 16)
  final double scale;
  final AnimCfg idle, walk, attack;
  final AnimCfg? death;
  const CharCfg(this.dir, this.dirs, this.scale, this.idle, this.walk,
      this.attack, [this.death]);
}

// EDIT THESE to retheme the game. Numbers are measured from the current sheets.
const kHeroCfg = CharCfg(
  'assets/characters/hero', 16, 0.5,
  AnimCfg('idle.png', 8), AnimCfg('walk.png', 8), AnimCfg('attack.png', 9),
);
const kMonsterCfgs = <MonsterKind, CharCfg>{
  MonsterKind.skeleton: CharCfg(
    'assets/characters/skeleton', 8, 0.55,
    AnimCfg('idle.png', 8), AnimCfg('walk.png', 8), AnimCfg('attack.png', 16),
    AnimCfg('death.png', 1),
  ),
  MonsterKind.zombie: CharCfg(
    'assets/characters/fallen', 8, 0.55,
    AnimCfg('idle.png', 12), AnimCfg('walk.png', 14), AnimCfg('attack.png', 17),
    AnimCfg('death.png', 1),
  ),
  MonsterKind.demon: CharCfg(
    'assets/characters/imp', 8, 0.6,
    AnimCfg('idle.png', 8), AnimCfg('walk.png', 9), AnimCfg('attack.png', 16),
    AnimCfg('death.png', 1),
  ),
};
const kBarrelPath = 'assets/objects/barrel.png';
const kCoinsPath = 'assets/objects/coins.png';
const kPotionsPath = 'assets/objects/potions.png';

Future<ui.Image> _loadImage(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<CharAnims> _loadChar(CharCfg c) async {
  Future<SpriteSheet> sheet(AnimCfg a) async =>
      SpriteSheet(await _loadImage('${c.dir}/${a.file}'), c.dirs, a.frames);
  return CharAnims(
    idle: await sheet(c.idle),
    walk: await sheet(c.walk),
    attack: await sheet(c.attack),
    death: c.death == null ? null : await sheet(c.death!),
    scale: c.scale,
  );
}

Future<Sprites> loadSprites() async {
  final hero = await _loadChar(kHeroCfg);
  final monsters = <MonsterKind, CharAnims>{};
  for (final e in kMonsterCfgs.entries) {
    monsters[e.key] = await _loadChar(e.value);
  }
  return Sprites(
    hero,
    monsters,
    await _loadImage(kBarrelPath),
    await _loadImage(kCoinsPath),
    await _loadImage(kPotionsPath),
  );
}

// ============================================================ Game Screen

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  static const tileW = 64.0, tileH = 32.0;
  late Ticker _ticker;
  Duration _last = Duration.zero;
  final rng = math.Random(); // unseeded: a fresh random dungeon every launch

  late Dungeon dungeon;
  late Player player;
  final List<Monster> monsters = [];
  final List<Fireball> fireballs = [];
  final List<Loot> loot = [];
  final List<FloatText> floats = [];
  final List<Prop> props = [];

  int floorNum = 1;
  bool showMap = false;
  bool gameOver = false;
  Offset cursor = Offset.zero;
  Size viewport = const Size(800, 600);
  final FocusNode _focus = FocusNode();

  Sprites? sprites; // null until loaded; renderer falls back to vectors
  bool blocked = false; // release build that bundles copyrighted sprites
  double animClock = 0; // free-running clock for idle/walk frame cycling

  @override
  void initState() {
    super.initState();
    _newFloor(1, fullHeal: true);
    _ticker = createTicker(_tick)..start();
    loadSprites().then((s) {
      if (!mounted) return;
      setState(() {
        sprites = s;
        blocked = distributionBlocked(true);
      });
    }).catchError((_) {
      // assets missing -> legal vector fallback, nothing to block
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _newFloor(int n, {bool fullHeal = false}) {
    floorNum = n;
    dungeon = Dungeon(40, 40, rng);
    monsters.clear();
    fireballs.clear();
    loot.clear();
    floats.clear();
    props.clear();
    final first = dungeon.rooms.first;
    final spawnX = first.left + first.width / 2;
    final spawnY = first.top + first.height / 2;
    if (fullHeal) {
      player = Player(spawnX, spawnY);
    } else {
      player.x = spawnX;
      player.y = spawnY;
      player.path = [];
      player.target = null;
    }
    for (int i = 1; i < dungeon.rooms.length; i++) {
      final r = dungeon.rooms[i];
      final count = 1 + rng.nextInt(3);
      for (int c = 0; c < count; c++) {
        final mx = r.left + 1 + rng.nextInt(math.max(1, r.width - 2));
        final my = r.top + 1 + rng.nextInt(math.max(1, r.height - 2));
        if (!dungeon.walkable(mx, my)) continue;
        final roll = rng.nextInt(10);
        final kind = roll < 5
            ? MonsterKind.skeleton
            : roll < 8
                ? MonsterKind.zombie
                : MonsterKind.demon;
        monsters.add(Monster.make(mx + 0.5, my + 0.5, kind, n));
      }
      // floor props: barrels & bones (objects layer)
      final propCount = rng.nextInt(3);
      for (int c = 0; c < propCount; c++) {
        final mx = r.left + 1 + rng.nextInt(math.max(1, r.width - 2));
        final my = r.top + 1 + rng.nextInt(math.max(1, r.height - 2));
        if (!dungeon.walkable(mx, my)) continue;
        if (_dist(mx + 0.5, my + 0.5, spawnX, spawnY) < 2) continue;
        props.add(Prop(mx + 0.5, my + 0.5,
            rng.nextBool() ? PropKind.barrel : PropKind.bones));
      }
    }
    // wall torches for lighting / atmosphere
    for (int y = 0; y < dungeon.h; y++) {
      for (int x = 0; x < dungeon.w; x++) {
        if (dungeon.at(x, y) != Tile.wall) continue;
        if (dungeon.at(x, y + 1) == Tile.floor && rng.nextDouble() < 0.10) {
          props.add(Prop(x + 0.5, y + 0.5, PropKind.torch));
        }
      }
    }
  }

  Offset worldToScreen(double tx, double ty) {
    final ox = viewport.width / 2 - (player.x - player.y) * tileW / 2;
    final oy = viewport.height / 2 - (player.x + player.y) * tileH / 2;
    return Offset(ox + (tx - ty) * tileW / 2, oy + (tx + ty) * tileH / 2);
  }

  Offset screenToWorld(Offset s) {
    final ox = viewport.width / 2 - (player.x - player.y) * tileW / 2;
    final oy = viewport.height / 2 - (player.x + player.y) * tileH / 2;
    final a = (s.dx - ox) / (tileW / 2);
    final b = (s.dy - oy) / (tileH / 2);
    return Offset((a + b) / 2, (b - a) / 2);
  }

  void _tick(Duration now) {
    final dt =
        _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    animClock += dt.clamp(0.0, 0.05);
    if (!gameOver) _update(dt.clamp(0.0, 0.05));
    if (mounted) setState(() {});
  }

  void _update(double dt) {
    player.attackCd = math.max(0, player.attackCd - dt);
    player.attackAnim = math.max(0, player.attackAnim - dt * 3);
    player.mana = math.min(player.maxMana, player.mana + dt * 4);
    player.moving = false;

    if (player.target != null && !monsters.contains(player.target)) {
      player.target = null;
    }
    if (player.target != null) {
      final t = player.target!;
      final dist = _dist(player.x, player.y, t.x, t.y);
      if (dist <= player.attackRange) {
        player.path = [];
        player.facing = math.atan2(t.y - player.y, t.x - player.x);
        if (player.attackCd <= 0) {
          player.attackCd = 0.55;
          player.attackAnim = 1.0;
          // original combat: 120 base, 40% crit, monster resistance
          final crit = rng.nextDouble() < player.critChance;
          var dmg = player.baseDamage * (crit ? player.critMult : 1.0);
          dmg = dmg * (100 - t.resistance) / 100;
          t.hp -= dmg;
          t.hitFlash = 0.15;
          floats.add(FloatText(t.x, t.y - 0.5, dmg.toInt().toString(),
              crit ? Colors.orangeAccent : Colors.white, crit ? 0.9 : 0.7,
              big: crit));
          if (t.hp <= 0) _killMonster(t);
        }
      } else {
        if (player.path.isEmpty) {
          player.path = findPath(dungeon,
              Point(player.x.floor(), player.y.floor()),
              Point(t.x.floor(), t.y.floor()));
          if (player.path.isNotEmpty) player.path.removeAt(0);
        }
        _stepPath(dt);
      }
    } else if (player.path.isNotEmpty) {
      _stepPath(dt);
    }
    if (player.moving) player.animTime += dt * 9;

    for (final f in fireballs) {
      f.x += f.vx * dt;
      f.y += f.vy * dt;
      f.life -= dt;
      if (dungeon.at(f.x.floor(), f.y.floor()) == Tile.wall) f.life = 0;
      for (final m in monsters) {
        if (m.dying) continue;
        if (_dist(f.x, f.y, m.x, m.y) < 0.6) {
          final dmg = f.dmg * (100 - m.resistance) / 100;
          m.hp -= dmg;
          m.hitFlash = 0.15;
          floats.add(FloatText(
              m.x, m.y - 0.5, dmg.toInt().toString(), Colors.orange, 0.7));
          f.life = 0;
          if (m.hp <= 0) _killMonster(m);
          break;
        }
      }
    }
    fireballs.removeWhere((f) => f.life <= 0);

    for (final m in monsters) {
      m.attackCd = math.max(0, m.attackCd - dt);
      m.hitFlash = math.max(0, m.hitFlash - dt);
      m.repathCd = math.max(0, m.repathCd - dt);
      m.attackAnim = math.max(0, m.attackAnim - dt * 3);
      m.moving = false;
      if (m.dying) {
        m.deathTime += dt;
        continue;
      }
      final d = _dist(m.x, m.y, player.x, player.y);
      if (d < 10) {
        m.facing = math.atan2(player.y - m.y, player.x - m.x);
        if (d <= m.range) {
          if (m.attackCd <= 0) {
            m.attackCd = 1.0;
            m.attackAnim = 1.0;
            player.hp -= m.dmg;
            floats.add(FloatText(player.x, player.y - 0.6,
                m.dmg.toInt().toString(), Colors.red, 0.7));
            if (player.hp <= 0) {
              player.hp = 0;
              gameOver = true;
            }
          }
        } else {
          if (m.repathCd <= 0) {
            m.path = findPath(dungeon, Point(m.x.floor(), m.y.floor()),
                Point(player.x.floor(), player.y.floor()));
            if (m.path.length > 1) m.path.removeAt(0);
            m.repathCd = 0.4;
          }
          _stepMonster(m, dt);
        }
      }
      if (m.moving) m.animTime += dt * 8;
    }
    // remove monsters whose death animation finished, drop their loot
    monsters.removeWhere((m) {
      if (m.dying && m.deathTime > 0.5) {
        _dropLoot(m);
        return true;
      }
      return false;
    });

    for (final l in loot) {
      l.bob += dt * 3;
    }
    loot.removeWhere((l) {
      if (_dist(l.x, l.y, player.x, player.y) < 0.7) {
        switch (l.kind) {
          case LootKind.gold:
            player.gold += l.gold;
            floats.add(FloatText(
                player.x, player.y - 0.8, '+${l.gold}g', Colors.amber, 0.8));
            break;
          case LootKind.healthPotion:
            player.healthPotions++;
            break;
          case LootKind.manaPotion:
            player.manaPotions++;
            break;
        }
        return true;
      }
      return false;
    });

    // ---- props: torch flicker + barrel smashing
    for (final pr in props) {
      if (pr.kind == PropKind.torch) {
        pr.flicker += dt * 12;
        continue;
      }
      if (pr.kind != PropKind.barrel || pr.broken) continue;
      bool smash = _dist(pr.x, pr.y, player.x, player.y) < 0.75;
      if (!smash) {
        for (final f in fireballs) {
          if (_dist(f.x, f.y, pr.x, pr.y) < 0.6) {
            smash = true;
            f.life = 0;
            break;
          }
        }
      }
      if (smash) {
        pr.broken = true;
        floats.add(FloatText(pr.x, pr.y - 0.4, '쾅!', Colors.orangeAccent, 0.6));
        if (rng.nextDouble() < 0.6) {
          loot.add(Loot(pr.x, pr.y, 2 + rng.nextInt(6), LootKind.gold));
        }
        if (rng.nextDouble() < 0.18) {
          loot.add(Loot(pr.x, pr.y, 0, LootKind.healthPotion));
        }
      }
    }
    props.removeWhere((pr) => pr.broken);

    for (final f in floats) {
      f.y -= dt * 0.8;
      f.life -= dt;
    }
    floats.removeWhere((f) => f.life <= 0);

    final lastR = dungeon.rooms.last;
    final lx = lastR.left + lastR.width / 2, ly = lastR.top + lastR.height / 2;
    if (_dist(player.x, player.y, lx, ly) < 0.9 && monsters.isEmpty) {
      _newFloor(floorNum + 1);
    }
  }

  // 5x5 sub-tile walkability check (original-style fine collision):
  // an entity of radius r may only stand where all four corners are floor.
  bool _free(double x, double y, double r) {
    return dungeon.walkable((x - r).floor(), (y - r).floor()) &&
        dungeon.walkable((x + r).floor(), (y - r).floor()) &&
        dungeon.walkable((x - r).floor(), (y + r).floor()) &&
        dungeon.walkable((x + r).floor(), (y + r).floor());
  }

  void _stepPath(double dt) {
    if (player.path.isEmpty) return;
    final next = player.path.first;
    final tx = next.x + 0.5, ty = next.y + 0.5;
    final dx = tx - player.x, dy = ty - player.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.08) {
      player.path.removeAt(0);
      return;
    }
    player.facing = math.atan2(dy, dx);
    player.moving = true;
    final step = player.speed * dt;
    const r = 0.28;
    final nx = player.x + dx / d * step;
    if (_free(nx, player.y, r)) player.x = nx;
    final ny = player.y + dy / d * step;
    if (_free(player.x, ny, r)) player.y = ny;
  }

  void _stepMonster(Monster m, double dt) {
    if (m.path.isEmpty) return;
    final next = m.path.first;
    final tx = next.x + 0.5, ty = next.y + 0.5;
    final dx = tx - m.x, dy = ty - m.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.1) {
      m.path.removeAt(0);
      return;
    }
    m.moving = true;
    final step = m.speed * dt;
    const r = 0.28;
    final nx = m.x + dx / d * step;
    if (_free(nx, m.y, r)) m.x = nx;
    final ny = m.y + dy / d * step;
    if (_free(m.x, ny, r)) m.y = ny;
  }

  void _killMonster(Monster m) {
    if (m.dying) return;
    m.dying = true;
    m.deathTime = 0;
    if (player.target == m) player.target = null;
    player.kills++;
    player.xp += m.xpValue;
    floats.add(
        FloatText(m.x, m.y - 0.5, '+${m.xpValue} XP', Colors.lightBlue, 0.9));
    while (player.xp >= player.xpNext) {
      player.xp -= player.xpNext;
      player.level++;
      player.xpNext = (player.xpNext * 1.5).round();
      player.maxHp += 20;
      player.maxMana += 8;
      player.hp = player.maxHp;
      player.mana = player.maxMana;
      floats.add(FloatText(
          player.x, player.y - 1.0, 'LEVEL UP!', Colors.yellowAccent, 1.4));
    }
  }

  void _dropLoot(Monster m) {
    if (rng.nextDouble() < 0.75) {
      loot.add(Loot(m.x, m.y, 3 + rng.nextInt(8 + floorNum * 2), LootKind.gold));
    }
    final roll = rng.nextDouble();
    if (roll < 0.12) {
      loot.add(Loot(m.x + 0.2, m.y, 0, LootKind.healthPotion));
    } else if (roll < 0.20) {
      loot.add(Loot(m.x + 0.2, m.y, 0, LootKind.manaPotion));
    }
  }

  double _dist(double ax, double ay, double bx, double by) {
    final dx = ax - bx, dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _onTapDown(TapDownDetails d) {
    if (gameOver) {
      setState(() {
        gameOver = false;
        floorNum = 1;
        _newFloor(1, fullHeal: true);
      });
      return;
    }
    final wp = screenToWorld(d.localPosition);
    Monster? clicked;
    double best = 0.9;
    for (final m in monsters) {
      if (m.dying) continue;
      final dd = _dist(wp.dx, wp.dy, m.x, m.y);
      if (dd < best) {
        best = dd;
        clicked = m;
      }
    }
    if (clicked != null) {
      player.target = clicked;
      player.path = [];
      return;
    }
    player.target = null;
    final gx = wp.dx.floor(), gy = wp.dy.floor();
    if (dungeon.walkable(gx, gy)) {
      player.path = findPath(
          dungeon, Point(player.x.floor(), player.y.floor()), Point(gx, gy));
      if (player.path.isNotEmpty) player.path.removeAt(0);
    }
  }

  void _castFireball() {
    if (gameOver || player.mana < 8) return;
    player.mana -= 8;
    final wp = screenToWorld(cursor);
    double dx = wp.dx - player.x, dy = wp.dy - player.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.01) {
      dx = math.cos(player.facing);
      dy = math.sin(player.facing);
    } else {
      dx /= d;
      dy /= d;
    }
    player.facing = math.atan2(dy, dx);
    fireballs.add(
        Fireball(player.x, player.y, dx * 7, dy * 7, 14 + player.level * 3.0, 1.2));
  }

  void _drinkHealth() {
    if (player.healthPotions <= 0 || player.hp >= player.maxHp) return;
    player.healthPotions--;
    player.hp = math.min(player.maxHp, player.hp + player.maxHp * 0.4);
    floats.add(FloatText(
        player.x, player.y - 0.8, '+HP', Colors.greenAccent, 0.9));
  }

  void _drinkMana() {
    if (player.manaPotions <= 0 || player.mana >= player.maxMana) return;
    player.manaPotions--;
    player.mana = math.min(player.maxMana, player.mana + player.maxMana * 0.5);
    floats.add(
        FloatText(player.x, player.y - 0.8, '+MP', Colors.cyanAccent, 0.9));
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.tab) {
      setState(() => showMap = !showMap);
    } else if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyF) {
      _castFireball();
    } else if (k == LogicalKeyboardKey.keyQ ||
        k == LogicalKeyboardKey.digit1 ||
        k == LogicalKeyboardKey.digit2) {
      // belt slots 1-2: health potions
      _drinkHealth();
    } else if (k == LogicalKeyboardKey.keyE ||
        k == LogicalKeyboardKey.digit3 ||
        k == LogicalKeyboardKey.digit4) {
      // belt slots 3-4: mana potions
      _drinkMana();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (blocked) return const _BlockedApp();
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      body: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: (e) => cursor = e.localPosition,
          child: GestureDetector(
            onTapDown: _onTapDown,
            onSecondaryTapDown: (_) => _castFireball(),
            child: LayoutBuilder(builder: (ctx, c) {
              viewport = Size(c.maxWidth, c.maxHeight);
              return Stack(children: [
                CustomPaint(size: Size.infinite, painter: GamePainter(this)),
                if (gameOver) _gameOverOverlay(),
                _hud(),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _gameOverOverlay() {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: const [
        Text('YOU DIED',
            style: TextStyle(
                color: Color(0xFFBB3333),
                fontSize: 64,
                fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Text('탭하여 다시 시작',
            style: TextStyle(color: Colors.white70, fontSize: 20)),
      ]),
    );
  }

  Widget _hud() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 8, runSpacing: 6, children: [
                _statChip('Floor $floorNum', Colors.purpleAccent),
                _statChip('Lv ${player.level}', Colors.amber),
                _statChip('${player.gold} G', Colors.yellow),
                _statChip('Kills ${player.kills}', Colors.redAccent),
                _statChip('적 ${monsters.length}', Colors.orangeAccent),
                _statChip('좌클릭:이동/공격  F:파이어볼  Tab:지도',
                    Colors.white38),
              ]),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _orb(player.hp, player.maxHp, const Color(0xFFc0392b),
                      const Color(0xFFe74c3c), 'HP'),
                  const Spacer(),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 280,
                      child: _bar(player.xp / player.xpNext,
                          const Color(0xFF6c5ce7),
                          'XP ${player.xp}/${player.xpNext}'),
                    ),
                    const SizedBox(height: 10),
                    _potionBelt(),
                  ]),
                  const Spacer(),
                  _orb(player.mana, player.maxMana, const Color(0xFF2471a3),
                      const Color(0xFF3498db), 'MP'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _potionBelt() {
    Widget slot(String key, IconData icon, Color c, int count) => Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.withOpacity(0.7), width: 2),
          ),
          child: Stack(children: [
            Center(child: Icon(icon, color: c, size: 22)),
            Positioned(
              left: 3,
              top: 1,
              child: Text(key,
                  style: const TextStyle(fontSize: 9, color: Colors.white54)),
            ),
            Positioned(
              right: 3,
              bottom: 1,
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: count > 0 ? Colors.white : Colors.white30)),
            ),
          ]),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      slot('1·2', Icons.local_drink, const Color(0xFFe74c3c),
          player.healthPotions),
      slot('3·4', Icons.science, const Color(0xFF3498db), player.manaPotions),
    ]);
  }

  Widget _statChip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withOpacity(0.6)),
        ),
        child: Text(t, style: TextStyle(color: c, fontSize: 13)),
      );

  Widget _bar(double frac, Color c, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 2),
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: frac.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ],
      );

  Widget _orb(double v, double max, Color dark, Color light, String label) {
    final frac = (v / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
            border: Border.all(color: Colors.white24, width: 2),
          ),
        ),
        ClipOval(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: frac,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [light, dark]),
              ),
            ),
          ),
        ),
        Text('$label\n${v.toInt()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(blurRadius: 2, color: Colors.black)])),
      ]),
    );
  }
}

// ============================================================ Painter

class _Drawable {
  final double depth;
  final void Function() draw;
  _Drawable(this.depth, this.draw);
}

class GamePainter extends CustomPainter {
  final _GameScreenState g;
  GamePainter(this.g);

  static const tileW = _GameScreenState.tileW;
  static const tileH = _GameScreenState.tileH;

  @override
  void paint(Canvas canvas, Size size) {
    final d = g.dungeon;
    final p = g.player;
    final px = p.x.floor(), py = p.y.floor();
    const rad = 17;

    final cells = <List<int>>[];
    for (int y = py - rad; y <= py + rad; y++) {
      for (int x = px - rad; x <= px + rad; x++) {
        if (d.at(x, y) == Tile.empty) continue;
        cells.add([x, y]);
      }
    }
    cells.sort((a, b) => (a[0] + a[1]).compareTo(b[0] + b[1]));

    for (final c in cells) {
      if (d.at(c[0], c[1]) == Tile.floor) _drawFloor(canvas, c[0], c[1]);
    }

    // hover tile highlight (original diablo-js cursor highlight)
    final hov = g.screenToWorld(g.cursor);
    final hx = hov.dx.floor(), hy = hov.dy.floor();
    if (d.walkable(hx, hy)) {
      _diamond(
          canvas,
          g.worldToScreen(hx + 0.5, hy + 0.5),
          Paint()
            ..color = Colors.white.withOpacity(0.18)
            ..style = PaintingStyle.fill);
    }

    // torch light pools on floor
    for (final pr in g.props) {
      if (pr.kind != PropKind.torch) continue;
      final s = g.worldToScreen(pr.x, pr.y + 0.5);
      final r = 46 + math.sin(pr.flicker) * 5;
      canvas.drawCircle(
          s,
          r,
          Paint()
            ..color = const Color(0xFFffaa44).withOpacity(0.10)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    }

    // flat decals (bones)
    for (final pr in g.props) {
      if (pr.kind == PropKind.bones) _drawBones(canvas, pr);
    }

    final last = d.rooms.last;
    _drawPortal(canvas, last.left + last.width / 2, last.top + last.height / 2);

    for (final l in g.loot) {
      _drawLoot(canvas, l);
    }

    if (p.path.isNotEmpty) {
      final dest = p.path.last;
      final s = g.worldToScreen(dest.x + 0.5, dest.y + 0.5);
      canvas.drawCircle(
          s,
          8,
          Paint()
            ..color = Colors.greenAccent.withOpacity(0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    final drawList = <_Drawable>[];
    for (final c in cells) {
      if (d.at(c[0], c[1]) == Tile.wall) {
        final cx = c[0], cy = c[1];
        drawList.add(
            _Drawable(cx + cy.toDouble(), () => _drawWall(canvas, cx, cy)));
      }
    }
    for (final pr in g.props) {
      if (pr.kind == PropKind.barrel) {
        drawList.add(_Drawable(pr.x + pr.y, () => _drawBarrel(canvas, pr)));
      } else if (pr.kind == PropKind.torch) {
        drawList.add(_Drawable(pr.x + pr.y + 0.05, () => _drawTorch(canvas, pr)));
      }
    }
    for (final m in g.monsters) {
      drawList.add(_Drawable(m.x + m.y, () => _drawMonster(canvas, m)));
    }
    drawList.add(_Drawable(p.x + p.y, () => _drawPlayer(canvas, p)));
    drawList.sort((a, b) => a.depth.compareTo(b.depth));
    for (final dr in drawList) {
      dr.draw();
    }

    for (final f in g.fireballs) {
      final s = g.worldToScreen(f.x, f.y);
      canvas.drawCircle(
          s,
          12,
          Paint()
            ..color = Colors.orange.withOpacity(0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(s, 6, Paint()..color = Colors.orangeAccent);
      canvas.drawCircle(
          s - const Offset(2, 2), 3, Paint()..color = Colors.yellow);
    }

    for (final f in g.floats) {
      final s = g.worldToScreen(f.x, f.y);
      final tp = TextPainter(
        text: TextSpan(
            text: f.text,
            style: TextStyle(
                color: f.color.withOpacity(f.life.clamp(0.0, 1.0)),
                fontSize: f.big ? 22 : 14,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(blurRadius: 2, color: Colors.black)])),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, s - Offset(tp.width / 2, tp.height / 2));
    }

    final vg = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
        stops: const [0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vg);

    if (g.showMap) _drawMinimap(canvas, size);
  }

  void _diamond(Canvas canvas, Offset c, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - tileH / 2)
      ..lineTo(c.dx + tileW / 2, c.dy)
      ..lineTo(c.dx, c.dy + tileH / 2)
      ..lineTo(c.dx - tileW / 2, c.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawFloor(Canvas canvas, int x, int y) {
    final c = g.worldToScreen(x + 0.5, y + 0.5);
    final shade = ((x * 7 + y * 13) % 3);
    final col = Color.lerp(
        const Color(0xFF3a3530), const Color(0xFF2a2723), shade / 2)!;
    _diamond(canvas, c, Paint()..color = col);
    _diamond(
        canvas,
        c,
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  void _drawWall(Canvas canvas, int x, int y) {
    final top = g.worldToScreen(x + 0.5, y + 0.5);
    const wallH = 40.0;
    final leftPath = Path()
      ..moveTo(top.dx - tileW / 2, top.dy)
      ..lineTo(top.dx, top.dy + tileH / 2)
      ..lineTo(top.dx, top.dy + tileH / 2 + wallH)
      ..lineTo(top.dx - tileW / 2, top.dy + wallH)
      ..close();
    canvas.drawPath(leftPath, Paint()..color = const Color(0xFF272320));
    final rightPath = Path()
      ..moveTo(top.dx + tileW / 2, top.dy)
      ..lineTo(top.dx, top.dy + tileH / 2)
      ..lineTo(top.dx, top.dy + tileH / 2 + wallH)
      ..lineTo(top.dx + tileW / 2, top.dy + wallH)
      ..close();
    canvas.drawPath(rightPath, Paint()..color = const Color(0xFF1c1916));
    _diamond(canvas, top, Paint()..color = const Color(0xFF4a443c));
    _diamond(
        canvas,
        top,
        Paint()
          ..color = Colors.black.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  void _drawPortal(Canvas canvas, double x, double y) {
    final s = g.worldToScreen(x, y);
    canvas.drawCircle(
        s,
        22,
        Paint()
          ..color = Colors.cyanAccent.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.save();
    canvas.translate(s.dx, s.dy);
    canvas.scale(1, 0.5);
    canvas.drawCircle(
        Offset.zero,
        18,
        Paint()
          ..color = Colors.cyanAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawCircle(
        Offset.zero, 10, Paint()..color = Colors.cyan.withOpacity(0.5));
    canvas.restore();
  }

  void _drawLoot(Canvas canvas, Loot l) {
    final s = g.worldToScreen(l.x, l.y);
    final bob = math.sin(l.bob) * 3;
    final sp = g.sprites;
    if (l.kind == LootKind.gold) {
      if (sp?.coins != null) {
        final img = sp!.coins!;
        const sc = 0.7;
        final dw = img.width * sc, dh = img.height * sc;
        canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(s.dx - dw / 2, s.dy - dh / 2 + bob, dw, dh),
            Paint()..filterQuality = FilterQuality.medium);
        return;
      }
      canvas.drawCircle(
          s + Offset(0, bob),
          7,
          Paint()
            ..color = Colors.amber.withOpacity(0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(s + Offset(0, bob), 4, Paint()..color = Colors.amber);
      return;
    }
    if (sp?.potions != null) {
      // potions.png is a row of potion icons; crop one by kind
      final img = sp!.potions!;
      final n = 4; // assume 4 potion icons across
      final fw = img.width / n;
      final idx = l.kind == LootKind.healthPotion ? 0 : 1;
      const sc = 0.22;
      final dw = fw * sc, dh = img.height * sc;
      canvas.drawImageRect(
          img,
          Rect.fromLTWH(fw * idx, 0, fw, img.height.toDouble()),
          Rect.fromLTWH(s.dx - dw / 2, s.dy - dh + 4 + bob, dw, dh),
          Paint()..filterQuality = FilterQuality.medium);
      return;
    }
    final glass =
        l.kind == LootKind.healthPotion ? Colors.redAccent : Colors.blueAccent;
    canvas.drawCircle(
        s + Offset(0, -6 + bob),
        9,
        Paint()
          ..color = glass.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: s + Offset(0, -6 + bob), width: 10, height: 14),
            const Radius.circular(3)),
        Paint()..color = glass);
    canvas.drawRect(
        Rect.fromCenter(center: s + Offset(0, -13 + bob), width: 5, height: 4),
        Paint()..color = Colors.brown);
  }

  void _drawBones(Canvas canvas, Prop pr) {
    final s = g.worldToScreen(pr.x, pr.y);
    final paint = Paint()
      ..color = const Color(0xFFcfc8b0).withOpacity(0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(s + const Offset(-6, 1), s + const Offset(6, -1), paint);
    canvas.drawLine(s + const Offset(-3, -3), s + const Offset(2, 4), paint);
    canvas.drawCircle(
        s + const Offset(7, -2), 3, Paint()..color = const Color(0xFFcfc8b0));
  }

  void _drawBarrel(Canvas canvas, Prop pr) {
    final s = g.worldToScreen(pr.x, pr.y);
    _shadow(canvas, s, 9);
    final img = g.sprites?.barrel;
    if (img != null) {
      const scale = 0.5;
      final dw = img.width * scale, dh = img.height * scale;
      canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(s.dx - dw / 2, s.dy - dh + 4, dw, dh),
          Paint()..filterQuality = FilterQuality.medium);
      return;
    }
    final body = Rect.fromLTWH(s.dx - 9, s.dy - 24, 18, 24);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(5)),
        Paint()..color = const Color(0xFF6e4a25));
    // hoops
    final hoop = Paint()
      ..color = const Color(0xFF3a2814)
      ..strokeWidth = 2;
    canvas.drawLine(s + const Offset(-9, -18), s + const Offset(9, -18), hoop);
    canvas.drawLine(s + const Offset(-9, -7), s + const Offset(9, -7), hoop);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(s.dx - 9, s.dy - 26, 18, 5),
            const Radius.circular(2)),
        Paint()..color = const Color(0xFF8a5e30));
  }

  void _drawTorch(Canvas canvas, Prop pr) {
    final s = g.worldToScreen(pr.x, pr.y) + const Offset(0, -22);
    // bracket
    canvas.drawLine(s + const Offset(0, 6), s + const Offset(0, 18),
        Paint()..color = const Color(0xFF3a2a18)..strokeWidth = 3);
    // flame
    final f = math.sin(pr.flicker) * 2;
    canvas.drawCircle(
        s,
        9 + f,
        Paint()
          ..color = Colors.orange.withOpacity(0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    final flame = Path()
      ..moveTo(s.dx, s.dy - 10 - f)
      ..quadraticBezierTo(s.dx + 5, s.dy - 2, s.dx, s.dy + 4)
      ..quadraticBezierTo(s.dx - 5, s.dy - 2, s.dx, s.dy - 10 - f)
      ..close();
    canvas.drawPath(flame, Paint()..color = Colors.orangeAccent);
    canvas.drawCircle(
        s + Offset(0, -1), 3, Paint()..color = Colors.yellow);
  }

  void _shadow(Canvas canvas, Offset s, double r) {
    canvas.save();
    canvas.translate(s.dx, s.dy + 6);
    canvas.scale(1, 0.45);
    canvas.drawCircle(
        Offset.zero, r, Paint()..color = Colors.black.withOpacity(0.4));
    canvas.restore();
  }

  // isometric screen-space facing unit vector for a world-space angle
  Offset _isoDir(double facing) {
    final cx = math.cos(facing), cy = math.sin(facing);
    var sx = cx - cy, sy = (cx + cy) * 0.5;
    final m = math.sqrt(sx * sx + sy * sy);
    if (m < 1e-6) return const Offset(1, 0);
    return Offset(sx / m, sy / m);
  }

  // blit a sprite-sheet frame with feet anchored at [feet]
  void _blit(Canvas c, ui.Image img, Rect src, Offset feet, double scale,
      double srcOffsetX,
      {double opacity = 1, bool flash = false}) {
    final dw = src.width * scale, dh = src.height * scale;
    final dst = Rect.fromLTWH(
        feet.dx - dw / 2 - srcOffsetX * scale, feet.dy - dh, dw, dh);
    final p = Paint()..filterQuality = FilterQuality.medium;
    if (opacity < 1) p.color = Colors.white.withOpacity(opacity);
    if (flash) {
      p.colorFilter =
          ColorFilter.mode(Colors.white.withOpacity(0.7), BlendMode.srcATop);
    }
    c.drawImageRect(img, src, dst, p);
  }

  // returns true if an animated sprite was drawn (else caller draws vectors)
  bool _drawChar(Canvas c, CharAnims a, Offset feet, double facing,
      {required bool moving,
      double attackAnim = 0,
      bool dying = false,
      double deathT = 0,
      bool flash = false}) {
    SpriteSheet? sh;
    int frame;
    double op = 1;
    if (dying && a.death != null) {
      sh = a.death;
      final st = sh!.steps;
      frame = (deathT / 0.5 * st).floor().clamp(0, st - 1);
      op = (1 - deathT / 0.5).clamp(0.0, 1.0);
    } else if (attackAnim > 0 && a.attack != null) {
      sh = a.attack;
      final st = sh!.steps;
      frame = ((1 - attackAnim) * st).floor().clamp(0, st - 1);
    } else if (moving && a.walk != null) {
      sh = a.walk;
      frame = (g.animClock * 10).floor() % sh!.steps;
    } else if (a.idle != null) {
      sh = a.idle;
      frame = (g.animClock * 8).floor() % sh!.steps;
    } else {
      return false;
    }
    final ang = sh.angleFor(facing);
    final src = Rect.fromLTWH(
        sh.frameW * frame, sh.frameH * ang, sh.frameW, sh.frameH);
    _blit(c, sh.image, src, feet, a.scale, sh.frameH / 4,
        opacity: op, flash: flash);
    return true;
  }

  void _drawPlayer(Canvas canvas, Player p) {
    final s = g.worldToScreen(p.x, p.y);
    _shadow(canvas, s, 12);
    final sp = g.sprites;
    if (sp != null &&
        _drawChar(canvas, sp.hero, s, p.facing,
            moving: p.moving, attackAnim: p.attackAnim)) {
      return;
    }
    final dir = _isoDir(p.facing);
    final flip = dir.dx < 0 ? -1.0 : 1.0;
    final walk = p.moving ? math.sin(p.animTime) : 0.0;
    final bob = -(p.moving ? walk.abs() * 2.5 : 0.0);
    final legA = walk * 5;
    final hipY = s.dy - 4 + bob;
    final legPaint = Paint()
      ..color = const Color(0xFF2a3a52)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    // legs (swing opposite)
    canvas.drawLine(Offset(s.dx - 3, hipY),
        Offset(s.dx - 3 + legA, s.dy), legPaint);
    canvas.drawLine(Offset(s.dx + 3, hipY),
        Offset(s.dx + 3 - legA, s.dy), legPaint);
    // body
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(s.dx - 8, s.dy - 28 + bob, 16, 26),
            const Radius.circular(5)),
        Paint()..color = const Color(0xFF3b6ea5));
    // belt
    canvas.drawRect(Rect.fromLTWH(s.dx - 8, s.dy - 8 + bob, 16, 3),
        Paint()..color = const Color(0xFF6b4a2a));
    // head + helmet
    canvas.drawCircle(Offset(s.dx, s.dy - 34 + bob), 7,
        Paint()..color = const Color(0xFFe8c39e));
    canvas.drawArc(
        Rect.fromCircle(center: Offset(s.dx, s.dy - 34 + bob), radius: 8),
        math.pi, math.pi, true,
        Paint()..color = const Color(0xFF9a9a9a));
    // weapon arm: swing forward on attack
    final swing = math.sin(p.attackAnim * math.pi); // 0..1..0
    final baseAng = math.atan2(dir.dy, dir.dx);
    final ang = baseAng - flip * swing * 1.3;
    final shoulder = Offset(s.dx + flip * 3, s.dy - 20 + bob);
    final wlen = 16 + swing * 8;
    final wtip = shoulder + Offset(math.cos(ang) * wlen, math.sin(ang) * wlen);
    canvas.drawLine(shoulder, wtip,
        Paint()
          ..color = const Color(0xFFd0d0d8)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    // hilt
    canvas.drawCircle(shoulder, 2.5, Paint()..color = const Color(0xFF6b4a2a));
    if (swing > 0.3) {
      canvas.drawLine(shoulder, wtip,
          Paint()
            ..color = Colors.white.withOpacity(0.4 * swing)
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round);
    }
  }

  void _drawMonster(Canvas canvas, Monster m) {
    final s = g.worldToScreen(m.x, m.y);
    Color col;
    switch (m.kind) {
      case MonsterKind.skeleton:
        col = const Color(0xFFd8d8c0);
        break;
      case MonsterKind.zombie:
        col = const Color(0xFF5a8a4a);
        break;
      case MonsterKind.demon:
        col = const Color(0xFF8a2a2a);
        break;
    }
    final h = m.kind == MonsterKind.demon ? 34.0 : 26.0;

    // --- real D2 sprite path ---
    final sp = g.sprites;
    final anims = sp?.monsters[m.kind];
    if (sp != null && anims != null) {
      final t = m.dying ? (m.deathTime / 0.5).clamp(0.0, 1.0) : 0.0;
      _shadow(canvas, s, 11 * (1 - t));
      _drawChar(canvas, anims, s, m.facing,
          moving: m.moving,
          attackAnim: m.attackAnim,
          dying: m.dying,
          deathT: m.deathTime,
          flash: m.hitFlash > 0);
      if (!m.dying) {
        final sh = anims.idle ?? anims.walk;
        final hgt = sh != null ? sh.frameH * anims.scale : 36.0;
        if (m.hp < m.maxHp) {
          const w = 24.0;
          final top = s.dy - hgt - 4;
          canvas.drawRect(Rect.fromLTWH(s.dx - w / 2, top, w, 4),
              Paint()..color = Colors.black);
          canvas.drawRect(
              Rect.fromLTWH(
                  s.dx - w / 2, top, w * (m.hp / m.maxHp).clamp(0, 1), 4),
              Paint()..color = Colors.redAccent);
        }
        if (g.player.target == m) {
          canvas.drawCircle(
              s,
              16,
              Paint()
                ..color = Colors.yellowAccent.withOpacity(0.7)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        }
      }
      return;
    }

    // death animation: topple over + fade
    if (m.dying) {
      final t = (m.deathTime / 0.5).clamp(0.0, 1.0);
      _shadow(canvas, s, 11 * (1 - t));
      canvas.save();
      canvas.translate(s.dx, s.dy);
      canvas.rotate(1.3 * t);
      canvas.scale(1, 1 - 0.5 * t);
      final dp = Paint()
        ..color = col.withOpacity((1 - t).clamp(0.0, 1.0));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-7, -h + 4, 14, h - 8), const Radius.circular(4)),
          dp);
      canvas.drawCircle(Offset(0, -h + 4), 6, dp);
      canvas.restore();
      return;
    }

    _shadow(canvas, s, 11);
    final dir = _isoDir(m.facing);
    final walk = m.moving ? math.sin(m.animTime) : 0.0;
    final bob = -(m.moving ? walk.abs() * 2.0 : 0.0);
    final lunge = math.sin(m.attackAnim * math.pi); // attack lunge
    final off = Offset(dir.dx * lunge * 4, dir.dy * lunge * 4 + bob);
    if (m.hitFlash > 0) col = Color.lerp(col, Colors.white, 0.7)!;
    final cx = s.dx + off.dx, cy = s.dy + off.dy;
    final legA = walk * 4;
    final legPaint = Paint()
      ..color = col
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(cx - 3, cy - 4), Offset(cx - 3 + legA, cy), legPaint);
    canvas.drawLine(
        Offset(cx + 3, cy - 4), Offset(cx + 3 - legA, cy), legPaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 7, cy - h + 4, 14, h - 8),
            const Radius.circular(4)),
        Paint()..color = col);
    canvas.drawCircle(Offset(cx, cy - h + 4), 6, Paint()..color = col);
    canvas.drawCircle(Offset(cx - 2.5, cy - h + 3), 1.6,
        Paint()..color = Colors.red);
    canvas.drawCircle(Offset(cx + 2.5, cy - h + 3), 1.6,
        Paint()..color = Colors.red);
    if (m.kind == MonsterKind.demon) {
      canvas.drawLine(Offset(cx - 5, cy - h), Offset(cx - 8, cy - h - 5),
          Paint()..color = Colors.black..strokeWidth = 2);
      canvas.drawLine(Offset(cx + 5, cy - h), Offset(cx + 8, cy - h - 5),
          Paint()..color = Colors.black..strokeWidth = 2);
    }
    if (m.hp < m.maxHp) {
      const w = 22.0;
      final top = cy - h - 6;
      canvas.drawRect(
          Rect.fromLTWH(cx - w / 2, top, w, 4), Paint()..color = Colors.black);
      canvas.drawRect(
          Rect.fromLTWH(cx - w / 2, top, w * (m.hp / m.maxHp).clamp(0, 1), 4),
          Paint()..color = Colors.redAccent);
    }
    if (g.player.target == m) {
      canvas.drawCircle(
          s,
          16,
          Paint()
            ..color = Colors.yellowAccent.withOpacity(0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  void _drawMinimap(Canvas canvas, Size size) {
    const cell = 4.0;
    final d = g.dungeon;
    final mw = d.w * cell, mh = d.h * cell;
    final ox = size.width - mw - 20, oy = 70.0;
    canvas.drawRect(Rect.fromLTWH(ox - 4, oy - 4, mw + 8, mh + 8),
        Paint()..color = Colors.black.withOpacity(0.7));
    for (int y = 0; y < d.h; y++) {
      for (int x = 0; x < d.w; x++) {
        final t = d.grid[y][x];
        if (t == Tile.empty) continue;
        canvas.drawRect(
            Rect.fromLTWH(ox + x * cell, oy + y * cell, cell, cell),
            Paint()
              ..color = t == Tile.floor
                  ? const Color(0xFF555049)
                  : const Color(0xFF2a2622));
      }
    }
    for (final m in g.monsters) {
      canvas.drawRect(
          Rect.fromLTWH(ox + m.x * cell - 1, oy + m.y * cell - 1, 3, 3),
          Paint()..color = Colors.redAccent);
    }
    final last = d.rooms.last;
    canvas.drawRect(
        Rect.fromLTWH(ox + (last.left + last.width / 2) * cell - 2,
            oy + (last.top + last.height / 2) * cell - 2, 4, 4),
        Paint()..color = Colors.cyanAccent);
    canvas.drawRect(
        Rect.fromLTWH(
            ox + g.player.x * cell - 2, oy + g.player.y * cell - 2, 4, 4),
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
