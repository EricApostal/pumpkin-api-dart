// Registration of custom blocks, without host imports: the block model, the
// state id computation of `docs/block-registry.md`, the host's validation
// rules, the interface the host binding implements, and the checks a plugin
// runs after registering. `block_registry.dart` connects it to the generated
// bindings.
import 'dart:math' as math;

/// Thrown when a block definition is invalid, the host refuses a block or tag,
/// or an expectation about the registry does not hold.
final class BlockRegistryException implements Exception {
  final String message;

  const BlockRegistryException(this.message);

  @override
  String toString() => 'BlockRegistryException: $message';
}

/// The six world directions of a [ConnectRule]. `north` is `-z`.
enum ConnectDirection { north, south, east, west, up, down }

/// What a neighbour has to be to make a boolean property true.
sealed class ConnectTarget {
  const ConnectTarget();

  /// A block of the same custom block.
  const factory ConnectTarget.sameBlock() = ConnectSameBlock;

  /// A block with this key (`minecraft:` is optional for vanilla blocks).
  const factory ConnectTarget.block(String key) = ConnectBlock;

  /// A block in this tag, `namespace:path`.
  const factory ConnectTarget.tag(String tag) = ConnectTag;
}

/// A block of the same custom block.
final class ConnectSameBlock extends ConnectTarget {
  const ConnectSameBlock();

  @override
  String toString() => 'same-block';
}

/// A block with the key [key].
final class ConnectBlock extends ConnectTarget {
  final String key;

  const ConnectBlock(this.key);

  @override
  String toString() => 'block($key)';
}

/// A block in the tag [tag].
final class ConnectTag extends ConnectTarget {
  final String tag;

  const ConnectTag(this.tag);

  @override
  String toString() => 'tag($tag)';
}

/// Sets the boolean property [property] to whether the neighbour in
/// [direction] matches [target], like glass panes, fences and chorus plants
/// do. The server applies it when the block is placed and whenever that
/// neighbour changes.
final class ConnectRule {
  final String property;
  final ConnectDirection direction;
  final ConnectTarget target;

  const ConnectRule({
    required this.property,
    required this.direction,
    this.target = const ConnectTarget.sameBlock(),
  });
}

/// A block state property: a name and the values it can have, in the order
/// that numbers the states (`true` before `false`, integers from the minimum
/// to the maximum, enum values as listed).
final class BlockProperty {
  /// Lowercase `a-z 0-9 _`.
  final String name;

  final BlockPropertyKind kind;

  const BlockProperty._(this.name, this.kind);

  /// `true` and `false`, in this order.
  const BlockProperty.boolean(String name) : this._(name, const BoolKind());

  /// The integers from [min] to [max] (inclusive, 0 to 255).
  BlockProperty.intRange(String name, int min, int max)
    : this._(name, IntRangeKind(min, max));

  /// The listed [values], lowercase `a-z 0-9 _`, in this order.
  BlockProperty.enumeration(String name, List<String> values)
    : this._(name, EnumKind(List.unmodifiable(values)));

  /// How many values the property has.
  int get valueCount => kind.valueCount;

  /// The values as the host spells them (`true`, `3`, `north`), in order.
  List<String> get values => kind.values;

  /// The position of [value] in [values], or `null` if it is not one.
  int? valueIndex(String value) => kind.valueIndex(value);

  bool get isBoolean => kind is BoolKind;

  @override
  String toString() => '$name: $kind';
}

/// The values a [BlockProperty] can have.
sealed class BlockPropertyKind {
  const BlockPropertyKind();

  int get valueCount;
  List<String> get values;
  int? valueIndex(String value);
}

/// `true` (index 0) and `false` (index 1).
final class BoolKind extends BlockPropertyKind {
  const BoolKind();

  @override
  int get valueCount => 2;

  @override
  List<String> get values => const ['true', 'false'];

  @override
  int? valueIndex(String value) => switch (value) {
    'true' => 0,
    'false' => 1,
    _ => null,
  };

  @override
  String toString() => 'boolean';
}

/// The integers [min] to [max]; the index of a value is `value - min`.
final class IntRangeKind extends BlockPropertyKind {
  final int min;
  final int max;

