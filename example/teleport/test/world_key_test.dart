// The world key guard for Teleport.
//
// `World.getName()` is the world id (the folder name, `world`); `World.getDimension()` is the
// dimension key (`minecraft:overworld`). The host resolves either one for `Server.getWorldByName`,
// so swapping them never throws: a saved home, warp or spawn would just resolve to a different
// world, or to none at all.
//
// A saved place takes its `Location.world` from `_locationOf`/`_spawnLocation`, which run against
// the host `Player`/`World` resources a unit test cannot build, so this guard pins the expression
// at each site instead.
import 'dart:io';

import 'package:test/test.dart';

/// The lines around the first [marker] in [file], at most one.
String _around(String file, String marker) {
  final source = File(file).readAsStringSync();
  final index = source.indexOf(marker);
  expect(index, isNot(-1), reason: 'marker `$marker` not found in $file');
  final start = source.lastIndexOf('\n', index) + 1;
  final next = source.indexOf('\n', index + marker.length);
  return source.substring(start, next < 0 ? source.length : next);
}

void main() {
  test('a place saved at a player carries the world id, not a dimension key', () {
    // `_locationOf`: `World.getName()` is the folder name (`world`), which is unique per world:
    // the dimension key would be ambiguous once two worlds share a dimension.
    final line = _around('bin/main.dart', 'world: player.getWorld()');
    expect(line, contains('player.getWorld().getName()'));
    expect(line, isNot(contains('getDimension()')));
  });

  test('the spawn fallback saves the world it read the spawn from', () {
    final line = _around('bin/main.dart', 'world: world.getName()');
    expect(line, contains('world.getName()'));
    expect(line, isNot(contains('getDimension()')));
  });

  test('a teleport request checks the mover for the cooldown bypass', () {
    // `_accept`: the player who moves is the one whose cooldown is enforced, so their own
    // permission decides whether the wait applies, not the answering player's.
    final line = _around('bin/main.dart', 'if (!await mover.hasPermission');
    expect(line, contains('node: Perm.bypassCooldown'));
    expect(line, isNot(contains('sender.hasPermission')));
  });
}