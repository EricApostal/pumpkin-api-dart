import 'package:pumpkin_api/src/block_registry_core.dart';
import 'package:test/test.dart';

const _sides = ['north', 'south', 'east', 'west', 'up', 'down'];

/// The Lonsdaleite wardframe, as the plugin declares it.
BlockDefinition wardframe([String key = 'lonsdaleite:lonsdaleite_wardframe']) =>
    BlockDefinition(
      key: key,
      properties: [for (final s in _sides) BlockProperty.boolean(s)],
      defaultState: {for (final s in _sides) s: 'false'},
      hardness: 5,
      blastResistance: 1200,
      requiresCorrectTool: true,
      soundType: 'amethyst',
      luminance: 7,
      canOcclude: false,
      suffocating: false,
      connectRules: [
        for (final s in _sides)
          ConnectRule(
            property: s,
            direction: ConnectDirection.values.byName(s),
            target: const ConnectTarget.sameBlock(),
          ),
      ],
      tags: ['minecraft:mineable/pickaxe', 'minecraft:needs_diamond_tool'],
    );

/// A host that follows Pumpkin's `DynamicBlockRegistry`: ids from the vanilla
/// counts, and `get-state-id` computed the way `DynamicBlockInfo` does it
/// (start at the default state, change one property at a time by its stride),
/// which is a different path than [BlockStateLayout.indexOf] takes.
final class _FakeHost implements BlockRegistryBackend {
  @override
  final int vanillaBlockCount;
  @override
  final int vanillaStateCount;
  final definitions = <BlockDefinition>[];
  final links = <String, String>{};
  int Function(int)? stateOffset;

  _FakeHost({this.vanillaBlockCount = 1286, this.vanillaStateCount = 35723});

  @override
  int register(BlockDefinition block) {
    block.check();
    final existing = definitions.indexWhere((d) => d.key == block.key);
    if (existing >= 0) return vanillaBlockCount + existing;
    definitions.add(block);
    return vanillaBlockCount + definitions.length - 1;
  }

  @override
  void registerTag(String tag, List<String> entries) {}

  @override
  void setBlockItem(String itemKey, String blockKey) =>
      links[blockKey] = itemKey;

  @override
  int? idOf(String key) {
    final i = definitions.indexWhere((d) => d.key == key);
    return i < 0 ? null : vanillaBlockCount + i;
  }

  @override
  String? keyOf(int id) => null;

  @override
  List<RegisteredBlock> get registeredBlocks {
    final expected = BlockRegistryChecks.expectedEntries(
      definitions,
      vanillaBlockCount: vanillaBlockCount,
      vanillaStateCount: vanillaStateCount,
    );
    return [
      for (final e in expected)
        RegisteredBlock(
          key: e.key,
          id: e.id,
          baseStateId: e.baseStateId,
          stateCount: e.stateCount,
          itemId: links.containsKey(e.key) ? 1700 : null,
        ),
    ];
  }

  @override
  int? stateId(String block, Map<String, String> properties) {
    final i = definitions.indexWhere((d) => d.key == block);
    if (i < 0) return null;
    final d = definitions[i];
    final sorted = [...d.properties]..sort((a, b) => a.name.compareTo(b.name));
    final strides = List<int>.filled(sorted.length, 1);
    var stride = 1;
    for (var k = sorted.length - 1; k >= 0; k--) {
      strides[k] = stride;
      stride *= sorted[k].valueCount;
    }
    int valueIndex(int k, String? value) =>
        sorted[k].valueIndex(value ?? sorted[k].values.first) ?? -1;
    var index = 0;
    for (var k = 0; k < sorted.length; k++) {
      index += valueIndex(k, d.defaultState[sorted[k].name]) * strides[k];
    }
    for (final e in properties.entries) {
      final k = sorted.indexWhere((p) => p.name == e.key);
      if (k < 0) return null;
      final next = sorted[k].valueIndex(e.value);
      if (next == null) return null;
      final old = valueIndex(k, d.defaultState[e.key]);
      index += (next - old) * strides[k];
    }
    final base = registeredBlocks[i].baseStateId;
    return base + index + (stateOffset?.call(index) ?? 0);
  }
}

