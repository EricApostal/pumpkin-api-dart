// `ItemAttribute`, `ItemAttributeType` and `AllItemAttributeTypes` (pure). An attribute is a
// predicate on an item stack that the attribute filter evaluates; a type creates the attributes
// of one registry entry (`create:item_attribute_type`).
//
// Java: com.simibubi.create.content.logistics.item.filter.attribute.AllItemAttributeTypes
//
// The attribute values of `AllItemAttributeTypes` are derived from what an [LStack] carries:
// the item key and the data components (each decoded with its `networkSynchronized` stream
// codec). What only the server knows — item tags, recipe inputs, creative tabs, enchantment
// levels, fluid contents — comes in through [ItemAttributeHooks], which the filter part installs
// (see `filter_part.dart`). The defaults keep the model usable in tests: everything the server
// would answer is "unknown" (`false`, no attribute).
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api_core.dart' show VanillaIds;

import '../../core/nbt.dart';
import '../model/stack.dart';

/// `ItemAttribute`: a named test on an item stack.
abstract class ItemAttribute {
  const ItemAttribute();

  /// The key of the attribute type (`create:placeable`).
  String get typeId;

  /// `appliesTo(stack, level)`.
  bool appliesTo(LStack stack);

  /// The translation key below `item_attributes.` (`placeable`, `in_tag`).
  String get translationKey;

  /// `getTranslationParameters()`: the values shown in the tooltip.
  List<Object> get translationParameters => const [];

  /// The registry form, for filter persistence (JSON, hand written).
  Map<String, dynamic> toMap() => {'type': typeId};

  @override
  String toString() =>
      '$typeId${translationParameters.isEmpty ? '' : translationParameters}';
}

/// `ItemAttribute.ItemAttributeEntry`: an attribute and whether its result is inverted.
final class ItemAttributeEntry {
  final ItemAttribute attribute;
  final bool inverted;

  const ItemAttributeEntry(this.attribute, this.inverted);

  Map<String, dynamic> toMap() => {
    'attribute': attribute.toMap(),
    'inverted': inverted,
  };

  static ItemAttributeEntry? fromMap(Map<String, dynamic> map) {
    final attribute = ItemAttributeRegistry.instance.attributeFromMap(
      map['attribute'],
    );
    if (attribute == null) return null;
    return ItemAttributeEntry(attribute, map['inverted'] == true);
  }
}

/// `ItemAttributeType`: one entry of `create:item_attribute_type`.
abstract class ItemAttributeType {
  const ItemAttributeType();

  /// The registry key without the namespace (`placeable`).
  String get id;

  /// `getAllAttributes(stack, level)`.
  List<ItemAttribute> attributesOf(LStack stack);

  /// The attribute of [map] (`{type: <id>, ...parameters}`), or `null` if it is unknown here.
  ItemAttribute? fromMap(Map<String, dynamic> map) => null;
}

/// A type with exactly one attribute (`SingletonItemAttribute.Type`).
final class SingletonAttributeType extends ItemAttributeType {
  @override
  final String id;
  final bool Function(LStack stack) predicate;
  final String translationKey;

  SingletonAttributeType(this.id, this.predicate, {String? translationKey})
    : translationKey = translationKey ?? id;

  @override
  List<ItemAttribute> attributesOf(LStack stack) =>
      predicate(stack) ? [SingletonAttribute(this)] : const [];

  @override
  ItemAttribute? fromMap(Map<String, dynamic> map) => SingletonAttribute(this);
}

/// `SingletonItemAttribute`: the attribute a [SingletonAttributeType] yields.
final class SingletonAttribute extends ItemAttribute {
  final SingletonAttributeType type;

  const SingletonAttribute(this.type);

  @override
  String get typeId => type.id;

  @override
  bool appliesTo(LStack stack) => type.predicate(stack);

  @override
  String get translationKey => type.translationKey;
}

/// A type whose attributes carry a value (`InTagAttribute`, `EnchantAttribute`, ...).
abstract class ValuedAttributeType extends ItemAttributeType {
  const ValuedAttributeType();

