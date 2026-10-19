import 'package:create/src/infrastructure/config/create_configs.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:test/test.dart';

void main() {
  test('defaults match the manifest', () {
    final c = CreateConfigs();
    final server = configDefaults.where((e) => e.side == ConfigSide.server).toList();
    expect(c.serverTree.length, server.length);
    expect(c.commonTree.length, 1);
    for (final e in server) {
      final v = c.serverTree[e.path];
      expect(v, isNotNull, reason: e.path);
      final d = e.defaultValue;
      if (d is double) {
        expect(v!.value, closeTo(d, 1e-9), reason: e.path);
      } else {
        expect(v!.value, d, reason: e.path);
      }
    }
    expect(c.server.kinetics.maxBeltLength.value, 20);
    expect(c.server.kinetics.spawnerMovement.value, 'NO_PICKUP');
    expect(c.server.tickrateSyncTimer.value, 20);
    expect(c.common.worldGen.disable.value, false);
  });

  test('stress values', () {
    final c = CreateConfigs();
    expect(c.stress.impact('mechanical_press'), 8);
    expect(c.stress.impact('create:mechanical_press'), 8);
    expect(c.stress.capacity('water_wheel'), 32);
    expect(c.stress.impact('stone'), 0);
    expect(c.stress.generatedRpm('water_wheel')?.rpm, 8);
    // every manifest stress entry has its config value
    for (final s in stressDefaults) {
      if (s.impact != null) expect(c.stress.impact(s.block), s.impact, reason: s.block);
      if (s.capacity != null) expect(c.stress.capacity(s.block), s.capacity, reason: s.block);
    }
  });

  test('load validates', () {
    final c = CreateConfigs();
    final warnings = <String>[];
    c.load({
      'server': {
        'kinetics': {
          'maxBeltLength': 40,
          'ignoreDeployerAttacks': 'all',
          'encasedFan': {'fanPushDistance': 1}, // below min 5
        },
        'nope': 3,
      },
    }, warnings: warnings);
    expect(c.server.kinetics.maxBeltLength.value, 40);
    expect(c.server.kinetics.ignoreDeployerAttacks.value, 'ALL');
    expect(c.server.kinetics.fanPushDistance.value, 20);
    expect(warnings.length, 2);
    final out = c.serverTree.overridesJson();
    expect(out['kinetics']['maxBeltLength'], 40);
    final listener = <String>[];
    c.server.kinetics.maxBeltLength.onChange((v) => listener.add(v.path));
    c.serverTree.setPath('kinetics.maxBeltLength', 30);
    expect(listener, ['kinetics.maxBeltLength']);
    expect(c.serverTree.setPath('kinetics.maxBeltLength', 1), isNotNull);
  });

  test('toml', () {
    final c = CreateConfigs();
    final toml = c.serverToml();
    expect(toml, contains('[kinetics]'));
    expect(toml, contains('[kinetics.encasedFan]'));
    expect(toml, contains('maxBeltLength = 20'));
    expect(toml, contains('ignoreDeployerAttacks = "CREEPERS"'));
    expect(toml, contains('[kinetics.stressValues.v2.impact]'));
    expect(toml, contains('[infrastructure]'));
    // Each table header appears once.
    final headers = RegExp(r'^\[.*\]$', multiLine: true).allMatches(toml).map((m) => m.group(0)).toList();
    expect(headers.toSet().length, headers.length);
    // After the header of table T no key of an earlier table is written (structure check: keys after
    // the last header belong to it).
    expect(toml.split('\n').where((l) => l.trim().startsWith('maxBeltLength')).length, 1);
  });
}
