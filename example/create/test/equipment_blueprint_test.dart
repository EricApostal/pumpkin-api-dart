import 'package:create/src/equipment/blueprint/blueprint_geometry.dart';
import 'package:create/src/equipment/model/dir.dart';
import 'package:test/test.dart';

void main() {
  test('size 1 on a north wall', () {
    const g = BlueprintGeometry(direction: Dir.north, verticalOrientation: Dir.down, size: 1, blockPos: (0, 0, 0));
    final p = g.entityPosition;
    expect(p.$1, 0.5);
    expect(p.$3, closeTo(0.96875, 1e-9));
    final b = g.boundingBox;
    expect(b.$1, closeTo(0, 1e-9));
    expect(b.$4, closeTo(1, 1e-9));
    expect(b.$6 - b.$3, closeTo(1 / 16, 1e-9));
    expect(g.rotation, (180.0, 0.0));
    expect(g.supportPositions, [(0, 0, 1)]);
  });

  test('size 2 shifts by half a block up and sideways', () {
    const g = BlueprintGeometry(direction: Dir.south, verticalOrientation: Dir.down, size: 2, blockPos: (10, 5, 10));
    final b = g.boundingBox;
    expect(b.$4 - b.$1, closeTo(2, 1e-9));
    expect(b.$5 - b.$2, closeTo(2, 1e-9));
    // south facing: counter clockwise is east, shifted by +0.5, and up by +0.5
    expect((b.$1 + b.$4) / 2, closeTo(11, 1e-9));
    expect((b.$2 + b.$5) / 2, closeTo(6, 1e-9));
    expect(g.supportPositions.length, 4);
  });

  test('size 3 covers 3 by 3 blocks', () {
    const g = BlueprintGeometry(direction: Dir.east, verticalOrientation: Dir.down, size: 3, blockPos: (0, 0, 0));
    expect(g.supportPositions.length, 9);
    expect(g.supportPositions.toSet().length, 9);
    expect(g.supportPositions.every((p) => p.$1 == -1), isTrue);
    expect(g.coveredBlocks.length, 9);
    expect(g.rotation, (270.0, 0.0));
  });

  test('on the floor the orientation sets the yaw', () {
    const g = BlueprintGeometry(direction: Dir.up, verticalOrientation: Dir.east, size: 1, blockPos: (0, 0, 0));
    expect(g.rotation, (180 + 270.0, -90.0));
    final b = g.boundingBox;
    expect(b.$5 - b.$2, closeTo(1 / 16, 1e-9));
    const down = BlueprintGeometry(direction: Dir.down, verticalOrientation: Dir.north, size: 1, blockPos: (0, 0, 0));
    expect(down.rotation.$2, 90.0);
  });

  test('sections of a 3 by 3 blueprint', () {
    const g = BlueprintGeometry(direction: Dir.south, verticalOrientation: Dir.down, size: 3, blockPos: (0, 0, 0));
    // the centre of the entity is section 4 (x = 1, y = 1)
    expect(g.sectionAt((0, 0, 0), yRot: 0, xRot: 0), 4);
    // lower left corner of the plane
    expect(g.sectionAt((-1.4, -1.4, 0), yRot: 0, xRot: 0), 0);
    expect(g.sectionAt((1.4, 1.4, 0), yRot: 0, xRot: 0), 8);
    const one = BlueprintGeometry(direction: Dir.south, verticalOrientation: Dir.down, size: 1, blockPos: (0, 0, 0));
    expect(one.sectionAt((0.3, 0.2, 0), yRot: 0, xRot: 0), 0);
  });

  test('placement orientation', () {
    expect(blueprintPlacementFor(Dir.north, Dir.east).vertical, Dir.down);
    expect(blueprintPlacementFor(Dir.up, Dir.east).vertical, Dir.east);
  });
}