  /// Creates the attribute of a serialized value, `null` when the value is malformed.
  ItemAttribute? attributeFromValue(Object? value);
}

/// An attribute with one value (a tag id, a colour, an enchantment, ...).
abstract class ValuedAttribute extends ItemAttribute {
  const ValuedAttribute();

  Object get value;

  @override
  List<Object> get translationParameters => [value];

  @override
  Map<String, dynamic> toMap() => {'type': typeId, 'value': value};

  @override
  bool operator ==(Object other) =>
      other is ValuedAttribute &&
      other.typeId == typeId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(typeId, value);
}

/// `AllItemAttributeTypes`: the registered types, in registration order.
final class ItemAttributeRegistry {
  ItemAttributeRegistry._();

  static final ItemAttributeRegistry instance = ItemAttributeRegistry._();

  final Map<String, ItemAttributeType> _byId = {};

  void register(ItemAttributeType type) =>
      _byId.putIfAbsent(type.id, () => type);

  ItemAttributeType? typeOf(String id) => _byId[id];

  List<String> get ids => [for (final t in _byId.values) 'create:${t.id}'];

  /// `ItemAttribute.getAllAttributes(stack, level)`, in registry order.
  List<ItemAttribute> allOf(LStack stack) => [
    for (final type in _byId.values) ...type.attributesOf(stack),
  ];

  /// The attribute of a serialized entry, or `null`.
  ItemAttribute? attributeFromMap(Object? map) {
    if (map is! Map) return null;
    final raw = map['type'];
    if (raw is! String) return null;
    // The dispatch codec writes the registry key (`create:in_tag`).
    final id = raw.startsWith('create:')
        ? raw.substring('create:'.length)
        : raw;
    final type = _byId[id];
    if (type == null) return null;
    if (type is SingletonAttributeType) {
      return type.fromMap(map.cast<String, dynamic>());
    }
    if (type is ValuedAttributeType) {
      return type.attributeFromValue(map['value']);
    }
    return type.fromMap(map.cast<String, dynamic>());
  }
}

/// `AllItemAttributeTypes.init()`: registers the default attributes (idempotent).
void registerDefaultItemAttributes() {
  final r = ItemAttributeRegistry.instance;

  // -- singleton attributes -------------------------------------------------------------------
  void singleton(String id, bool Function(LStack) predicate) =>
      r.register(SingletonAttributeType(id, predicate));

  singleton(
    'placeable',
    (s) => _has(s, 'minecraft:block_state') || _isBlockItem(s),
  );
  singleton('consumable', (s) => _has(s, 'minecraft:food'));
  // `TransferUtil.hasFluidHandler`: an item the spout or the drain can fill or empty.
  singleton('fluid_container', ItemAttributeHooks.holdsFluid);
  singleton('enchanted', (s) => _has(s, 'minecraft:enchantments'));
  singleton('max_enchanted', _maxEnchanted);
  singleton('renamed', (s) => _has(s, 'minecraft:custom_name'));
  singleton('damaged', (s) => _damage(s) > 0);
  singleton('badly_damaged', (s) {
    final max = _maxDamage(s);
    return max > 0 && _damage(s) / max > 3 / 4;
  });
  singleton('not_stackable', (s) => !s.stackable);
  singleton('equipable', _equipable);
  singleton('furnace_fuel', (s) => _has(s, 'minecraft:cooking_fuel'));
  // `AllFanProcessingTypes.SPLASHING::canProcess` / `HAUNTING::canProcess`.
  singleton('washable', (s) => _hasRecipe('create:splashing', s));
  singleton('hauntable', (s) => _hasRecipe('create:haunting', s));
  // `testRecipe(CRUSHING) || testRecipe(MILLING)`.
  singleton(
    'crushable',
    (s) => _hasRecipe('create:crushing', s) || _hasRecipe('create:milling', s),
  );
  singleton('smeltable', (s) => _hasRecipe('minecraft:smelting', s));
  singleton('smokable', (s) => _hasRecipe('minecraft:smoking', s));
  singleton('blastable', (s) => _hasRecipe('minecraft:blasting', s));
  singleton('compostable', (s) => _has(s, 'minecraft:compostable'));

  // -- valued attributes ----------------------------------------------------------------------
  r.register(_InTagAttributeType());
  r.register(_InItemGroupAttributeType());
  r.register(_AddedByAttributeType());
  r.register(_EnchantAttributeType());
  r.register(_ShulkerFillLevelAttributeType());
  r.register(_ColorAttributeType());
  r.register(_FluidContentsAttributeType());
  r.register(_ItemNameAttributeType());
  r.register(_BookAuthorAttributeType());
  r.register(_BookCopyAttributeType());
}