  const IntRangeKind(this.min, this.max);

  @override
  int get valueCount => max >= min ? max - min + 1 : 0;

  @override
  List<String> get values => [for (var v = min; v <= max; v++) '$v'];

  @override
  int? valueIndex(String value) {
    final parsed = int.tryParse(value);
    // The host parses a u8: no sign, no whitespace.
    if (parsed == null || value != '$parsed' || parsed < min || parsed > max) {
      return null;
    }
    return parsed - min;
  }

  @override
  String toString() => 'int $min..$max';
}

/// The listed values; the index of a value is its position.
final class EnumKind extends BlockPropertyKind {
  @override
  final List<String> values;

  const EnumKind(this.values);

  @override
  int get valueCount => values.length;

  @override
  int? valueIndex(String value) {
    final index = values.indexOf(value);
    return index < 0 ? null : index;
  }

  @override
  String toString() => 'enum ${values.join('|')}';
}

/// An axis aligned box in block units, `0..1` is the block itself.
final class BlockBox {
  final double minX, minY, minZ, maxX, maxY, maxZ;

  const BlockBox(
    this.minX,
    this.minY,
    this.minZ,
    this.maxX,
    this.maxY,
    this.maxZ,
  );

  /// The whole block.
  static const unit = BlockBox(0, 0, 0, 1, 1, 1);
}

/// A collision or selection shape.
sealed class BlockShape {
  const BlockShape();

  /// No shape. Entities and items pass through, a ray goes through.
  static const BlockShape empty = EmptyShape();

  /// The whole block.
  static const BlockShape fullCube = FullCubeShape();

  /// A union of boxes, at most 64.
  const factory BlockShape.boxes(List<BlockBox> boxes) = BoxesShape;
}

final class EmptyShape extends BlockShape {
  const EmptyShape();
}

final class FullCubeShape extends BlockShape {
  const FullCubeShape();
}

final class BoxesShape extends BlockShape {
  final List<BlockBox> boxes;

  const BoxesShape(this.boxes);
}

/// What breaking the block drops. Nothing drops when the tool is not correct
/// for a block that requires the correct tool.
sealed class BlockDrops {
  const BlockDrops();

  /// One item of the item linked with `setBlockItem`.
  static const BlockDrops selfItem = DropsSelfItem();

  static const BlockDrops nothing = DropsNothing();

  /// The loot table with this key, for example `namespace:blocks/name`.
  const factory BlockDrops.lootTable(String key) = DropsLootTable;
}

final class DropsSelfItem extends BlockDrops {
  const DropsSelfItem();
}

final class DropsNothing extends BlockDrops {
  const DropsNothing();
}

final class DropsLootTable extends BlockDrops {
  final String key;

  const DropsLootTable(this.key);
}

/// A block to add to the host's block registry (`block-definition` in
/// `block-registry.wit`).
final class BlockDefinition {
  /// `namespace:path`, lowercase, `a-z 0-9 _ - .` (and `/` in the path). The
  /// `minecraft` namespace is reserved.
  final String key;

  /// State properties, at most 32 and 16384 states in total. Their order is
  /// irrelevant for the state numbering (see [BlockStateLayout]).
  final List<BlockProperty> properties;

  /// Values of the default state. A property that is not listed gets its
  /// **first** value (`true` for a boolean): list the ones that start `false`.
  final Map<String, String> defaultState;

  /// Time to mine, -1 for unbreakable.
  final double hardness;
  final double blastResistance;

  /// Vanilla `requiresCorrectToolForDrops()`. Which tool is correct comes from
  /// the block [tags] and the tool rules of the held item.
  final bool requiresCorrectTool;

  /// Name of a vanilla sound type (`stone`, `amethyst`); clients choose the
  /// sounds, the server keeps the name.
  final String soundType;

  /// Light level 0 to 15 that every state emits.
  final int luminance;

  /// Vanilla `canOcclude`, false for `noOcclusion()`.
  final bool canOcclude;

  /// Vanilla `isSuffocating`: a full block that is suffocating hurts an entity
  /// whose head is inside it.
  final bool suffocating;

  /// Whether a block placed against it replaces it, like grass does.
  final bool replaceable;

