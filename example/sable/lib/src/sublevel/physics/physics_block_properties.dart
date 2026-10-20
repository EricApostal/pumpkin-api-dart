// `dev.ryanhcode.sable.physics.config.block_properties`: the physics properties
// of blocks, and the datapack/payload definition that assigns them.
//
// Java keeps these on a mixin field of `BlockState` (`BlockStateMixin`) and
// fills them from `physics_block_properties/*.json`. The port keeps the same
// data, in a table resolved from the block-state string the plot host returns
// (`minecraft:oak_stairs[facing=north,half=bottom]`), with the same rules:
//
// * definitions are applied in **ascending** priority, so a higher priority
//   overwrites a lower one property by property (`PhysicsBlockPropertiesDefinitionLoader.apply`);
// * a definition's `overrides` are applied after its base properties, for the
//   block states whose condition set matches;
// * a property a definition does not mention keeps whatever an earlier
//   definition set, otherwise the type's default.
//
// The wire form of one definition (`physics_property` payload) is the NBT form
// of `PhysicsBlockPropertiesDefinition.CODEC`:
//
// ```json
// { "selector": "minecraft:stone" | "#minecraft:logs",  // string, required
//   "priority": 1000,                                  // int, omitted at 1000
//   "properties": { "sable:mass": 2.5, ... },          // compound, required
//   "overrides": { "waterlogged=true": { ... } } }     // compound, optional
// ```
//
// Pure: no host imports.
// create's barrel re-exports the host bridge (wasm); the NBT model is pure.
// ignore_for_file: implementation_imports
import 'package:create/src/core/nbt.dart' show NbtKind, NbtValue;
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../network/network_nbt.dart';

/// `ExtraCodecs.TagOrElementLocation`: a block id or a block tag id.
final class TagOrElementLocation {
  /// The id, without the leading `#` for tags.
  final String id;

  /// Whether [id] is a tag.
  final bool tag;

  const TagOrElementLocation(this.id, {this.tag = false});

  /// `ExtraCodecs.TAG_OR_ELEMENT_ID` decoding: `#tag` or `ns:block`.
  factory TagOrElementLocation.parse(String value) => value.startsWith('#')
      ? TagOrElementLocation(value.substring(1), tag: true)
      : TagOrElementLocation(value);

  /// `decoratedId()`.
  String get decoratedId => tag ? '#$id' : id;

  @override
  bool operator ==(Object other) => other is TagOrElementLocation && other.id == id && other.tag == tag;

  @override
  int get hashCode => Object.hash(id, tag);

  @override
  String toString() => decoratedId;
}

/// One `property=value` condition of a [BlockStateConditionSet].
final class BlockStateCondition {
  final String property;
  final String value;

  const BlockStateCondition(this.property, this.value);

  /// `BlockStateCondition.parse`: `property=value`.
  factory BlockStateCondition.parse(String value) {
    final parts = value.split('=');
    if (parts.length != 2) {
      throw FormatException('Invalid block state condition: $value');
    }
    return BlockStateCondition(parts[0], parts[1]);
  }

  @override
  String toString() => '$property=$value';

  @override
  bool operator ==(Object other) =>
      other is BlockStateCondition && other.property == property && other.value == value;

  @override
  int get hashCode => Object.hash(property, value);
}

/// `BlockStateConditionSet`: a comma separated list of [BlockStateCondition]s,
/// serialized as one string (it is a `Codec.STRING`, so it is the NBT map key of
/// the `overrides` compound).
final class BlockStateConditionSet {
  final List<BlockStateCondition> conditions;

  const BlockStateConditionSet(this.conditions);

  /// `BlockStateConditionSet.parse`: `prop=value,prop2=value2`.
  factory BlockStateConditionSet.parse(String value) =>
      BlockStateConditionSet([for (final part in value.split(',')) BlockStateCondition.parse(part)]);

  /// `matches`: every condition's property must exist and hold the value.
  bool matches(Map<String, String> stateProperties) {
    for (final condition in conditions) {
      if (stateProperties[condition.property] != condition.value) return false;
    }
    return true;
  }

  @override
  String toString() => conditions.join(',');