// -- singleton predicates -----------------------------------------------------------------------

bool _has(LStack s, String component) => s.hasComp(component);

bool _hasRecipe(String recipeType, LStack s) =>
    ItemAttributeHooks.hasRecipe(recipeType, s);

/// A block item carries the block's default state component in 26.x. That component is part of
/// the item's defaults, which the host does not report for a stack (`get-components` lists the
/// stack's own patch), so the known block items of this plugin are used as a fallback.
bool _isBlockItem(LStack s) {
  if (!s.key.startsWith('create:')) return false;
  const suffixes = [
    '_block',
    '_casing',
    '_cogwheel',
    '_shaft',
    '_table_cloth',
    '_postbox',
  ];
  return suffixes.any(s.key.endsWith);
}

/// `EQUIPABLE`: the `equippable` component names a slot of another type than `HAND`; a stack
/// without the component falls back to `MAINHAND` (`EquipmentSlot.MAINHAND.getType()`), so it is
/// not equipable. `EquipmentSlot.STREAM_CODEC` writes the slot id: 0 mainhand, 1 offhand, then
/// feet, legs, chest, head, body and saddle.
bool _equipable(LStack s) {
  final bytes = s.compBytes('minecraft:equippable');
  if (bytes == null || bytes.isEmpty) return false;
  final slot = _ComponentReader(bytes).varInt();
  return slot != null && slot > 1;
}

/// `AllItemAttributeTypes.maxEnchanted`: some enchantment is at its maximum level.
bool _maxEnchanted(LStack s) {
  final maxLevels = ItemAttributeHooks.enchantmentMaxLevels;
  if (maxLevels.isEmpty) return false;
  for (final (id, level) in _craftingEnchantments(s)) {
    final max = maxLevels[id];
    if (max != null && max <= level) return true;
  }
  return false;
}

int _varInt(List<int> bytes) {
  var value = 0;
  var shift = 0;
  for (final b in bytes) {
    value |= (b & 0x7F) << shift;
    if (b & 0x80 == 0) break;
    shift += 7;
  }
  return value;
}

int _damage(LStack s) {
  final bytes = s.compBytes('minecraft:damage');
  return bytes == null ? 0 : _varInt(bytes);
}

int _maxDamage(LStack s) {
  final bytes = s.compBytes('minecraft:max_damage');
  return bytes == null ? 0 : _varInt(bytes);
}

/// The namespace of an item key (`create`).
String itemNamespace(LStack s) {
  final i = s.key.indexOf(':');
  return i < 0 ? 'minecraft' : s.key.substring(0, i);
}

// -- component values ---------------------------------------------------------------------------
//
// Every data component value is the `networkSynchronized` encoding of the component, so it is
// read with the same stream codec the client uses. A malformed value reads as "unknown" instead
// of throwing: a stack that another plugin wrote badly must not break the filter.

/// A cursor over a network encoded component value; every read is `null` past the end.
final class _ComponentReader {
  _ComponentReader(this._bytes);

  final List<int> _bytes;
  int _i = 0;

  bool get atEnd => _i >= _bytes.length;

  /// `ByteBufCodecs.VAR_INT`.
  int? varInt() {
    var value = 0;
    var shift = 0;
    while (_i < _bytes.length) {
      final b = _bytes[_i++];
      value |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return value;
      shift += 7;
      if (shift > 35) return null;
    }
    return null;
  }