  /// Map colour id, 0 for none.
  final int mapColor;
  final BlockShape collisionShape;
  final BlockShape selectionShape;

  /// Boolean properties that follow the neighbours, one rule per property.
  final List<ConnectRule> connectRules;
  final BlockDrops drops;

  /// Block tags to join, `namespace:path`.
  final List<String> tags;

  const BlockDefinition({
    required this.key,
    this.properties = const [],
    this.defaultState = const {},
    required this.hardness,
    required this.blastResistance,
    this.requiresCorrectTool = false,
    this.soundType = 'stone',
    this.luminance = 0,
    this.canOcclude = true,
    this.suffocating = true,
    this.replaceable = false,
    this.mapColor = 0,
    this.collisionShape = BlockShape.fullCube,
    this.selectionShape = BlockShape.fullCube,
    this.connectRules = const [],
    this.drops = BlockDrops.selfItem,
    this.tags = const [],
  });

  /// The numbering of this block's states.
  BlockStateLayout get layout => BlockStateLayout(this);

  /// How many states the block has (the product of the value counts).
  int get stateCount => layout.stateCount;

  /// The problems the host would reject this definition for (empty if it
  /// is valid). Mirrors `normalize` in Pumpkin's
  /// `crates/pumpkin-data/src/block_registry.rs`, in the same order, so the
  /// first message is the one the host would give.
  List<String> validate() => BlockRegistryChecks.validate(this);

  /// Throws a [BlockRegistryException] if [validate] finds a problem.
  void check() {
    final issues = validate();
    if (issues.isNotEmpty) {
      throw BlockRegistryException(
        'Invalid block definition for `$key`:\n  ${issues.join('\n  ')}',
      );
    }
  }

  @override
  String toString() => 'BlockDefinition($key, ${properties.length} properties)';
}

/// How the host numbers the states of a block, as `docs/block-registry.md`
/// specifies it (vanilla's `StateDefinition`):
///
/// 1. the properties are sorted by name (byte order),
/// 2. the first is the most significant, the last one changes fastest,
/// 3. the values of a property are indexed in declaration order: `true` = 0,
///    `false` = 1, integers `value - min`, enums by position.
///
/// `state index = sum(valueIndex[i] * stride[i])`, with the stride of a
/// property the product of the value counts of the ones after it; the state id
/// is the block's base state id plus the index.
final class BlockStateLayout {
  /// The properties in numbering order (sorted by name).
  final List<BlockProperty> properties;

  /// The strides, parallel to [properties].
  final List<int> strides;

  /// The number of states.
  final int stateCount;

  /// The values of the default state, parallel to [properties], as value
  /// indices (the first value for a property the definition leaves out).
  final List<int> defaultValueIndices;

  factory BlockStateLayout(BlockDefinition definition) {
    final sorted = [...definition.properties]
      ..sort((a, b) => a.name.compareTo(b.name));
    final strides = List<int>.filled(sorted.length, 1);
    var stride = 1;
    for (var i = sorted.length - 1; i >= 0; i--) {
      strides[i] = stride;
      stride *= sorted[i].valueCount;
    }
    final defaults = [
      for (final property in sorted)
        definition.defaultState[property.name] == null
            ? 0
            : property.valueIndex(definition.defaultState[property.name]!) ?? 0,
    ];
    return BlockStateLayout._(sorted, strides, stride, defaults);
  }

  const BlockStateLayout._(
    this.properties,
    this.strides,
    this.stateCount,
    this.defaultValueIndices,
  );

  /// The names in numbering order.
  List<String> get propertyNames => [for (final p in properties) p.name];

  /// The index of the default state (what a plain placement uses).
  int get defaultStateIndex {
    var index = 0;
    for (var i = 0; i < properties.length; i++) {
      index += defaultValueIndices[i] * strides[i];
    }
    return index;
  }

