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

  /// Components that must match too (`StrictNbtStackRequirement`): compared with
  /// [componentsMatch]; null means any components.
  final Object? strictComponents;

  const StackRequirement(
    this.item,
    this.count,
    this.usage, {
    this.strictComponents,
  });

  /// `matches(other)`: the same item (and the same components when strict).
  bool matches(String otherItem, {Object? otherComponents}) {
    if (item != otherItem) return false;
    if (strictComponents == null) return true;
    return componentsMatch(strictComponents, otherComponents);
  }

  static bool componentsMatch(Object? a, Object? b) =>
      a == b || (a is Map && b is Map && a.toString() == b.toString());

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
    var requirement = custom != null ? custom(state, nbt) : defaultOf(state);
    final typeKey = blockEntityTypeOf(state.key);
    if (typeKey != null) {
      final extra = blockEntities[typeKey];
      if (extra != null) requirement = requirement.union(extra(state, nbt));
    }
    return requirement;
  }

  /// `ItemRequirement.defaultOf`.
  ItemRequirement defaultOf(BState state) {
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
    }
    return ItemRequirement.invalid;
  }
}

Map<String, NbtValue>? _readEntity(List<int> nbt) {
  try {
    final parsed = BinaryNbt.read(nbt);
    return parsed != null && parsed.root.kind == NbtKind.compound
        ? parsed.root.asCompound
        : null;
  } on Object {
    // A malformed entity tag has no extra requirement.
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