  /// `ByteBufCodecs.BOOL` and the flag of `ByteBufCodecs.optional`.
  bool? flag() {
    if (atEnd) return null;
    return _bytes[_i++] != 0;
  }

  /// Four bytes, big endian (`ByteBufCodecs.INT`).
  int? int32() {
    if (_i + 4 > _bytes.length) return null;
    final v =
        (_bytes[_i] << 24) |
        (_bytes[_i + 1] << 16) |
        (_bytes[_i + 2] << 8) |
        _bytes[_i + 3];
    _i += 4;
    return v;
  }

  /// `ByteBufCodecs.STRING_UTF8` and `Identifier.STREAM_CODEC`: a varint length and UTF-8.
  String? string() {
    final n = varInt();
    if (n == null || _i + n > _bytes.length) return null;
    try {
      final s = utf8.decode(_bytes.sublist(_i, _i + n));
      _i += n;
      return s;
    } on FormatException {
      return null;
    }
  }
}

/// The `(enchantment key, level)` pairs of an `ItemEnchantments` component
/// (`ItemEnchantments.STREAM_CODEC`: a varint count, then a registry id and a level per entry).
/// Enchantments another plugin registered have no key in the vanilla id table and are left out.
List<(String, int)> _enchantmentsOf(LStack stack, {required bool stored}) {
  final bytes = stack.compBytes(
    stored ? 'minecraft:stored_enchantments' : 'minecraft:enchantments',
  );
  if (bytes == null) return const [];
  final r = _ComponentReader(bytes);
  final count = r.varInt();
  if (count == null) return const [];
  final out = <(String, int)>[];
  for (var i = 0; i < count; i++) {
    final id = r.varInt();
    final level = r.varInt();
    if (id == null || level == null) return out;
    final key = VanillaIds.enchantments.keyOf(id);
    if (key != null) out.add((key, level));
  }
  return out;
}

/// `EnchantmentHelper.getEnchantmentsForCrafting`: an enchanted book keeps its enchantments in
/// `stored_enchantments`, everything else in `enchantments`.
List<(String, int)> _craftingEnchantments(LStack stack) =>
    _enchantmentsOf(stack, stored: stack.key == 'minecraft:enchanted_book');

