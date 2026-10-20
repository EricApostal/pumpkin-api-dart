// What it takes to place a block or an entity (pure): `ItemRequirement` and the
// `SchematicRequirementRegistries` of Create's schematic API.
import '../api/block_state.dart';
import '../common/binary_nbt.dart';
import '../core/nbt.dart';

/// `ItemRequirement.ItemUseType`.
enum ItemUseType { consume, damage }

/// `StackRequirement` / `StrictNbtStackRequirement`.
final class StackRequirement {
  /// The item key (`minecraft:dirt`).
  final String item;
  final int count;
  final ItemUseType usage;

  /// Components that must match too (`StrictNbtStackRequirement`), as a
  /// `Map<String, NbtValue>` of component name to the component's NBT; null means any components.
  final Object? strictComponents;

  const StackRequirement(
    this.item,
    this.count,
    this.usage, {
    this.strictComponents,
  });

  /// `matches(other)`: the same item and, for a strict requirement (`StrictNbtStackRequirement`),
  /// the same components.
  ///
  /// [otherComponents] are the candidate's components, keyed by component name: as saved NBT
  /// (`Map<String, NbtValue>`, what a stack read from a schematic has) or as their network
  /// encoding (`Map<String, List<int>>`, what `ItemStack.getComponents` gives). The encoded form
  /// is compared through [encode], which turns one of [strictComponents] into those bytes and
  /// returns null for a component the caller cannot encode; such a component is not compared.
  /// Null [otherComponents] (or nothing to compare) pins the item only.
  bool matches(
    String otherItem, {
    Object? otherComponents,
    List<int>? Function(String name, NbtValue value)? encode,
  }) {
    if (item != otherItem) return false;
    final strict = strictComponents;
    if (strict == null || otherComponents == null) return true;
    if (otherComponents is Map<String, List<int>>) {
      if (encode == null || strict is! Map<String, NbtValue>) return true;
      for (final entry in strict.entries) {
        final bytes = encode(entry.key, entry.value);
        if (bytes == null) continue;
        final have = otherComponents[wireComponentName(entry.key)];
        if (have == null || !_sameBytes(have, bytes)) return false;
      }
      return true;
    }
    return componentsMatch(strict, otherComponents);
  }

