// The world id / dimension key guard for CC:Tweaked.
//
// `World.getId()` is the world id (the folder name, `world`); `World.getDimension()` is the
// dimension key (`minecraft:overworld`). A computer's `ComputerLocation.world` is a **world id**:
// every producer (`world_computers.dart`, `world_turtles.dart`) passes `world.getId()`, and the
// block entity store it is matched against is keyed by it. A dimension key in that field would
// never match, and a world id where a dimension is expected would never match a dimension.
//
// The saved records and the turtle brain import the host API, so they cannot be loaded on the VM;
// the guard pins the two defaults, which are the only places a dimension key could creep in.
import 'dart:io';

import 'package:test/test.dart';

String _lineAt(String file, String marker) {
  final source = File(file).readAsStringSync();
  final index = source.indexOf(marker);
  expect(index, isNot(-1), reason: 'marker `$marker` not found in $file');
  return source.substring(index, source.indexOf('\n', index));
}

void main() {
  test('a saved location without a world falls back to a world id', () {
    // Hand-edited or truncated `computers.json`: the field is a world id, so the fallback has the
    // folder-name shape (`world`), not `minecraft:overworld`.
    final line = _lineAt('lib/src/plugin/records.dart', "json['world'] is String");
    expect(line, contains(": 'world'"));
    expect(line, isNot(contains('minecraft:')));
  });

  test('a turtle brain starts on a world id, not a dimension key', () {
    final line = _lineAt('lib/src/turtle/brain.dart', 'String worldId =');
    expect(line, contains("'world'"));
    expect(line, isNot(contains('minecraft:')));
  });

  test('a turtle compares its world id with a world id', () {
    // `playerWorld.getId() == _brain.worldId`: both sides are folder names.
    final source = File('lib/src/plugin/world_turtles.dart').readAsStringSync();
    expect(source, contains('playerWorld.getId() == _brain.worldId'));
  });
}