  /// The state index (`0 ..< stateCount`) of the state with [values] (property
  /// name to value). Properties that are not listed have their default value,
  /// like in `get-state-id`. Throws an [ArgumentError] for an unknown
  /// property or value (the host answers `none`).
  int indexOf(Map<String, String> values) {
    final byName = {
      for (var i = 0; i < properties.length; i++) properties[i].name: i,
    };
    final chosen = [...defaultValueIndices];
    for (final entry in values.entries) {
      final position = byName[entry.key];
      if (position == null) {
        throw ArgumentError.value(
          entry.key,
          'values',
          'is not a property of this block',
        );
      }
      final index = properties[position].valueIndex(entry.value);
      if (index == null) {
        throw ArgumentError.value(
          entry.value,
          'values',
          'is not a value of the property `${entry.key}`',
        );
      }
      chosen[position] = index;
    }
    var index = 0;
    for (var i = 0; i < properties.length; i++) {
      index += chosen[i] * strides[i];
    }
    return index;
  }

  /// The state id of the state with [values] for a block whose first state is
  /// [baseStateId].
  int stateId(int baseStateId, Map<String, String> values) =>
      baseStateId + indexOf(values);

  /// The property values of the state with index [stateIndex], by name.
  Map<String, String> valuesAt(int stateIndex) {
    if (stateIndex < 0 || stateIndex >= stateCount) {
      throw RangeError.range(stateIndex, 0, stateCount - 1, 'stateIndex');
    }
    return {
      for (var i = 0; i < properties.length; i++)
        properties[i].name: properties[i]
            .values[(stateIndex ~/ strides[i]) % properties[i].valueCount],
    };
  }
}

/// A block and its network ids, as the host reports them.
final class RegisteredBlock {
  /// The full resource location.
  final String key;

  /// The block id.
  final int id;

  /// The id of the first state, the states follow in state order.
  final int baseStateId;
  final int stateCount;

  /// The item linked with `setBlockItem`, if any.
  final int? itemId;

  const RegisteredBlock({
    required this.key,
    required this.id,
    required this.baseStateId,
    required this.stateCount,
    this.itemId,
  });

  @override
  bool operator ==(Object other) =>
      other is RegisteredBlock &&
      other.key == key &&
      other.id == id &&
      other.baseStateId == baseStateId &&
      other.stateCount == stateCount &&
      other.itemId == itemId;

  @override
  int get hashCode => Object.hash(key, id, baseStateId, stateCount, itemId);

  @override
  String toString() =>
      '$key id=$id states=$baseStateId+$stateCount item=${itemId ?? '-'}';
}

/// The host's block registry as plain Dart: what `block-registry.wit` offers.
/// Implemented over the generated bindings by `BlockRegistries.host`, and by
/// fakes in tests.
abstract interface class BlockRegistryBackend {
  /// Registers [block] and returns its id. Throws a [BlockRegistryException]
  /// for an invalid definition or key, a different definition for a known key,
  /// a missing `registry.blocks` permission, or when registration is closed.
  /// Registering the same definition again returns the existing id.
  int register(BlockDefinition block);

  /// Adds [entries] (block keys or `#tag` references) to the block tag [tag],
  /// creating it. Same restrictions as [register].
  void registerTag(String tag, List<String> entries);

  /// Makes the custom item [itemKey] the item of the custom block [blockKey]:
  /// using it places the block, and the block drops it with
  /// [BlockDrops.selfItem]. Both have to be registered. Repeating a link is
  /// fine.
  void setBlockItem(String itemKey, String blockKey);

  /// The id of a block (`minecraft:` prefix optional), or `null`.
  int? idOf(String key);

  /// The full resource location of the block with [id], or `null`.
  String? keyOf(int id);

  /// The number of vanilla blocks; also the id of the first custom block.
  int get vanillaBlockCount;

  /// The number of vanilla block states; also the first state id of the first
  /// custom block.
  int get vanillaStateCount;

  /// The state id of the block's state with [properties] (unlisted ones have
  /// their default value), or `null` for an unknown block, property or value.
  int? stateId(String block, Map<String, String> properties);

  /// All custom blocks in id order.
  List<RegisteredBlock> get registeredBlocks;
}

/// The host's validation, checks on the ids it reports, and key rules.
abstract final class BlockRegistryChecks {
  static const maxStatesPerBlock = 16384;
  static const maxProperties = 32;
  static const maxEnumValues = 256;
  static const maxBoxes = 64;
  static const maxLuminance = 15;

  /// The limit of the host's `u16` ids: block ids and state ids.
  static const maxIds = 65536;