/// `DyeColor` in id order (`DyeColor.STREAM_CODEC` writes the id).
const List<String> _dyeColors = [
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

/// `DyeColor.BY_FIREWORK_COLOR`: the firework colour value of each dye colour.
const Map<int, String> _fireworkColors = {
  0xFFFFFF: 'white',
  0xFF8000: 'orange',
  0xFF00FF: 'magenta',
  0x9AC0FC: 'light_blue',
  0xFFFF00: 'yellow',
  0xC0FF00: 'lime',
  0xFF80C0: 'pink',
  0x808080: 'gray',
  0xD3D3D3: 'light_gray',
  0x00FFFF: 'cyan',
  0xA03EF0: 'purple',
  0x0000FF: 'blue',
  0x8B4513: 'brown',
  0x00FF00: 'green',
  0xFF0000: 'red',
  0x000000: 'black',
};

/// `DyeColor.getColor(stack)`: the `dye` component, else the `c:dyed/<colour>` tag of the item.
/// Java stops before `BLACK`, so a black tag is not picked up here (a black item still matches
/// `has_color` through the item key, see [_colorsOf]).
String? _dyeColorOf(LStack stack) {
  final dye = stack.compBytes('minecraft:dye');
  if (dye != null) {
    final id = _ComponentReader(dye).varInt();
    if (id != null && id >= 0 && id < _dyeColors.length) return _dyeColors[id];
  }
  for (var i = 0; i < _dyeColors.length - 1; i++) {
    final color = _dyeColors[i];
    if (ItemAttributeHooks.itemInTag(stack.key, 'c:dyed/$color')) return color;
  }
  return null;
}

/// Reads one `FireworkExplosion` from [r] and returns its dye colours
/// (`FireworkExplosion.STREAM_CODEC`: shape, colours, fade colours, trail, twinkle).
List<String> _readExplosion(_ComponentReader r) {
  final out = <String>[];
  if (r.varInt() == null) return out; // shape
  for (var list = 0; list < 2; list++) {
    final n = r.varInt();
    if (n == null) return out;
    for (var i = 0; i < n; i++) {
      final rgb = r.int32();
      if (rgb == null) return out;
      final color = _fireworkColors[rgb & 0xFFFFFF];
      if (color != null && !out.contains(color)) out.add(color);
    }
  }
  r.flag(); // has trail
  r.flag(); // has twinkle
  return out;
}

/// `ColorAttribute.findMatchingDyeColors`.
List<String> _colorsOf(LStack stack) {
  final dyed = _dyeColorOf(stack);
  if (dyed != null) return [dyed];

  final colors = <String>[];
  final fireworks = stack.compBytes('minecraft:fireworks');
  if (fireworks != null && stack.key == 'minecraft:firework_rocket') {
    // `Fireworks.STREAM_CODEC`: the flight duration, then the explosions.
    final r = _ComponentReader(fireworks);
    final flight = r.varInt();
    final count = r.varInt();
    if (flight != null && count != null) {
      for (var i = 0; i < count; i++) {
        for (final color in _readExplosion(r)) {
          if (!colors.contains(color)) colors.add(color);
        }
      }
    }
  } else {
    final star = stack.compBytes('minecraft:firework_explosion');
    if (star != null) {
      for (final color in _readExplosion(_ComponentReader(star))) {
        if (!colors.contains(color)) colors.add(color);
      }
    }
  }

  final path = stack.key.substring(stack.key.indexOf(':') + 1);
  for (final color in _dyeColors) {
    if (path.startsWith('${color}_') && !colors.contains(color)) {
      colors.add(color);
    }
  }
  return colors;
}

/// The author and generation of a `written_book_content` component
/// (`WrittenBookContent.STREAM_CODEC`: title, author, generation, pages, resolved). The pages
/// come after the generation and are not read.
({String author, int generation})? _bookContent(LStack stack) {
  final bytes = stack.compBytes('minecraft:written_book_content');
  if (bytes == null) return null;
  final r = _ComponentReader(bytes);
  // `Filterable<String>`: the raw title, then an optional filtered one.
  if (r.string() == null) return null;
  final filtered = r.flag();
  if (filtered == null) return null;
  if (filtered && r.string() == null) return null;
  final author = r.string();
  final generation = r.varInt();
  if (author == null || generation == null) return null;
  return (author: author, generation: generation);
}

/// `ShulkerLevels.canApply`: -1 when [stack] is not a shulker box, else 0 (empty), 1 (partial)
/// or 2 (full).
int _shulkerLevel(LStack stack) {
  if (!ItemAttributeHooks.itemInTag(stack.key, 'minecraft:shulker_boxes')) {
    return -1;
  }
  final bytes = stack.compBytes('minecraft:container');
  // `getOrDefault(CONTAINER, ItemContainerContents.EMPTY)`.
  if (bytes == null) return 0;
  if (stack.hasComp('minecraft:container_loot')) return -1;

  final contents = ItemAttributeHooks.containerContents(bytes);
  if (contents == null) {
    // The contents hold a component this process cannot delimit. The slot count alone still
    // separates an empty box from a partly filled one.
    final slots = _ComponentReader(bytes).varInt();
    return slots == null || slots <= 0 ? 0 : 1;
  }
  if (contents.isEmpty) return 0;
  if (contents.length < 27) return 1;
  final full = contents.every((s) => s.isNotEmpty && s.count >= s.maxStack);
  return full ? 2 : 1;
}

/// `Component.getString()` of a network NBT text component: the `text` of a literal, the key of a
/// translation (Java's `getString()` does not resolve it either), then the siblings in `extra`.
String _componentText(NbtValue? value) {
  switch (value?.kind) {
    case null:
      return '';
    case NbtKind.string:
      return value!.value as String;
    case NbtKind.list:
      return (value!.value as List<NbtValue>).map(_componentText).join();
    case NbtKind.compound:
      final map = value!.asCompound;
      final b = StringBuffer();
      for (final key in const ['text', 'translate', 'keybind']) {
        final part = map[key];
        if (part != null) {
          b.write(_componentText(part));
          break;
        }
      }
      final extra = map['extra'];
      if (extra != null) b.write(_componentText(extra));
      return b.toString();
    default:
      return '';
  }
}

// -- valued attributes --------------------------------------------------------------------------

final class _InTagAttributeType extends ValuedAttributeType {
  @override
  String get id => 'in_tag';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => [
    // The host knows tag membership but not the tags of an item, so the candidates are the item
    // tags the shipped data pack names (see `ItemAttributeHooks.tagsOf`).
    for (final tag in ItemAttributeHooks.tagsOf(stack.key)) InTagAttribute(tag),
  ];

  @override
  ItemAttribute? attributeFromValue(Object? value) {
    if (value is! String) return null;
    // `TagKey` writes `#namespace:path` in NBT.
    return InTagAttribute(value.startsWith('#') ? value.substring(1) : value);
  }
}

/// `InTagAttribute`: matches the items of an item tag.
final class InTagAttribute extends ValuedAttribute {
  final String tag;

  const InTagAttribute(this.tag);

  @override
  String get typeId => 'in_tag';

  /// `TagKey.toString()`: `#namespace:path`.
  @override
  Object get value => '#$tag';

  @override
  String get translationKey => 'in_tag';

  /// `stack.is(tag)`; the filter part installs the predicate that knows the tags.
  @override
  bool appliesTo(LStack stack) => ItemAttributeHooks.itemInTag(stack.key, tag);
}

final class _InItemGroupAttributeType extends ValuedAttributeType {
  @override
  String get id => 'in_item_group';

  /// `CreativeModeTabs.tabs()` has no counterpart in the plugin API: the host exposes neither the
  /// creative tabs nor the items of one, so no group attribute is ever offered. Java lists the
  /// category tabs whose contents include the stack (`InItemGroupAttribute.Type`).
  @override
  List<ItemAttribute> attributesOf(LStack stack) => const [];

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is String ? InItemGroupAttribute(value) : null;
}

/// `InItemGroupAttribute`.
final class InItemGroupAttribute extends ValuedAttribute {
  final String group;

  const InItemGroupAttribute(this.group);

  @override
  String get typeId => 'in_item_group';

  @override
  Object get value => group;

  @override
  String get translationKey => 'in_item_group';

  @override
  bool appliesTo(LStack stack) =>
      ItemAttributeHooks.itemInGroup(stack.key, group);
}

final class _AddedByAttributeType extends ValuedAttributeType {
  @override
  String get id => 'added_by';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => [
    AddedByAttribute(itemNamespace(stack)),
  ];

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is String ? AddedByAttribute(value) : null;
}

/// `AddedByAttribute`: matches the namespace of the item.
final class AddedByAttribute extends ValuedAttribute {
  final String namespace;

  const AddedByAttribute(this.namespace);

  @override
  String get typeId => 'added_by';

  @override
  Object get value => namespace;

  @override
  String get translationKey => 'added_by';

  @override
  bool appliesTo(LStack stack) => itemNamespace(stack) == namespace;
}

final class _EnchantAttributeType extends ValuedAttributeType {
  @override
  String get id => 'has_enchant';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => [
    for (final (id, _) in _craftingEnchantments(stack)) EnchantAttribute(id),
  ];

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is String ? EnchantAttribute(value) : null;
}

/// `EnchantAttribute`: matches a stack carrying an enchantment.
final class EnchantAttribute extends ValuedAttribute {
  final String enchantment;

  const EnchantAttribute(this.enchantment);

  @override
  String get typeId => 'has_enchant';

  @override
  Object get value => enchantment;

  @override
  String get translationKey => 'has_enchant';

  @override
  bool appliesTo(LStack stack) {
    for (final (id, _) in _craftingEnchantments(stack)) {
      if (id == enchantment) return true;
    }
    return false;
  }
}

final class _ShulkerFillLevelAttributeType extends ValuedAttributeType {
  @override
  String get id => 'shulker_fill_level';

  @override
  List<ItemAttribute> attributesOf(LStack stack) {
    final level = _shulkerLevel(stack);
    return level < 0 ? const [] : [ShulkerFillLevelAttribute(level)];
  }

  @override
  ItemAttribute? attributeFromValue(Object? value) {
    // `ShulkerLevels` writes its enum name in NBT; the ordinal is the network form.
    if (value is String) return ShulkerFillLevelAttribute.fromKey(value);
    return value is int ? ShulkerFillLevelAttribute(value) : null;
  }
}

/// `ShulkerFillLevelAttribute`: the fill level of a shulker box (0 to 2).
final class ShulkerFillLevelAttribute extends ValuedAttribute {
  /// `ShulkerLevels.EMPTY` / `PARTIAL` / `FULL`.
  final int level;

  const ShulkerFillLevelAttribute(this.level);

  static const List<String> keys = ['empty', 'partial', 'full'];

  /// `ShulkerLevels.fromKey`.
  static ShulkerFillLevelAttribute? fromKey(String key) {
    final index = keys.indexOf(key);
    return index < 0 ? null : ShulkerFillLevelAttribute(index);
  }

  /// The enum name of [level] (`empty`), the NBT value of the attribute.
  String get key => level >= 0 && level < keys.length ? keys[level] : 'empty';

  @override
  String get typeId => 'shulker_fill_level';

  @override
  Object get value => key;

  /// `getTranslationKey()`: `shulker_level`, not the registry key.
  @override
  String get translationKey => 'shulker_level';

  @override
  bool appliesTo(LStack stack) => _shulkerLevel(stack) == level;
}

final class _ColorAttributeType extends ValuedAttributeType {
  @override
  String get id => 'has_color';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => [
    for (final color in _colorsOf(stack)) ColorAttribute(color),
  ];

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is String ? ColorAttribute(value) : null;
}

/// `ColorAttribute`: matches a stack dyed with a colour.
final class ColorAttribute extends ValuedAttribute {
  final String color;

  const ColorAttribute(this.color);

  @override
  String get typeId => 'has_color';

  @override
  Object get value => color;

  /// `getTranslationKey()`: `color`, not the registry key.
  @override
  String get translationKey => 'color';

  @override
  bool appliesTo(LStack stack) => _colorsOf(stack).contains(color);
}

final class _FluidContentsAttributeType extends ValuedAttributeType {
  @override
  String get id => 'has_fluid';

  @override
  List<ItemAttribute> attributesOf(LStack stack) {
    final fluid = ItemAttributeHooks.fluidOf(stack);
    return fluid == null ? const [] : [FluidContentsAttribute(fluid)];
  }

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is String ? FluidContentsAttribute(value) : null;
}

/// `FluidContentsAttribute`: matches a fluid container holding a fluid.
final class FluidContentsAttribute extends ValuedAttribute {
  final String fluid;

  const FluidContentsAttribute(this.fluid);

  @override
  String get typeId => 'has_fluid';

  @override
  Object get value => fluid;

  @override
  String get translationKey => 'has_fluid';

  @override
  bool appliesTo(LStack stack) => ItemAttributeHooks.fluidOf(stack) == fluid;
}

final class _ItemNameAttributeType extends ValuedAttributeType {
  @override
  String get id => 'has_name';

  @override
  List<ItemAttribute> attributesOf(LStack stack) {
    final name = ItemNameAttribute.nameOf(stack);
    return name.isEmpty ? const [] : [ItemNameAttribute(name)];
  }

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is String ? ItemNameAttribute(value) : null;
}

/// `ItemNameAttribute`: matches a custom item name.
final class ItemNameAttribute extends ValuedAttribute {
  final String name;

  const ItemNameAttribute(this.name);

  /// `extractCustomName`: the plain text of the `custom_name` component, `''` when the stack has
  /// none (the component is a text component, not a string).
  static String nameOf(LStack stack) {
    final bytes = stack.compBytes('minecraft:custom_name');
    if (bytes == null) return '';
    try {
      return _componentText(NetworkNbt.decode(bytes));
    } on Object {
      return '';
    }
  }

  @override
  String get typeId => 'has_name';

  @override
  Object get value => name;

  @override
  String get translationKey => 'has_name';

  @override
  bool appliesTo(LStack stack) => nameOf(stack) == name;
}

final class _BookAuthorAttributeType extends ValuedAttributeType {
  @override
  String get id => 'book_author';

  @override
  List<ItemAttribute> attributesOf(LStack stack) {
    final author = _bookContent(stack)?.author ?? '';
    return author.isEmpty ? const [] : [BookAuthorAttribute(author)];
  }

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is String ? BookAuthorAttribute(value) : null;
}

/// `BookAuthorAttribute`.
final class BookAuthorAttribute extends ValuedAttribute {
  final String author;

  const BookAuthorAttribute(this.author);

  @override
  String get typeId => 'book_author';

  @override
  Object get value => author;

  @override
  String get translationKey => 'book_author';

  @override
  bool appliesTo(LStack stack) =>
      (_bookContent(stack)?.author ?? '') == author;
}

final class _BookCopyAttributeType extends ValuedAttributeType {
  @override
  String get id => 'book_copy';

  @override
  List<ItemAttribute> attributesOf(LStack stack) {
    final generation = _bookContent(stack)?.generation ?? -1;
    return generation < 0 ? const [] : [BookCopyAttribute(generation)];
  }

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is int ? BookCopyAttribute(value) : null;
}

/// `BookCopyAttribute`: the generation of a written book (0 original, 1 first copy, 2 second
/// copy, 3 tattered).
final class BookCopyAttribute extends ValuedAttribute {
  final int generation;

  const BookCopyAttribute(this.generation);

  @override
  String get typeId => 'book_copy';

  @override
  Object get value => generation;

  @override
  String get translationKey => switch (generation) {
    0 => 'book_copy_original',
    1 => 'book_copy_first',
    2 => 'book_copy_second',
    _ => 'book_copy_tattered',
  };

  @override
  bool appliesTo(LStack stack) =>
      (_bookContent(stack)?.generation ?? -1) == generation;
}

/// The server-provided checks the pure attribute model needs. The filter part fills them in; the
/// defaults keep the model usable in tests (everything unknown is "no").
abstract final class ItemAttributeHooks {
  /// `stack.is(tag)`.
  static bool Function(String itemKey, String tag) itemInTag = (_, _) => false;

  /// `InItemGroupAttribute.tabContainsItem`: a creative tab holds the item.
  static bool Function(String itemKey, String group) itemInGroup = (_, _) => false;

  /// The item tags of an item, as far as the process can name them (for `in_tag`).
  static List<String> Function(String itemKey) tagsOf = (_) => const [];

  /// Whether a recipe of [recipeType] (`create:crushing`, `minecraft:smelting`, ...) takes the
  /// stack: the single-input lookups `AllItemAttributeTypes` runs for washable, crushable, ...
  static bool Function(String recipeType, LStack stack) hasRecipe = (_, _) => false;

  /// The maximum level of every enchantment the server knows, by key.
  static Map<String, int> enchantmentMaxLevels = const {};

  /// The fluid the stack holds (`GenericItemEmptying`), `null` when it holds none.
  static String? Function(LStack stack) fluidOf = (_) => null;

  /// `TransferUtil.hasFluidHandler`: the item can hold a fluid.
  static bool Function(LStack stack) holdsFluid = (_) => false;

  /// The slots of an `ItemContainerContents` value (`ItemContainerContents.STREAM_CODEC`),
  /// `null` when the contents cannot be delimited.
  static List<LStack>? Function(List<int> bytes) containerContents = (_) => null;
}
