import 'package:create/src/equipment/model/dir.dart';
import 'package:create/src/equipment/wrench/wrench_rotation.dart';
import 'package:test/test.dart';

void main() {
  test('pillar axis rotates about the clicked face', () {
    final r = WrenchRotation.rotated({'axis': 'y'}, Dir.north, facing: FacingKind.none);
    // up rotated clockwise about Z -> east, so the axis becomes x
    expect(r['axis'], 'x');
    expect(WrenchRotation.rotated({'axis': 'x'}, Dir.up, facing: FacingKind.none)['axis'], 'z');
    expect(WrenchRotation.rotated({'axis': 'y'}, Dir.up, facing: FacingKind.none)['axis'], 'y');
  });

  test('horizontal facing rotates only on vertical faces', () {
    final p = {'facing': 'north'};
    expect(WrenchRotation.rotated(p, Dir.up, facing: FacingKind.horizontal)['facing'], 'east');
    expect(WrenchRotation.rotated(p, Dir.down, facing: FacingKind.horizontal)['facing'], 'east');
    expect(WrenchRotation.rotated(p, Dir.north, facing: FacingKind.horizontal), p);
  });

  test('horizontal axis toggles', () {
    expect(WrenchRotation.rotated({'axis': 'x'}, Dir.up, facing: FacingKind.none, axisHorizontalOnly: true)['axis'], 'z');
    expect(WrenchRotation.rotated({'axis': 'x'}, Dir.north, facing: FacingKind.none, axisHorizontalOnly: true)['axis'], 'x');
  });

  test('six way facing', () {
    // facing up, click east face: up -> clockwise about X is unchanged for east; about X up->north.
    final r = WrenchRotation.rotated({'facing': 'up'}, Dir.west, facing: FacingKind.sixWay);
    expect(r['facing'], 'north');
    // facing along the clicked axis stays
    expect(WrenchRotation.rotated({'facing': 'up'}, Dir.up, facing: FacingKind.sixWay)['facing'], 'up');
    // and cycles axis_along_first when present
    final c = WrenchRotation.rotated(
      {'facing': 'up', 'axis_along_first': 'false'},
      Dir.up,
      facing: FacingKind.sixWay,
    );
    expect(c['axis_along_first'], 'true');
    // rotating about Y also cycles it
    final d = WrenchRotation.rotated(
      {'facing': 'north', 'axis_along_first': 'false'},
      Dir.up,
      facing: FacingKind.sixWay,
    );
    expect(d['facing'], 'east');
    expect(d['axis_along_first'], 'true');
  });

  test('facing kind from values', () {
    expect(WrenchRotation.facingKindOf(['north', 'south', 'west', 'east']), FacingKind.horizontal);
    expect(WrenchRotation.facingKindOf(['down', 'up', 'north']), FacingKind.sixWay);
    expect(WrenchRotation.facingKindOf(null), FacingKind.none);
  });
}