  static final RegExp _namespace = RegExp(r'^[a-z0-9_.\-]+$');
  static final RegExp _path = RegExp(r'^[a-z0-9_.\-/]+$');
  static final RegExp _identifier = RegExp(r'^[a-z0-9_]+$');

  /// Whether [key] is a valid custom block key, with the host's rules.
  static bool isValidKey(String key) {
    final colon = key.indexOf(':');
    if (colon < 0) return false;
    final namespace = key.substring(0, colon);
    final path = key.substring(colon + 1);
    return namespace != 'minecraft' &&
        _namespace.hasMatch(namespace) &&
        _path.hasMatch(path);
  }

  /// The problems with [definition], in the order the host checks them.
  static List<String> validate(BlockDefinition definition) {
    final issues = <String>[];
    final key = definition.key;

    final colon = key.indexOf(':');
    if (colon < 0 ||
        !_namespace.hasMatch(key.substring(0, colon)) ||
        !_path.hasMatch(key.substring(colon + 1))) {
      issues.add(
        'The key `$key` is not a valid resource location (`namespace:path`, '
        'lowercase `a-z 0-9 _ - .`, and `/` in the path).',
      );
    } else if (key.substring(0, colon) == 'minecraft') {
      issues.add('The key `$key` is in the reserved `minecraft` namespace.');
    }

    if (!definition.hardness.isFinite || definition.hardness < -1) {
      issues.add(
        'hardness must be finite and at least -1 (was ${definition.hardness}).',
      );
    }
    if (!definition.blastResistance.isFinite ||
        definition.blastResistance < 0) {
      issues.add(
        'blast resistance must be finite and not negative (was ${definition.blastResistance}).',
      );
    }
    if (definition.luminance < 0 || definition.luminance > maxLuminance) {
      issues.add('luminance is 0 to 15 (was ${definition.luminance}).');
    }
    if (!_identifier.hasMatch(definition.soundType)) {
      issues.add(
        "sound type must be a lowercase name like 'stone' (was `${definition.soundType}`).",
      );
    }
    if (definition.mapColor < 0 || definition.mapColor > 255) {
      issues.add('map color is 0 to 255 (was ${definition.mapColor}).');
    }
    _checkShape('collision shape', definition.collisionShape, issues);
    _checkShape('selection shape', definition.selectionShape, issues);

    final properties = definition.properties;
    if (properties.length > maxProperties) {
      issues.add('more than $maxProperties properties (${properties.length}).');
    }
    final names = <String>{};
    var states = 1;
    var tooMany = false;
    for (final property in [
      ...properties,
    ]..sort((a, b) => a.name.compareTo(b.name))) {
      if (!_identifier.hasMatch(property.name)) {
        issues.add(
          'property name `${property.name}` must be lowercase a-z 0-9 _.',
        );
      }
      if (!names.add(property.name)) {
        issues.add('property `${property.name}` is listed twice.');
      }
      switch (property.kind) {
        case BoolKind():
          break;
        case IntRangeKind(:final min, :final max):
          if (min < 0 || max > 255) {
            issues.add(
              'property `${property.name}`: integers are 0 to 255 (u8).',
            );
          }
          if (min > max) {
            issues.add(
              'property `${property.name}` has a minimum above its maximum.',
            );
          }
        case EnumKind(:final values):
          if (values.isEmpty || values.length > maxEnumValues) {
            issues.add(
              'property `${property.name}` needs 1 to $maxEnumValues values.',
            );
          }
          for (var i = 0; i < values.length; i++) {
            if (!_identifier.hasMatch(values[i])) {
              issues.add(
                'value `${values[i]}` of property `${property.name}` must be lowercase a-z 0-9 _.',
              );
            }
            if (values.sublist(0, i).contains(values[i])) {
              issues.add(
                'value `${values[i]}` of property `${property.name}` is listed twice.',
              );
            }
          }
      }
      if (!tooMany) {
        states = math.min(states * math.max(property.valueCount, 0), 1 << 32);
        if (states > maxStatesPerBlock) {
          tooMany = true;
          issues.add(
            'block `$key` would have $states states, the limit is $maxStatesPerBlock.',
          );
        }
      }
    }

    final byName = {for (final p in properties) p.name: p};
    for (final entry in definition.defaultState.entries) {
      final property = byName[entry.key];
      if (property == null) {
        issues.add('default state names unknown property `${entry.key}`.');
      } else if (property.valueIndex(entry.value) == null) {
        issues.add(
          '`${entry.value}` is not a value of property `${property.name}`.',
        );
      }
    }

    final ruled = <String>{};
    for (final rule in definition.connectRules) {
      final property = byName[rule.property];
      if (property == null) {
        issues.add('connect rule names unknown property `${rule.property}`.');
      } else if (!property.isBoolean) {
        issues.add(
          'connect rule property `${rule.property}` is not a boolean.',
        );
      }
      if (!ruled.add(rule.property)) {
        issues.add(
          'property `${rule.property}` has more than one connect rule.',
        );
      }
    }

    if (definition.drops case DropsLootTable(key: '')) {
      issues.add('the loot table key is empty.');
    }

    for (final tag in definition.tags) {
      if (tag.isEmpty || tag == '#') issues.add('a tag name is empty.');
    }
    return issues;
  }