void main() {
  group('state ids', () {
    final layout = wardframe().layout;

    test(
      'the properties are numbered in sorted order, the first most significant',
      () {
        expect(layout.propertyNames, [
          'down',
          'east',
          'north',
          'south',
          'up',
          'west',
        ]);
        expect(layout.strides, [32, 16, 8, 4, 2, 1]);
        expect(layout.stateCount, 64);
      },
    );

    test('index 0 is all true, index 63 all false (booleans: true = 0)', () {
      final allTrue = {for (final s in _sides) s: 'true'};
      final allFalse = {for (final s in _sides) s: 'false'};
      expect(layout.indexOf(allTrue), 0);
      expect(layout.indexOf(allFalse), 63);
      expect(layout.valuesAt(0), allTrue);
      expect(layout.valuesAt(63), allFalse);
    });

    test('the default state (all false) is index 63', () {
      expect(layout.defaultStateIndex, 63);
      expect(layout.indexOf(const {}), 63);
      expect(layout.stateId(35723, const {}), 35723 + 63);
    });

    test('the example of docs/block-registry.md: east and up true is 45', () {
      expect(layout.indexOf({'east': 'true', 'up': 'true'}), 63 - 16 - 2);
      expect(layout.stateId(35723, {'east': 'true', 'up': 'true'}), 35723 + 45);
    });

    test('matches the manifest block_state: each property one at a time', () {
      expect(layout.indexOf({'down': 'true'}), 63 - 32);
      expect(layout.indexOf({'east': 'true'}), 63 - 16);
      expect(layout.indexOf({'north': 'true'}), 63 - 8);
      expect(layout.indexOf({'south': 'true'}), 63 - 4);
      expect(layout.indexOf({'up': 'true'}), 63 - 2);
      expect(layout.indexOf({'west': 'true'}), 63 - 1);
    });

    test('indexOf and valuesAt are inverse for all 64 states', () {
      for (var i = 0; i < 64; i++) {
        expect(layout.indexOf(layout.valuesAt(i)), i);
      }
    });

    test('the declaration order does not matter', () {
      final shuffled = BlockDefinition(
        key: 'a:b',
        properties: [for (final s in _sides.reversed) BlockProperty.boolean(s)],
        hardness: 1,
        blastResistance: 1,
      );
      expect(shuffled.layout.propertyNames, layout.propertyNames);
      // No default state given: every boolean starts at `true` (index 0), east false adds 16.
      expect(shuffled.layout.indexOf({'east': 'false'}), 16);
    });

    test('mixed kinds: int index is value - min, enums by position', () {
      final d = BlockDefinition(
        key: 'a:mixed',
        properties: [
          BlockProperty.enumeration('shape', ['straight', 'inner', 'outer']),
          BlockProperty.intRange('age', 2, 5),
          const BlockProperty.boolean('lit'),
        ],
        defaultState: {'shape': 'inner', 'age': '3', 'lit': 'false'},
        hardness: 1,
        blastResistance: 1,
      );
      final l = d.layout;
      // sorted: age(4) lit(2) shape(3); strides 6, 3, 1
      expect(l.propertyNames, ['age', 'lit', 'shape']);
      expect(l.strides, [6, 3, 1]);
      expect(l.stateCount, 24);
      expect(l.indexOf({'age': '2', 'lit': 'true', 'shape': 'straight'}), 0);
      expect(
        l.indexOf({'age': '5', 'lit': 'false', 'shape': 'outer'}),
        3 * 6 + 1 * 3 + 2,
      );
      expect(l.defaultStateIndex, 1 * 6 + 1 * 3 + 1);
      expect(() => l.indexOf({'age': '6'}), throwsArgumentError);
      expect(() => l.indexOf({'nope': 'x'}), throwsArgumentError);
    });

    test(
      'a property left out of the default state starts at its first value',
      () {
        final d = BlockDefinition(
          key: 'a:b',
          properties: [const BlockProperty.boolean('lit')],
          hardness: 1,
          blastResistance: 1,
        );
        expect(d.layout.defaultStateIndex, 0);
        expect(d.layout.valuesAt(0), {'lit': 'true'});
      },
    );
  });

  group('validation (the rules of the host)', () {
    BlockDefinition base({
      String key = 'a:b',
      List<BlockProperty> properties = const [],
      Map<String, String> defaultState = const {},
      double hardness = 1,
      double blastResistance = 1,
      int luminance = 0,
      String soundType = 'stone',
      int mapColor = 0,
      BlockShape collision = BlockShape.fullCube,
      List<ConnectRule> rules = const [],
      BlockDrops drops = BlockDrops.selfItem,
    }) => BlockDefinition(
      key: key,
      properties: properties,
      defaultState: defaultState,
      hardness: hardness,
      blastResistance: blastResistance,
      luminance: luminance,
      soundType: soundType,
      mapColor: mapColor,
      collisionShape: collision,
      connectRules: rules,
      drops: drops,
    );

    test('the wardframe is valid', () {
      expect(wardframe().validate(), isEmpty);
      wardframe().check();
    });

    test('keys', () {
      for (final good in ['a:b', 'my_mod:path/to.x-y', 'a-b.c:d']) {
        expect(base(key: good).validate(), isEmpty, reason: good);
        expect(BlockRegistryChecks.isValidKey(good), isTrue);
      }
      for (final bad in [
        'nocolon',
        'A:b',
        'a:B',
        ':b',
        'a:',
        'a b:c',
        'a:b c',
        'a/x:b',
      ]) {
        expect(base(key: bad).validate(), isNotEmpty, reason: bad);
        expect(BlockRegistryChecks.isValidKey(bad), isFalse, reason: bad);
      }
      expect(
        base(key: 'minecraft:thing').validate().single,
        contains('reserved'),
      );
      expect(BlockRegistryChecks.isValidKey('minecraft:thing'), isFalse);
    });

    test('hardness, resistance, luminance, sound, map color', () {
      expect(base(hardness: -1).validate(), isEmpty);
      expect(base(hardness: -1.5).validate(), isNotEmpty);
      expect(base(hardness: double.nan).validate(), isNotEmpty);
      expect(base(hardness: double.infinity).validate(), isNotEmpty);
      expect(base(blastResistance: -0.1).validate(), isNotEmpty);
      expect(base(luminance: 15).validate(), isEmpty);
      expect(base(luminance: 16).validate(), isNotEmpty);
      expect(base(soundType: 'Stone').validate(), isNotEmpty);
      expect(base(soundType: '').validate(), isNotEmpty);
      expect(base(mapColor: 256).validate(), isNotEmpty);
    });

    test('properties', () {
      expect(
        base(
          properties: [
            const BlockProperty.boolean('a'),
            const BlockProperty.boolean('a'),
          ],
        ).validate(),
        contains(contains('listed twice')),
      );
      expect(
        base(properties: [const BlockProperty.boolean('Up')]).validate(),
        isNotEmpty,
      );
      expect(
        base(properties: [BlockProperty.intRange('n', 5, 2)]).validate(),
        isNotEmpty,
      );
      expect(
        base(properties: [BlockProperty.enumeration('e', [])]).validate(),
        isNotEmpty,
      );
      expect(
        base(
          properties: [
            BlockProperty.enumeration('e', ['a', 'a']),
          ],
        ).validate(),
        isNotEmpty,
      );
      expect(
        base(
          properties: [
            BlockProperty.enumeration('e', ['A']),
          ],
        ).validate(),
        isNotEmpty,
      );
      expect(
        base(
          properties: [
            for (var i = 0; i < 33; i++) const BlockProperty.boolean('p'),
          ],
        ).validate(),
        contains(contains('more than 32')),
      );
    });

    test('at most 16384 states', () {
      expect(
        base(
          properties: [
            for (var i = 0; i < 14; i++) BlockProperty.boolean('p$i'),
          ],
        ).validate(),
        isEmpty,
      );
      final issues = base(
        properties: [for (var i = 0; i < 15; i++) BlockProperty.boolean('p$i')],
      ).validate();
      expect(issues.single, contains('32768 states'));
      expect(issues.single, contains('limit is 16384'));
    });

    test('default state', () {
      final props = [
        const BlockProperty.boolean('lit'),
        BlockProperty.intRange('n', 0, 3),
      ];
      expect(
        base(
          properties: props,
          defaultState: {'lit': 'false', 'n': '3'},
        ).validate(),
        isEmpty,
      );
      expect(
        base(properties: props, defaultState: {'x': 'true'}).validate().single,
        contains('unknown property'),
      );
      expect(
        base(properties: props, defaultState: {'n': '4'}).validate().single,
        contains('not a value'),
      );
      expect(
        base(properties: props, defaultState: {'lit': 'yes'}).validate(),
        isNotEmpty,
      );
    });

    test('connect rules', () {
      final props = [
        const BlockProperty.boolean('up'),
        BlockProperty.intRange('n', 0, 3),
      ];
      ConnectRule rule(String p) =>
          ConnectRule(property: p, direction: ConnectDirection.up);
      expect(base(properties: props, rules: [rule('up')]).validate(), isEmpty);
      expect(
        base(properties: props, rules: [rule('zz')]).validate().single,
        contains('unknown property'),
      );
      expect(
        base(properties: props, rules: [rule('n')]).validate().single,
        contains('not a boolean'),
      );
      expect(
        base(
          properties: props,
          rules: [rule('up'), rule('up')],
        ).validate().single,
        contains('more than one'),
      );
    });

    test('shapes, loot table', () {
      expect(
        base(collision: BlockShape.boxes([BlockBox.unit])).validate(),
        isEmpty,
      );
      expect(
        base(
          collision: BlockShape.boxes([
            for (var i = 0; i < 65; i++) BlockBox.unit,
          ]),
        ).validate(),
        isNotEmpty,
      );
      expect(
        base(collision: BlockShape.boxes(const [BlockBox(1, 0, 0, 0, 1, 1)]))
            .validate(),
        isNotEmpty,
      );
      expect(
        base(
          collision: BlockShape.boxes(const [
            BlockBox(0, 0, 0, double.nan, 1, 1),
          ]),
        ).validate(),
        isNotEmpty,
      );
      expect(
        base(drops: const BlockDrops.lootTable('')).validate(),
        isNotEmpty,
      );
      expect(
        base(drops: const BlockDrops.lootTable('a:blocks/x')).validate(),
        isEmpty,
      );
    });

    test('check() reports every problem with the key', () {
      expect(
        () => base(key: 'A:b', luminance: 99).check(),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'message',
            allOf(contains('A:b'), contains('luminance')),
          ),
        ),
      );
    });
  });

  group('checks against the host', () {
    test('the vanilla counts must be the ones the sync was built for', () {
      final host = _FakeHost(vanillaBlockCount: 1200);
      expect(
        () => BlockRegistryChecks.checkVanillaCounts(
          host,
          expectedBlocks: 1286,
          expectedStates: 35723,
        ),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            allOf(contains('1200 vanilla blocks'), contains('for 1286')),
          ),
        ),
      );
      final states = _FakeHost(vanillaStateCount: 35000);
      expect(
        () => BlockRegistryChecks.checkVanillaCounts(
          states,
          expectedBlocks: 1286,
          expectedStates: 35723,
        ),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            allOf(contains('35000 vanilla block states'), contains('35723')),
          ),
        ),
      );
      BlockRegistryChecks.checkVanillaCounts(
        _FakeHost(),
        expectedBlocks: 1286,
        expectedStates: 35723,
      );
    });

    test(
      'ids: block 1286 + index, states from 35723 in registration order',
      () {
        final defs = [wardframe(), wardframe('t:second')];
        final expected = BlockRegistryChecks.expectedEntries(
          defs,
          vanillaBlockCount: 1286,
          vanillaStateCount: 35723,
        );
        expect(expected[0].id, 1286);
        expect(expected[0].baseStateId, 35723);
        expect(expected[0].stateCount, 64);
        expect(expected[1].id, 1287);
        expect(expected[1].baseStateId, 35723 + 64);
      },
    );

    test('accepts what the host reports when it matches', () {
      final host = _FakeHost();
      final def = wardframe();
      host.register(def);
      BlockRegistryChecks.checkAssigned(
        vanillaBlockCount: 1286,
        vanillaStateCount: 35723,
        definitions: [def],
        reported: host.registeredBlocks,
      );
      BlockRegistryChecks.checkStateIds(host, def, baseStateId: 35723);
    });

    test('fails when another plugin registered a block first', () {
      final host = _FakeHost();
      host.register(wardframe('other:first'));
      host.register(wardframe());
      final reported = host.registeredBlocks.sublist(1);
      expect(
        () => BlockRegistryChecks.checkAssigned(
          vanillaBlockCount: 1286,
          vanillaStateCount: 35723,
          definitions: [wardframe()],
          reported: reported,
        ),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            contains('Another plugin'),
          ),
        ),
      );
      expect(
        () => BlockRegistryChecks.checkAssigned(
          vanillaBlockCount: 1286,
          vanillaStateCount: 35723,
          definitions: [wardframe()],
          reported: host.registeredBlocks,
        ),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            contains('other:first'),
          ),
        ),
      );
    });

    test('fails on another id, state count or base state', () {
      final def = wardframe();
      void expectFailure(RegisteredBlock reported, Matcher message) => expect(
        () => BlockRegistryChecks.checkAssigned(
          vanillaBlockCount: 1286,
          vanillaStateCount: 35723,
          definitions: [def],
          reported: [reported],
        ),
        throwsA(
          isA<BlockRegistryException>().having((e) => e.message, 'm', message),
        ),
      );
      expectFailure(
        const RegisteredBlock(
          key: 'lonsdaleite:lonsdaleite_wardframe',
          id: 1290,
          baseStateId: 35723,
          stateCount: 64,
        ),
        contains('got block id 1290'),
      );
      expectFailure(
        const RegisteredBlock(
          key: 'lonsdaleite:lonsdaleite_wardframe',
          id: 1286,
          baseStateId: 35723,
          stateCount: 32,
        ),
        contains('32 states'),
      );
      expectFailure(
        const RegisteredBlock(
          key: 'lonsdaleite:lonsdaleite_wardframe',
          id: 1286,
          baseStateId: 35800,
          stateCount: 64,
        ),
        contains('start at id 35800'),
      );
    });

    test('fails when the host numbers states differently', () {
      final host = _FakeHost();
      final def = wardframe();
      host.register(def);
      BlockRegistryChecks.checkStateIds(host, def, baseStateId: 35723);
      // A host that is off by one for one state.
      host.stateOffset = (index) => index == 45 ? 1 : 0;
      expect(
        () => BlockRegistryChecks.checkStateIds(host, def, baseStateId: 35723),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            allOf(
              contains('east=true'),
              contains('35768'),
              contains('disagree'),
            ),
          ),
        ),
      );
    });

    test('large blocks are sampled', () {
      final def = BlockDefinition(
        key: 'a:big',
        properties: [for (var i = 0; i < 12; i++) BlockProperty.boolean('p$i')],
        hardness: 1,
        blastResistance: 1,
      );
      final host = _FakeHost()..register(def);
      BlockRegistryChecks.checkStateIds(
        host,
        def,
        baseStateId: 35723,
        maxChecks: 100,
      );
    });
  });
}
