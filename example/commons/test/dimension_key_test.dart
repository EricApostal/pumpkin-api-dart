// The world id / dimension key guard for the announcements module.
//
// An announcement's `world` is a **dimension key** (`overworld`, `the_nether`,
// `minecraft:the_end` — the `minecraft:` prefix is optional). The host has two strings per world:
// `World.getId()` / `World.getName()` are the world id (the folder name, `world`) and
// `World.getDimension()` the dimension key (`minecraft:overworld`). Comparing the configured
// dimension against the folder name never matches, and the announcement is never shown.
//
// `World` is a host (wasm) resource, so the caller cannot be observed from a unit test; the pure
// matcher below is, and the caller's expression is pinned.
import 'dart:io';

import 'package:commons/src/announcements/model.dart';
import 'package:commons/src/announcements/service.dart';
import 'package:test/test.dart';

Future<bool> _visible({String? world, required String worldName}) => isVisibleTo(
  Announcement(text: 'hi', world: world),
  hasPermission: (_) async => true,
  worldName: worldName,
);

void main() {
  test('the dimension key matches, with or without the namespace', () async {
    expect(await _visible(world: 'overworld', worldName: 'minecraft:overworld'), isTrue);
    expect(await _visible(world: 'minecraft:overworld', worldName: 'minecraft:overworld'), isTrue);
    expect(await _visible(world: 'the_nether', worldName: 'minecraft:the_nether'), isTrue);
  });

  test('a world id is not a dimension key', () async {
    // `World.getId()` of the overworld is `world`: the folder name must not be what the caller
    // passes, or an announcement restricted to `overworld` is never shown.
    expect(await _visible(world: 'overworld', worldName: 'world'), isFalse);
  });

  test('the caller passes the dimension, not the world name', () {
    final source = File('lib/src/announcements/ui.dart').readAsStringSync();
    expect(source, contains('getDimension()'));
    expect(source, isNot(contains('getWorld().getName()')));
  });
}