  static void _checkShape(String what, BlockShape shape, List<String> issues) {
    if (shape is! BoxesShape) return;
    if (shape.boxes.length > maxBoxes) {
      issues.add('the $what has more than $maxBoxes boxes.');
    }
    for (final b in shape.boxes) {
      final values = [b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ];
      if (values.any((v) => !v.isFinite)) {
        issues.add('the $what has a box with a value that is not finite.');
      } else if (b.minX > b.maxX || b.minY > b.maxY || b.minZ > b.maxZ) {
        issues.add('the $what has a box with a minimum above its maximum.');
      }
    }
  }

  /// Throws unless the host's vanilla block and state counts are what the
  /// plugin's registry sync was built for: the ids of custom blocks are
  /// `vanillaBlockCount + index` and their states start at `vanillaStateCount`,
  /// and a client numbers them from its own vanilla registry.
  static void checkVanillaCounts(
    BlockRegistryBackend backend, {
    required int expectedBlocks,
    required int expectedStates,
  }) {
    final blocks = backend.vanillaBlockCount;
    if (blocks != expectedBlocks) {
      throw BlockRegistryException(
        'The server has $blocks vanilla blocks, but the registry sync was '
        'built for $expectedBlocks. The ids of custom blocks would not match '
        'what clients are told, so the plugin refuses to continue. Run the '
        'server build this plugin was generated for, or regenerate the '
        'vanilla lists (packages/pumpkin_neoforge: '
        'tool/generate_vanilla_registries.dart).',
      );
    }
    final states = backend.vanillaStateCount;
    if (states != expectedStates) {
      throw BlockRegistryException(
        'The server has $states vanilla block states, but the registry sync '
        'was built for $expectedStates. Clients number the states of custom '
        'blocks after their own vanilla states, so they would disagree with '
        'the server about every state of the custom blocks. Run the server '
        'build this plugin was generated for, or regenerate the vanilla '
        'lists (packages/pumpkin_neoforge: tool/generate_vanilla_registries.dart).',
      );
    }
  }

  /// The ids the host must report for [definitions] registered in this order
  /// after [vanillaBlockCount] blocks and [vanillaStateCount] states.
  static List<RegisteredBlock> expectedEntries(
    List<BlockDefinition> definitions, {
    required int vanillaBlockCount,
    required int vanillaStateCount,
  }) {
    final out = <RegisteredBlock>[];
    var base = vanillaStateCount;
    for (var i = 0; i < definitions.length; i++) {
      final count = definitions[i].stateCount;
      out.add(
        RegisteredBlock(
          key: definitions[i].key,
          id: vanillaBlockCount + i,
          baseStateId: base,
          stateCount: count,
        ),
      );
      base += count;
    }
    return out;
  }

