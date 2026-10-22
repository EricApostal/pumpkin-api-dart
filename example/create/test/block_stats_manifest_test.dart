// The regression guard on the block data the `CreateBlock` builders read: the 19
// table cloths, the map colours every manifest block names, and the four blocks
// whose Java `lightLevel` is a function of the state.
//
// Pure (the manifest and the `MapColor` table only), so it runs on the VM
// without the host: `manifestBlock`/`createBlockFromManifest` read exactly these
// values, and the metal cloths' stats are the ones a full block was registered
// with before (`0.8/0.8 wool`, no tool) while Java has `1.5/6.0 stone` and
// `3.0/6.0 metal` with a pickaxe.
import 'package:create/src/common/map_colors.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:test/test.dart';

Map<String, ManifestBlock> get _byKey => {for (final b in kBlocks) b.key: b};

const List<String> _dyes = [
  'white',
  'orange',
  'magenta',
  'light_blue',
  'yellow',
  'lime',
  'pink',
  'gray',
  'light_gray',
  'cyan',
  'purple',
  'blue',
  'brown',
  'green',
  'red',
  'black',
];

void main() {
  test('every manifest map colour resolves', () {
    final unknown = <String, String>{};
    for (final block in kBlocks) {
      final color = block.mapColor;
      if (color == 'NONE') continue;
      if (!mapColorIds.containsKey(color)) unknown[block.key] = color;
    }
    expect(unknown, isEmpty, reason: 'unresolved map colours: $unknown');
    // The dye-coloured blocks are the ones that used to fall back to `NONE` (0).
    expect(mapColorIdOf('dye:WHITE'), 8); // MapColor.SNOW
    expect(mapColorIdOf('dye:BLACK'), 29);
    expect(mapColorIdOf('dye:LIME'), 19); // MapColor.COLOR_LIGHT_GREEN
    expect(mapColorIdOf('NETHER'), 35);
  });

  test('the dye-coloured blocks are the 111 the manifest names', () {
    final dyed = [
      for (final b in kBlocks)
        if (b.mapColor.startsWith('dye:')) b.key,
    ];
    expect(dyed.length, 111);
  });

  test('table cloths match Java per colour', () {
    for (final dye in _dyes) {
      final m = _byKey['${dye}_table_cloth']!;
      expect(m.hardness, 0.1, reason: '${m.key} hardness');
      expect(m.blastResistance, 0.1, reason: '${m.key} blast resistance');
      expect(m.requiresCorrectTool, isFalse, reason: '${m.key} tool');
      expect(m.soundType, 'WOOL', reason: '${m.key} sound');
      expect(m.ignitedByLava, isTrue, reason: '${m.key} ignitedByLava');
      expect(m.mapColor, 'dye:${dye.toUpperCase()}', reason: '${m.key} colour');
    }
    const metal = {
      'andesite_table_cloth': ('STONE', 1.5),
      'brass_table_cloth': ('METAL', 3.0),
      'copper_table_cloth': ('COPPER', 3.0),
    };
    metal.forEach((key, soundAndHardness) {
      final (sound, hardness) = soundAndHardness;
      final m = _byKey[key]!;
      expect(m.hardness, hardness, reason: '$key hardness');
      expect(m.blastResistance, 6.0, reason: '$key blast resistance');
      expect(m.requiresCorrectTool, isTrue, reason: '$key tool');
      expect(m.soundType, sound, reason: '$key sound');
      expect(m.ignitedByLava, isFalse, reason: '$key ignitedByLava');
    });
    // The three metal cloths keep `StateDefinition.any()`: no `registerDefaultState`
    // in their Java constructor, so `entity` stays true; the 16 dye cloths
    // register `HAS_BE=false`.
    for (final key in metal.keys) {
      expect(_byKey[key]!.defaultState, {'entity': 'true'}, reason: key);
    }
    expect(_byKey['white_table_cloth']!.defaultState, {'entity': 'false'});
  });

  test('the state-dependent light blocks are the ones with light rules', () {
    // `lightLevel(s -> POWERING ? 15 : 0)`; the registration passes the rule.
    expect(_byKey['rose_quartz_lamp']!.lightLevel, 15);
    for (final key in [
      'blaze_burner',
      'lit_blaze_burner',
      'elevator_contact',
      'rose_quartz_lamp',
    ]) {
      expect(_byKey[key]!.lightDynamic, isTrue, reason: key);
    }
    // Every other block's light is a constant, so no rule may be added for it.
    final dynamic = [
      for (final b in kBlocks)
        if (b.lightDynamic) b.key,
    ]..sort();
    expect(dynamic, [
      'blaze_burner',
      'elevator_contact',
      'lit_blaze_burner',
      'rose_quartz_lamp',
    ]);
  });

  test('the blocks Java lights unlike the rest carry ignitedByLava', () {
    for (final key in [
      'white_seat',
      'black_sail',
      'white_postbox',
      'white_toolbox',
      'white_table_cloth',
    ]) {
      expect(_byKey[key]!.ignitedByLava, isTrue, reason: key);
    }
    // The water wheels, the turntable, the hand crank and the cuckoo clock carry
    // it too (the belt does not: its Java class overrides `isFlammable` only,
    // which is about fire spreading, and its own properties are not ignited).
    for (final key in [
      'water_wheel',
      'large_water_wheel',
      'turntable',
      'hand_crank',
      'cuckoo_clock',
    ]) {
      expect(_byKey[key]!.ignitedByLava, isTrue, reason: key);
    }
    expect(_byKey['belt']!.ignitedByLava, isFalse);
  });
}