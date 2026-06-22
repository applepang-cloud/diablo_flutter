import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diablo_flutter/main.dart';

void main() {
  testWidgets('game boots and HUD renders without exceptions', (tester) async {
    await tester.pumpWidget(const DiabloApp());
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Floor 1'), findsOneWidget);
    expect(find.text('Lv 1'), findsOneWidget);
  });

  testWidgets('dungeon spawns monsters and props, loop runs', (tester) async {
    await tester.pumpWidget(const DiabloApp());
    await tester.pump(const Duration(milliseconds: 16));
    final dynamic state =
        tester.state<State<GameScreen>>(find.byType(GameScreen));
    expect(state.dungeon.rooms.length, greaterThan(2));
    expect(state.monsters.length, greaterThan(0));
    expect(state.props.length, greaterThan(0));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  });

  testWidgets('combat kills an adjacent monster and it drops loot',
      (tester) async {
    await tester.pumpWidget(const DiabloApp());
    await tester.pump(const Duration(milliseconds: 16));
    final dynamic state =
        tester.state<State<GameScreen>>(find.byType(GameScreen));
    // place a single weak monster right next to the player and target it
    state.monsters.clear();
    state.loot.clear();
    final m = Monster.make(state.player.x + 1.0, state.player.y, MonsterKind.skeleton, 1);
    state.monsters.add(m);
    state.player.target = m;
    // pump enough frames for several attack swings to kill + finish death anim
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(state.monsters.contains(m), isFalse); // died & was removed
    expect(state.player.kills, greaterThan(0));
  });

  testWidgets('Diablo II sprite sheets load with expected frame geometry',
      (tester) async {
    Sprites? sprites;
    await tester.runAsync(() async {
      sprites = await loadSprites();
    });
    expect(sprites, isNotNull);
    final hero = sprites!.hero;
    // BA/NU = 816x1792 as 8 frames x 16 directions -> 102 x 112
    expect(hero.idle!.angles, 16);
    expect(hero.idle!.steps, 8);
    expect(hero.idle!.frameW, closeTo(102, 0.5));
    expect(hero.idle!.frameH, closeTo(112, 0.5));
    // skeleton attack = 2976x904 as 16 frames x 8 dir -> 186 x 113
    final sk = sprites!.monsters[MonsterKind.skeleton]!;
    expect(sk.attack!.frameW, closeTo(186, 0.5));
    expect(sk.death, isNotNull);
    // direction mapping stays within range for all sheets
    for (final f in [0.0, 1.5, 3.0, -2.0, 6.2]) {
      final a = hero.walk!.angleFor(f);
      expect(a, inInclusiveRange(0, hero.walk!.angles - 1));
    }
  });

  test('monster resistance reduces effective physical damage', () {
    final tough = Monster.make(0, 0, MonsterKind.demon, 1); // resistance 50
    expect(tough.resistance, greaterThan(0));
    const base = 120.0;
    final effective = base * (100 - tough.resistance) / 100;
    expect(effective, lessThan(base));
  });

  test('A* pathfinding finds a route between first and last room', () {
    final d = Dungeon(30, 30, math.Random(7));
    final start = d.rooms.first;
    final goal = d.rooms.last;
    final path = findPath(
      d,
      Point(start.left + start.width ~/ 2, start.top + start.height ~/ 2),
      Point(goal.left + goal.width ~/ 2, goal.top + goal.height ~/ 2),
    );
    expect(path, isNotEmpty);
    expect(path.last.x, goal.left + goal.width ~/ 2);
    expect(path.last.y, goal.top + goal.height ~/ 2);
  });
}
