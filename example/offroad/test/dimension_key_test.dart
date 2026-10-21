// The world id / dimension key guard for Offroad.
//
// `World.getId()` is the world id (the folder name, `world`); `World.getDimension()` is the
// dimension key (`minecraft:overworld`). `SableLevel.dimensionId` is documented as the key
// (`Level.dimension().identifier().toString()`), and Sable puts it into `/execute in <dimension>`
// suggestions and the `sable:dimension_physics` wire value.
//
// `World` is a host (wasm) resource, so a unit test cannot build one and observe the site; the
// guard pins the expression instead (see `create`'s `test/dimension_key_test.dart` for the full
// audit of the class).
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the offroad SableLevel names its level by dimension key', () {
    final source = File('lib/src/host/offroad_hooks.dart').readAsStringSync();
    final index = source.indexOf('String get dimensionId =>');
    expect(index, isNot(-1), reason: 'the SableLevel adapter is gone; update this guard');
    final line = source.substring(index, source.indexOf('\n', index));
    expect(line, contains('world.getDimension()'));
    expect(line, isNot(contains('world.getId()')));
  });
}