  @override
  bool operator ==(Object other) {
    if (other is! BlockStateConditionSet || other.conditions.length != conditions.length) return false;
    for (var i = 0; i < conditions.length; i++) {
      if (other.conditions[i] != conditions[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(conditions);
}

/// A block state as the plot host reports it: an id and its properties.
final class BlockStateKey {
  final String blockId;
  final Map<String, String> properties;

  const BlockStateKey(this.blockId, [this.properties = const {}]);

  /// Parses `minecraft:oak_stairs[facing=north,half=bottom]`; a bare id has no
  /// properties.
  factory BlockStateKey.parse(String state) {
    final open = state.indexOf('[');
    if (open < 0 || !state.endsWith(']')) return BlockStateKey(state);
    final properties = <String, String>{};
    final body = state.substring(open + 1, state.length - 1);
    if (body.isNotEmpty) {
      for (final pair in body.split(',')) {
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        properties[pair.substring(0, eq)] = pair.substring(eq + 1);
      }
    }
    return BlockStateKey(state.substring(0, open), properties);
  }

  /// The canonical `id[prop=value,...]` form.
  @override
  String toString() => properties.isEmpty
      ? blockId
      : '$blockId[${properties.entries.map((e) => '${e.key}=${e.value}').join(',')}]';

  @override
  bool operator ==(Object other) {
    if (other is! BlockStateKey || other.blockId != blockId) return false;
    if (other.properties.length != properties.length) return false;
    for (final entry in properties.entries) {
      if (other.properties[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(blockId, Object.hashAllUnordered(properties.entries));
}

/// `PhysicsBlockPropertyTypes`: the eight property types and their defaults.
///
/// Java registers them in this order, and that order is the numeric id a
/// `PhysicsBlockPropertyType` carries. The ids are local bookkeeping, not wire
/// data: on the wire a property is always its resource identifier (`sable:mass`).
abstract final class PhysicsBlockPropertyTypes {
  static const String mass = 'sable:mass';
  static const String inertia = 'sable:inertia';
  static const String volume = 'sable:volume';
  static const String restitution = 'sable:restitution';
  static const String friction = 'sable:friction';
  static const String fragile = 'sable:fragile';
  static const String floatingMaterial = 'sable:floating_material';
  static const String floatingScale = 'sable:floating_scale';

  /// The registry order, which is also the numeric id order.
  static const List<String> all = [
    mass,
    inertia,
    volume,
    restitution,
    friction,
    fragile,
    floatingMaterial,
    floatingScale,
  ];

  /// `PhysicsBlockPropertyTypes.count()`.
  static int get count => all.length;

  /// `getPropertyType(id).id()`, or `null` for an unknown id.
  static int? indexOf(String id) {
    final index = all.indexOf(id);
    return index < 0 ? null : index;
  }
}

/// The resolved physics properties of one block state.
final class PhysicsBlockPropertyValues {
  /// `sable:mass`, in `kpg`. Default 1.0.
  final double mass;

  /// `sable:inertia`: the principal inertia, or `null` when not set (the
  /// pipeline then uses the block's default).
  final (double, double, double)? inertia;

  /// `sable:volume`, used for buoyancy. Default 1.0.
  final double volume;

  /// `sable:restitution`. Default 0.0.
  final double restitution;

  /// `sable:friction`, a multiplier. Default 1.0.
  final double friction;

  /// `sable:fragile`. Default false.
  final bool fragile;

  /// `sable:floating_material`: the material id, or `null`.
  final String? floatingMaterial;

  /// `sable:floating_scale`. Default 1.0.
  final double floatingScale;

  const PhysicsBlockPropertyValues({
    this.mass = 1.0,
    this.inertia,
    this.volume = 1.0,
    this.restitution = 0.0,
    this.friction = 1.0,
    this.fragile = false,
    this.floatingMaterial,
    this.floatingScale = 1.0,
  });

  /// The defaults of `PhysicsBlockPropertyTypes`.
  static const PhysicsBlockPropertyValues defaults = PhysicsBlockPropertyValues();

  /// Applies one property set (a definition's `properties`, or one override) on
  /// top of this value set, exactly like `BlockStateMixin.sable$applyPropertySet`.
  PhysicsBlockPropertyValues apply(Map<String, Object?> properties) {
    var mass = this.mass;
    var inertia = this.inertia;
    var volume = this.volume;
    var restitution = this.restitution;
    var friction = this.friction;
    var fragile = this.fragile;
    var floatingMaterial = this.floatingMaterial;
    var floatingScale = this.floatingScale;

    for (final entry in properties.entries) {
      switch (entry.key) {
        case PhysicsBlockPropertyTypes.mass:
          mass = entry.value as double;
        case PhysicsBlockPropertyTypes.inertia:
          inertia = entry.value as (double, double, double)?;
        case PhysicsBlockPropertyTypes.volume:
          volume = entry.value as double;
        case PhysicsBlockPropertyTypes.restitution:
          restitution = entry.value as double;
        case PhysicsBlockPropertyTypes.friction:
          friction = entry.value as double;
        case PhysicsBlockPropertyTypes.fragile:
          fragile = entry.value as bool;
        case PhysicsBlockPropertyTypes.floatingMaterial:
          floatingMaterial = entry.value as String?;
        case PhysicsBlockPropertyTypes.floatingScale:
          floatingScale = entry.value as double;
        default:
          throw ArgumentError.value(entry.key, 'property', 'is not a Sable physics property');
      }
    }

    return PhysicsBlockPropertyValues(
      mass: mass,
      inertia: inertia,
      volume: volume,
      restitution: restitution,
      friction: friction,
      fragile: fragile,
      floatingMaterial: floatingMaterial,
      floatingScale: floatingScale,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhysicsBlockPropertyValues &&
      other.mass == mass &&
      other.inertia == inertia &&
      other.volume == volume &&
      other.restitution == restitution &&
      other.friction == friction &&
      other.fragile == fragile &&
      other.floatingMaterial == floatingMaterial &&
      other.floatingScale == floatingScale;

  @override
  int get hashCode => Object.hash(
    mass,
    inertia,
    volume,
    restitution,
    friction,
    fragile,
    floatingMaterial,
    floatingScale,
  );

  @override
  String toString() =>
      'PhysicsBlockPropertyValues[mass=$mass, inertia=$inertia, volume=$volume, '
      'friction=$friction, fragile=$fragile, floating=$floatingMaterial]';
}

/// `PhysicsBlockPropertiesDefinition`: one datapack entry (or one
/// `physics_property` payload).
final class PhysicsBlockPropertiesDefinition {
  /// The block or block tag this definition applies to.
  final TagOrElementLocation selector;

  /// The priority; higher wins. Default 1000.
  final int priority;

  /// The properties, by `sable:` id.
  final Map<String, Object?> properties;

  /// Per-block-state overrides, by condition set.
  final Map<BlockStateConditionSet, Map<String, Object?>>? overrides;

  const PhysicsBlockPropertiesDefinition({
    required this.selector,
    required this.properties,
    this.priority = 1000,
    this.overrides,
  });

  /// `PhysicsBlockPropertiesDefinition.CODEC`, as NBT.
  Map<String, NbtValue> toNbt() {
    final map = <String, NbtValue>{
      'selector': NbtFields.string(selector.decoratedId),
    };
    if (priority != 1000) map['priority'] = NbtFields.intValue(priority);
    map['properties'] = NbtFields.compound(encodePropertySet(properties));
    final overrides = this.overrides;
    if (overrides != null) {
      map['overrides'] = NbtFields.compound({
        for (final entry in overrides.entries)
          entry.key.toString(): NbtFields.compound(encodePropertySet(entry.value)),
      });
    }
    return map;
  }

  /// `PhysicsBlockPropertiesDefinition.CODEC`, as NBT.
  factory PhysicsBlockPropertiesDefinition.fromNbt(Map<String, NbtValue> map) {
    final overridesTag = NbtFields.compoundOrNull(map, 'overrides');
    return PhysicsBlockPropertiesDefinition(
      selector: TagOrElementLocation.parse(NbtFields.requireString(map, 'selector')),
      priority: NbtFields.intOr(map, 'priority', 1000),
      properties: decodePropertySet(NbtFields.requireCompound(map, 'properties')),
      overrides: overridesTag == null
          ? null
          : {
              for (final entry in overridesTag.entries)
                BlockStateConditionSet.parse(entry.key): decodePropertySet(
                  _compoundValue(entry.key, entry.value),
                ),
            },
    );
  }

  /// The payload-body encoding.
  void write(PacketWriter buf) => NetworkNbtMap.write(buf, toNbt());

  /// The payload-body decoding.
  static PhysicsBlockPropertiesDefinition read(PacketReader buf) =>
      PhysicsBlockPropertiesDefinition.fromNbt(NetworkNbtMap.read(buf));

  static Map<String, NbtValue> _compoundValue(String key, NbtValue value) {
    if (value.kind != NbtKind.compound) {
      throw PacketException('NBT field "$key" is ${value.kind.name}, expected a compound');
    }
    return value.asCompound;
  }

  /// `Codec.dispatchedMap(Identifier.CODEC, PhysicsBlockPropertyTypes::getPropertyCodec)`
  /// encoding: the property id as the key, the type's codec as the value.
  static Map<String, NbtValue> encodePropertySet(Map<String, Object?> properties) => {
    for (final entry in properties.entries) entry.key: _encodeProperty(entry.key, entry.value),
  };

  /// The inverse of [encodePropertySet].
  static Map<String, Object?> decodePropertySet(Map<String, NbtValue> map) => {
    for (final entry in map.entries) entry.key: _decodeProperty(entry.key, entry.value),
  };

  static NbtValue _encodeProperty(String id, Object? value) => switch (id) {
    PhysicsBlockPropertyTypes.mass ||
    PhysicsBlockPropertyTypes.volume ||
    PhysicsBlockPropertyTypes.restitution ||
    PhysicsBlockPropertyTypes.friction ||
    PhysicsBlockPropertyTypes.floatingScale => NbtFields.doubleValue(value as double),
    PhysicsBlockPropertyTypes.inertia => NbtFields.doubleList([
      (value as (double, double, double)).$1,
      value.$2,
      value.$3,
    ]),
    PhysicsBlockPropertyTypes.fragile => NbtFields.boolean(value as bool),
    PhysicsBlockPropertyTypes.floatingMaterial => NbtFields.string(value as String),
    _ => throw ArgumentError.value(id, 'property', 'is not a Sable physics property'),
  };

  static Object? _decodeProperty(String id, NbtValue value) => switch (id) {
    PhysicsBlockPropertyTypes.mass ||
    PhysicsBlockPropertyTypes.volume ||
    PhysicsBlockPropertyTypes.restitution ||
    PhysicsBlockPropertyTypes.friction ||
    PhysicsBlockPropertyTypes.floatingScale => _requireNumber(id, value),
    PhysicsBlockPropertyTypes.inertia => _decodeVec3(id, value),
    PhysicsBlockPropertyTypes.fragile => _requireBool(id, value),
    PhysicsBlockPropertyTypes.floatingMaterial => _requireString(id, value),
    _ => throw PacketException('Unknown physics block property: $id'),
  };

  static double _requireNumber(String id, NbtValue value) => switch (value.kind) {
    NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (value.value as int).toDouble(),
    NbtKind.float || NbtKind.double => value.value as double,
    _ => throw PacketException('Physics property "$id" is ${value.kind.name}, expected a number'),
  };

  static bool _requireBool(String id, NbtValue value) => value.kind == NbtKind.byte
      ? (value.value as int) != 0
      : throw PacketException('Physics property "$id" is ${value.kind.name}, expected a byte');

  static String _requireString(String id, NbtValue value) => value.kind == NbtKind.string
      ? value.value as String
      : throw PacketException('Physics property "$id" is ${value.kind.name}, expected a string');

  /// `Vec3.CODEC` is `Codec.DOUBLE.listOf(3, 3)`: exactly three doubles.
  static (double, double, double)? _decodeVec3(String id, NbtValue value) {
    if (value.kind != NbtKind.list) {
      throw PacketException('Physics property "$id" is ${value.kind.name}, expected a list');
    }
    final items = value.value as List<NbtValue>;
    if (items.isEmpty) return null;
    if (items.length != 3) {
      throw PacketException('Physics property "$id" has ${items.length} elements, expected 3');
    }
    return (_requireNumber(id, items[0]), _requireNumber(id, items[1]), _requireNumber(id, items[2]));
  }

  @override
  bool operator ==(Object other) =>
      other is PhysicsBlockPropertiesDefinition &&
      other.selector == selector &&
      other.priority == priority &&
      _mapsEqual(other.properties, properties) &&
      _overridesEqual(other.overrides, overrides);

  @override
  int get hashCode => Object.hash(selector, priority, properties.length, overrides?.length);

  @override
  String toString() => 'PhysicsBlockPropertiesDefinition[selector=$selector, priority=$priority]';

  static bool _mapsEqual(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _overridesEqual(
    Map<BlockStateConditionSet, Map<String, Object?>>? a,
    Map<BlockStateConditionSet, Map<String, Object?>>? b,
  ) {
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !_mapsEqual(entry.value, other)) return false;
    }
    return true;
  }
}

/// The table of definitions, resolved per block state.
///
/// Java mutates a field on every `BlockState`; the port resolves lazily and
/// caches, which yields the same values for the same inputs.
final class PhysicsBlockPropertiesTable {
  /// `PhysicsBlockPropertiesDefinitionLoader.getDefinitions()`, in apply order.
  final List<PhysicsBlockPropertiesDefinition> definitions = [];

  final Map<BlockStateKey, PhysicsBlockPropertyValues> _cache = {};

  /// Whether [blockId] is in the tag [tagId]. Tag membership lives with the
  /// block registry, so it is a host query; it defaults to "no tag contains any
  /// block", which leaves tag selectors inert instead of wrong.
  bool Function(String blockId, String tagId) blockInTag = (_, _) => false;

  /// Replaces all definitions (`SimpleJsonResourceReloadListener.apply`): the
  /// list is sorted by ascending priority, so later entries win.
  void setDefinitions(Iterable<PhysicsBlockPropertiesDefinition> newDefinitions) {
    definitions
      ..clear()
      ..addAll(newDefinitions)
      ..sort((a, b) => a.priority.compareTo(b.priority));
    _cache.clear();
  }

  /// Adds one definition (`applyToBlocks` for a single definition): it is
  /// applied on top of the table, so the cache is dropped.
  void addDefinition(PhysicsBlockPropertiesDefinition definition) {
    definitions.add(definition);
    definitions.sort((a, b) => a.priority.compareTo(b.priority));
    _cache.clear();
  }

  /// Clears the table.
  void clear() {
    definitions.clear();
    _cache.clear();
  }

  /// The properties of [state], applying every matching definition in order.
  PhysicsBlockPropertyValues resolve(BlockStateKey state) {
    final cached = _cache[state];
    if (cached != null) return cached;

    var values = PhysicsBlockPropertyValues.defaults;
    for (final definition in definitions) {
      if (!_selectorMatches(definition.selector, state.blockId)) continue;
      values = values.apply(definition.properties);
      final overrides = definition.overrides;
      if (overrides != null) {
        for (final entry in overrides.entries) {
          if (entry.key.matches(state.properties)) values = values.apply(entry.value);
        }
      }
    }

    if (_cache.length > 8192) _cache.clear();
    return _cache[state] = values;
  }

  /// The properties of the block state string [state]
  /// (`minecraft:oak_stairs[facing=north]`).
  PhysicsBlockPropertyValues resolveStateString(String state) => resolve(BlockStateKey.parse(state));

  bool _selectorMatches(TagOrElementLocation selector, String blockId) =>
      selector.tag ? blockInTag(blockId, selector.id) : selector.id == blockId;

  /// `PhysicsBlockPropertyHelper.getMass`: a non-solid block has no mass.
  double massOf(String state, bool solid) => solid ? resolveStateString(state).mass : 0.0;

  /// `PhysicsBlockPropertyHelper.getInertia`: `null` for a non-solid block.
  (double, double, double)? inertiaOf(String state, bool solid) =>
      solid ? resolveStateString(state).inertia : null;

  /// `PhysicsBlockPropertyHelper.getFriction`.
  double frictionOf(String state) => resolveStateString(state).friction;

  /// `PhysicsBlockPropertyHelper.getVolume`.
  double volumeOf(String state) => resolveStateString(state).volume;

  /// `PhysicsBlockPropertyHelper.getRestitution`.
  double restitutionOf(String state) => resolveStateString(state).restitution;

  /// `PhysicsBlockPropertyHelper.getFloatingScale`.
  double floatingScaleOf(String state) => resolveStateString(state).floatingScale;

  /// `PhysicsBlockPropertyHelper.getFloatingMaterial`.
  String? floatingMaterialOf(String state) => resolveStateString(state).floatingMaterial;
}