  /// Throws unless [reported] (what the host says about the blocks the plugin
  /// registered, in registration order) has exactly the ids and state ranges
  /// computed from [definitions]: block id `vanillaBlockCount + index`, base
  /// state id = the vanilla states plus the states of the blocks before, and
  /// the state count of the layout. A different start means another plugin
  /// registered blocks first.
  static void checkAssigned({
    required int vanillaBlockCount,
    required int vanillaStateCount,
    required List<BlockDefinition> definitions,
    required List<RegisteredBlock> reported,
  }) {
    final expected = expectedEntries(
      definitions,
      vanillaBlockCount: vanillaBlockCount,
      vanillaStateCount: vanillaStateCount,
    );
    if (reported.length != expected.length) {
      final ours = {for (final e in expected) e.key};
      final others = [
        for (final r in reported)
          if (!ours.contains(r.key)) r.key,
      ];
      throw BlockRegistryException(
        'Registered ${expected.length} blocks, but the host reports '
        '${reported.length} custom blocks'
        '${others.isEmpty ? '' : ' (also ${others.map((k) => '`$k`').join(', ')})'}. '
        'Another plugin has registered blocks: load this plugin first, or '
        'include those blocks in the sync.',
      );
    }
    for (var i = 0; i < expected.length; i++) {
      final want = expected[i];
      final got = reported[i];
      if (got.key != want.key) {
        throw BlockRegistryException(
          'The custom block with index $i is `${got.key}` on the host, but '
          '`${want.key}` was expected. Another plugin has registered blocks '
          'before this one: load this plugin first, or include those blocks '
          'in the sync.',
        );
      }
      if (got.id != want.id) {
        throw BlockRegistryException(
          '`${want.key}` got block id ${got.id}, but the registry sync tells '
          'clients ${want.id} (vanilla blocks: $vanillaBlockCount, '
          'registration index: $i). Another plugin has registered blocks '
          'before this one: load this plugin first, or include those blocks '
          'in the sync.',
        );
      }
      if (got.stateCount != want.stateCount) {
        throw BlockRegistryException(
          '`${want.key}` has ${got.stateCount} states on the host, but its '
          'definition describes ${want.stateCount}.',
        );
      }
      if (got.baseStateId != want.baseStateId) {
        throw BlockRegistryException(
          'The states of `${want.key}` start at id ${got.baseStateId} on the '
          'host, but clients number them from ${want.baseStateId} (vanilla '
          'states: $vanillaStateCount, states of the blocks before: '
          '${want.baseStateId - vanillaStateCount}).',
        );
      }
    }
  }

  /// Throws unless the host's `get-state-id` agrees with the layout for the
  /// states of [definition] (a block that starts at [baseStateId]): every
  /// state if there are at most [maxChecks], else the first, the last, the
  /// default and an even sample. Run it after registering; a disagreement
  /// means the host numbers states differently than the client will.
  static void checkStateIds(
    BlockRegistryBackend backend,
    BlockDefinition definition, {
    required int baseStateId,
    int maxChecks = 4096,
  }) {
    final layout = definition.layout;
    final count = layout.stateCount;
    final indices = <int>{};
    if (count <= maxChecks) {
      indices.addAll([for (var i = 0; i < count; i++) i]);
    } else {
      indices
        ..add(0)
        ..add(count - 1)
        ..add(layout.defaultStateIndex);
      final step = count ~/ maxChecks;
      for (var i = 0; i < count; i += step) {
        indices.add(i);
      }
    }
    for (final index in indices) {
      final values = layout.valuesAt(index);
      final computed = baseStateId + index;
      final reported = backend.stateId(definition.key, values);
      if (reported != computed) {
        throw BlockRegistryException(
          'The state ${_describe(values)} of `${definition.key}` has id '
          '${reported ?? 'none'} on the host, but the client will compute '
          '$computed (index $index from $baseStateId). The host and the '
          'plugin disagree about the state order.',
        );
      }
    }
    final defaultIndex = layout.defaultStateIndex;
    final reportedDefault = backend.stateId(definition.key, const {});
    if (reportedDefault != baseStateId + defaultIndex) {
      throw BlockRegistryException(
        'The default state of `${definition.key}` has id '
        '${reportedDefault ?? 'none'} on the host, but the definition '
        'describes ${baseStateId + defaultIndex}.',
      );
    }
  }

  static String _describe(Map<String, String> values) =>
      '{${values.entries.map((e) => '${e.key}=${e.value}').join(', ')}}';
}