  /// The name a component has in the network form (`DataComponent.wireName`, the key
  /// `ItemStack.getComponents` returns it under): `minecraft:max_stack_size` is
  /// `max-stack-size`. The pure model cannot import the API's `DataComponentCodec`, so the
  /// transform is spelled out here.
  static String wireComponentName(String name) {
    final bare = name.startsWith('minecraft:')
        ? name.substring('minecraft:'.length)
        : name;
    return bare.replaceAll('_', '-').replaceAll('/', '-');
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool componentsMatch(Object? a, Object? b) {
    if (identical(a, b) || a == b) return true;
    if (a == null || b == null) return false;
    return _nbtEquals(a, b);
  }

  /// Structural equality of two component values (NBT values or plain data).
  static bool _nbtEquals(Object? a, Object? b) {
    if (identical(a, b) || a == b) return true;
    if (a is NbtValue && b is NbtValue) {
      if (a.kind != b.kind) return false;
      final av = a.value, bv = b.value;
      if (av is List && bv is List) {
        if (av.length != bv.length) return false;
        for (var i = 0; i < av.length; i++) {
          if (!_nbtEquals(av[i], bv[i])) return false;
        }
        return true;
      }
      if (av is Map && bv is Map) {
        if (av.length != bv.length) return false;
        for (final e in av.entries) {
          if (!bv.containsKey(e.key)) return false;
          if (!_nbtEquals(e.value, bv[e.key])) return false;
        }
        return true;
      }
      return av == bv;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final e in a.entries) {
        if (!b.containsKey(e.key)) return false;
        if (!_nbtEquals(e.value, b[e.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_nbtEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return false;
  }

  @override
  String toString() =>
      '${usage == ItemUseType.damage ? 'damage ' : ''}$count x $item';
}

/// `ItemRequirement`.
final class ItemRequirement {
  /// `ItemRequirement.NONE`: nothing is needed (air).
  static const ItemRequirement none = ItemRequirement._([], _Kind.none);

  /// `ItemRequirement.INVALID`: the block has no item, it cannot be placed by the cannon.
  static const ItemRequirement invalid = ItemRequirement._([], _Kind.invalid);

  final List<StackRequirement> requiredItems;
  final _Kind _kind;

  const ItemRequirement._(this.requiredItems, this._kind);

  const ItemRequirement(this.requiredItems) : _kind = _Kind.items;

  factory ItemRequirement.of1(
    ItemUseType usage,
    String item, [
    int count = 1,
  ]) => ItemRequirement([StackRequirement(item, count, usage)]);

  bool get isEmpty => _kind == _Kind.none;
  bool get isInvalid => _kind == _Kind.invalid;

  /// `union`.
  ItemRequirement union(ItemRequirement other) {
    if (isInvalid || other.isInvalid) return invalid;
    if (isEmpty) return other;
    if (other.isEmpty) return this;
    return ItemRequirement([...requiredItems, ...other.requiredItems]);
  }

  @override
  String toString() =>
      isEmpty ? 'none' : (isInvalid ? 'invalid' : requiredItems.join(', '));
}

enum _Kind { none, invalid, items }

/// A block requirement supplied by a module (`SpecialBlockItemRequirement` /
/// `SchematicRequirementRegistries.BLOCKS`). [nbt] is the block entity data (binary NBT) or null.
typedef BlockRequirement = ItemRequirement Function(
  BState state,
  List<int>? nbt,
);

/// `SchematicRequirementRegistries.BLOCK_ENTITIES`: extra items a block entity needs, added to the
/// block's own requirement.
typedef BlockEntityRequirement = ItemRequirement Function(
  BState state,
  List<int>? nbt,
);

/// `SchematicRequirementRegistries.ENTITIES`: requirement of an entity by its type key, given the
/// entity NBT (binary).
typedef EntityRequirement = ItemRequirement Function(List<int> nbt);

/// The registries modules fill in `onLoad` (`ctx.services.require<SchematicRequirements>()`).
final class SchematicRequirements {
  final Map<String, BlockRequirement> blocks = {};
  final Map<String, BlockEntityRequirement> blockEntities = {};
  final Map<String, EntityRequirement> entities = {};

  /// Resolves the item that places a block (`Block.asItem()`): the item key, or null when the block
  /// has no item. The host wires this to the block registry (`Block.itemId`).
  String? Function(String blockKey) itemOfBlock = (k) => k;

  /// Block key to the block entity type key, for [blockEntities] (null: the block has no entity).
  String? Function(String blockKey) blockEntityTypeOf = (k) => null;

  /// `ItemRequirement.of(state, be)`.
  ItemRequirement ofBlock(BState state, List<int>? nbt) {
    final custom = blocks[state.key];
    var requirement = custom != null ? custom(state, nbt) : defaultOf(state, nbt);
    final typeKey = blockEntityTypeOf(state.key);
    if (typeKey != null) {
      final extra = blockEntities[typeKey];
      if (extra != null) requirement = requirement.union(extra(state, nbt));
    }
    return requirement;
  }

  /// `ItemRequirement.defaultOf`.
  ItemRequirement defaultOf(BState state, [List<int>? nbt]) {
    final key = state.key;
    if (key == 'minecraft:air' ||
        key == 'minecraft:cave_air' ||
        key == 'minecraft:void_air') {
      return ItemRequirement.none;
    }
    // Tall grass and large ferns do not exist as items: use two blades.
    if (key == 'minecraft:tall_grass')
      return ItemRequirement.of1(
        ItemUseType.consume,
        'minecraft:short_grass',
        2,
      );
    if (key == 'minecraft:large_fern')
      return ItemRequirement.of1(ItemUseType.consume, 'minecraft:fern', 2);
    if (key == 'minecraft:farmland' || key == 'minecraft:dirt_path') {
      return ItemRequirement.of1(ItemUseType.consume, 'minecraft:dirt');
    }
    // `AbstractBannerBlock` + `BannerBlockEntity.getItem()`: the banner keeps its patterns, so a
    // banner with patterns needs a matching banner item. A wall banner has no item in vanilla,
    // which gives the empty requirement Java builds from the empty stack.
    if (key.endsWith('_banner')) {
      final item = itemOfBlock(key) ?? 'minecraft:air';
      final patterns = _readCompound(nbt)?['patterns'];
      return ItemRequirement([
        StackRequirement(
          item,
          item == 'minecraft:air' ? 0 : 1,
          ItemUseType.consume,
          strictComponents: patterns == null
              ? null
              : {'minecraft:banner_patterns': patterns},
        ),
      ]);
    }
    final item = itemOfBlock(key);
    if (item == null || item == 'minecraft:air') return ItemRequirement.invalid;
    // double slab needs two items
    if (state['type'] == 'double' && key.endsWith('_slab'))
      return ItemRequirement.of1(ItemUseType.consume, item, 2);
    if (key == 'minecraft:turtle_egg')
      return ItemRequirement.of1(
        ItemUseType.consume,
        item,
        state.intValue('eggs'),
      );
    if (key == 'minecraft:sea_pickle')
      return ItemRequirement.of1(
        ItemUseType.consume,
        item,
        state.intValue('pickles'),
      );
    if (key == 'minecraft:snow')
      return ItemRequirement.of1(
        ItemUseType.consume,
        item,
        state.intValue('layers'),
      );
    return ItemRequirement.of1(ItemUseType.consume, item);
  }

  /// `ItemRequirement.of(entity)` for the entity [typeKey] with data [nbt].
  ItemRequirement ofEntity(String typeKey, List<int> nbt) {
    final custom = entities[typeKey];
    if (custom != null) return custom(nbt);
    final root = _readEntity(nbt);
    switch (typeKey) {
      case 'minecraft:item_frame':
      case 'minecraft:glow_item_frame':
        final frame = ItemRequirement.of1(ItemUseType.consume, typeKey);
        final displayed = _readStack(root?['Item']);
        if (displayed == null) return frame;
        return frame.union(
          ItemRequirement([
            StackRequirement(
              displayed.$1,
              displayed.$2,
              ItemUseType.consume,
              strictComponents: displayed.$3,
            ),
          ]),
        );
      case 'minecraft:armor_stand':
        final requirements = <StackRequirement>[
          const StackRequirement(
            'minecraft:armor_stand',
            1,
            ItemUseType.consume,
          ),
        ];
        // `ArmorStand.getItemBySlot` for every hand and humanoid armor slot.
        final equipment = root?['equipment'];
        if (equipment != null && equipment.kind == NbtKind.compound) {
          for (final entry in equipment.asCompound.values) {
            final item = _readStack(entry);
            if (item == null) continue;
            requirements.add(
              StackRequirement(
                item.$1,
                item.$2,
                ItemUseType.consume,
                strictComponents: item.$3,
              ),
            );
          }
        }
        return ItemRequirement(requirements);
      // `SuperGlueEntity.getRequiredItems` (`SuperGlueEntity.java:296-298`): the glue item, worn
      // down by a point of damage instead of being used up (`AllItems.SUPER_GLUE`).
      case 'create:super_glue':
        return ItemRequirement.of1(ItemUseType.damage, 'create:super_glue');
      // `BlueprintEntity.getRequiredItems` (`BlueprintEntity.java:347-349`): a crafting blueprint.
      case 'create:crafting_blueprint':
        return ItemRequirement.of1(
          ItemUseType.consume,
          'create:crafting_blueprint',
        );
    }
    return ItemRequirement.invalid;
  }
}

/// The requirements of the Create blocks that have no item of their own: the Java block classes
/// that implement `SpecialBlockItemRequirement` / `SpecialBlockEntityItemRequirement`, which
/// `SchematicRequirements.defaultOf` cannot resolve (`Block.asItem()` is air for them).
///
/// Registers into [r] the same entries Java's `SchematicRequirementRegistries.BLOCKS` /
/// `BLOCK_ENTITIES` would hold for these blocks. The caller wires [SchematicRequirements.
/// itemOfBlock] and [SchematicRequirements.blockEntityTypeOf] to the host registries first or
/// after; both are only read when a requirement is looked up.
void registerSpecialBlockRequirements(SchematicRequirements r) {
  // `GlassFluidPipeBlock.getRequiredItems` (`GlassFluidPipeBlock.java:74-76`) and
  // `EncasedPipeBlock.getRequiredItems` (`EncasedPipeBlock.java:158-160`): a plain fluid pipe.
  // `create:encased_fluid_pipe` resolves through its `fluid_pipe` block item already and needs no
  // entry; the glass pipe has none.
  r.blocks['create:glass_fluid_pipe'] = (state, nbt) =>
      r.defaultOf(const BState('create:fluid_pipe'), nbt);
  // `BeltFunnelBlock.getRequiredItems` (`BeltFunnelBlock.java:208-210`): `parent.asItem()`, the
  // funnel the belt funnel was made from.
  r.blocks['create:andesite_belt_funnel'] = (state, nbt) =>
      ItemRequirement.of1(ItemUseType.consume, 'create:andesite_funnel');
  r.blocks['create:brass_belt_funnel'] = (state, nbt) =>
      ItemRequirement.of1(ItemUseType.consume, 'create:brass_funnel');
  // `GirderEncasedShaftBlock.getRequiredItems` (`GirderEncasedShaftBlock.java:137-140`): a shaft
  // and a girder.
  r.blocks['create:metal_girder_encased_shaft'] = (state, nbt) =>
      r
          .defaultOf(const BState('create:shaft'), nbt)
          .union(r.defaultOf(const BState('create:metal_girder'), nbt));
  // `LecternControllerBlock.getRequiredItems` (`LecternControllerBlock.java:102-107`): a vanilla
  // lectern and a linked controller.
  r.blocks['create:lectern_controller'] = (state, nbt) =>
      const ItemRequirement([
        StackRequirement('minecraft:lectern', 1, ItemUseType.consume),
        StackRequirement('create:linked_controller', 1, ItemUseType.consume),
      ]);
  // `CopycatBlockEntity.getRequiredItems` (`CopycatBlockEntity.java:140-144`): the item the
  // copycat was made from (`Item` in its data), none while it has no material.
  r.blockEntities['create:copycat'] = (state, nbt) {
    final item = _readStack(_readCompound(nbt)?['Item']);
    if (item == null) return ItemRequirement.none;
    return ItemRequirement([
      StackRequirement(item.$1, item.$2, ItemUseType.consume),
    ]);
  };
}

Map<String, NbtValue>? _readEntity(List<int> nbt) => _readCompound(nbt);

/// The root compound of [nbt], or null when it cannot be read.
Map<String, NbtValue>? _readCompound(List<int>? nbt) {
  if (nbt == null) return null;
  try {
    final parsed = BinaryNbt.read(nbt);
    return parsed != null && parsed.root.kind == NbtKind.compound
        ? parsed.root.asCompound
        : null;
  } on Object {
    // A malformed tag has no extra requirement.
    return null;
  }
}

/// `(item key, count, components)` of a saved item stack, or `null` for an empty/unknown stack.
(String, int, Map<String, NbtValue>?)? _readStack(NbtValue? value) {
  if (value == null || value.kind != NbtKind.compound) return null;
  final map = value.asCompound;
  final id = map['id'];
  if (id == null || id.kind != NbtKind.string) return null;
  final item = id.value as String;
  if (item == 'minecraft:air') return null;
  final countValue = map['count'];
  final count = countValue != null && countValue.value is int
      ? countValue.value as int
      : 1;
  if (count <= 0) return null;
  final components = map['components'];
  return (
    item,
    count,
    components != null && components.kind == NbtKind.compound
        ? components.asCompound
        : null,
  );
}
