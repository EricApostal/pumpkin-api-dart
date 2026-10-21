// The world id / dimension key guard for Aeronautics.
//
// `World.getName()` and `World.getId()` are the world id (the folder name, `world`);
// `World.getDimension()` is the dimension key (`minecraft:overworld`). The host resolves both for
// `getWorldByName`, so nothing throws when they are swapped — the code just never matches.
//
// `World` is a host (wasm) resource, so a unit test cannot build one and observe these sites; the
// guard pins the expression at each site instead (see `create`'s `test/dimension_key_test.dart`
// for the full audit of the class).
import 'dart:io';

import 'package:test/test.dart';

/// One audited site: the file, the marker that finds it, and the identifier it must produce.
typedef Site = ({String file, String marker, String mustMatch, String mustNotMatch, String why});

final List<Site> sites = [
  (
    file: 'lib/src/content/items/item_behaviour.dart',
    marker: 'if (world.',
    mustMatch: 'world.getDimension() != overworldDimension',
    mustNotMatch: 'getName()',
    why: 'the cloud-skipper conversion only starts in the overworld: `World.getName()` is the '
        'folder name (`world`), so `getName() != "minecraft:overworld"` was always true and the '
        'conversion never started',
  ),
  (
    file: 'lib/src/host/world_balloon_world.dart',
    marker: 'String get dimensionId =>',
    mustMatch: 'world.getDimension()',
    mustNotMatch: 'getId()',
    why: '`SableLevel.dimensionId` is `Level.dimension().identifier().toString()`: the key goes '
        'into `/execute in <dimension>` suggestions and the `sable:dimension_physics` wire value',
  ),
];

String _around(String source, String marker, {int lines = 6}) {
  final index = source.indexOf(marker);
  if (index < 0) fail('marker not found: $marker');
  final start = source.lastIndexOf('\n', index) + 1;
  var end = start;
  for (var i = 0; i < lines; i++) {
    final next = source.indexOf('\n', end);
    if (next < 0) {
      end = source.length;
      break;
    }
    end = next + 1;
  }
  return source.substring(start, end);
}

void main() {
  test('the balloon world id is not a dimension key', () {
    // `BalloonWorld.id` is the world id (the map key); the dimension is `SableLevel.dimensionId`.
    final source = File('lib/src/hot_air/balloon_world.dart').readAsStringSync();
    expect(source, contains('World.getId()'));
  });

  for (final site in sites) {
    test('${site.file} :: ${site.marker}', () {
      final text = _around(File(site.file).readAsStringSync(), site.marker, lines: 1);
      expect(text, contains(site.mustMatch), reason: '${site.why}\n--- $text');
      expect(text, isNot(contains(site.mustNotMatch)), reason: '${site.why}\n--- $text');
    });
  }
}
