// `ItemAttribute`, `ItemAttributeType` and `AllItemAttributeTypes` (pure). An attribute is a
// predicate on an item stack that the attribute filter evaluates; a type creates the attributes
// of one registry entry (`create:item_attribute_type`).
//
// The attribute values of `AllItemAttributeTypes` are derived from what an [LStack] carries:
// the item key, the stack size and its data components. Properties that only the server knows
// (recipe inputs, tags, item groups) are evaluated through the hooks the filter part installs.
import 'dart:convert';

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
  singleton(
    'fluid_container',
    (s) =>
        _has(s, 'minecraft:bucket_entity_data') ||
        _has(s, 'create:fluid_contents'),
  );
  singleton('enchanted', (s) => _has(s, 'minecraft:enchantments'));
  singleton('max_enchanted', (s) => false);
  singleton('renamed', (s) => _has(s, 'minecraft:custom_name'));
  singleton('damaged', (s) => _damage(s) > 0);
  singleton('badly_damaged', (s) {
    final max = _maxDamage(s);
    return max > 0 && _damage(s) / max > 3 / 4;
  });
  singleton('not_stackable', (s) => !s.stackable);
  singleton('equipable', (s) => _has(s, 'minecraft:equippable'));
  singleton('furnace_fuel', (s) => _has(s, 'minecraft:cooking_fuel'));
  singleton(
    'washable',
    (s) => _has(s, 'minecraft:washable') || _has(s, 'create:washable'),
  );
  singleton('hauntable', (s) => _has(s, 'create:hauntable'));
  singleton('crushable', (s) => _has(s, 'create:crushable'));
  singleton('smeltable', (s) => _has(s, 'minecraft:smeltable'));
  singleton('smokable', (s) => _has(s, 'minecraft:smokable'));
  singleton('blastable', (s) => _has(s, 'minecraft:blastable'));
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

// -- stack helpers ------------------------------------------------------------------------------

bool _has(LStack s, String component) => s.hasComp(component);

/// A block item carries the block's default state component in 26.x; older data has none, so
/// the known block items of this plugin are used as a fallback.
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

/// The value of a string component (the network form of a string is a varint length and UTF-8).
String? _stringComponent(LStack s, String component) {
  final bytes = s.compBytes(component);
  if (bytes == null) return null;
  try {
    var i = 0;
    var length = 0;
    var shift = 0;
    while (i < bytes.length) {
      final b = bytes[i++];
      length |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return utf8.decode(bytes.sublist(i, i + length));
  } on Object {
    return null;
  }
}

// -- valued attributes --------------------------------------------------------------------------

final class _InTagAttributeType extends ValuedAttributeType {
  @override
  String get id => 'in_tag';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => const [];

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

  @override
  Object get value => tag;

  @override
  String get translationKey => 'in_tag';

  /// Tags are not part of an [LStack]; the filter part installs the predicate that knows them.
  @override
  bool appliesTo(LStack stack) => ItemAttributeHooks.itemInTag(stack.key, tag);
}

final class _InItemGroupAttributeType extends ValuedAttributeType {
  @override
  String get id => 'in_item_group';

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
  List<ItemAttribute> attributesOf(LStack stack) => const [];

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
  bool appliesTo(LStack stack) =>
      ItemAttributeHooks.hasEnchantment(stack, enchantment);
}

final class _ShulkerFillLevelAttributeType extends ValuedAttributeType {
  @override
  String get id => 'shulker_fill_level';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => const [];

  @override
  ItemAttribute? attributeFromValue(Object? value) {
    // `ShulkerLevels` writes its enum name in NBT.
    if (value is String) {
      return switch (value) {
        'empty' => const ShulkerFillLevelAttribute(0),
        'partial' => const ShulkerFillLevelAttribute(1),
        'full' => const ShulkerFillLevelAttribute(2),
        _ => null,
      };
    }
    return value is int ? ShulkerFillLevelAttribute(value) : null;
  }
}

/// `ShulkerFillLevelAttribute`: the fill level of a shulker box (0 to 2).
final class ShulkerFillLevelAttribute extends ValuedAttribute {
  final int level;

  const ShulkerFillLevelAttribute(this.level);

  @override
  String get typeId => 'shulker_fill_level';

  @override
  Object get value => level;

  @override
  String get translationKey => 'shulker_fill_level';

  @override
  bool appliesTo(LStack stack) =>
      ItemAttributeHooks.shulkerFillLevel(stack) == level;
}

final class _ColorAttributeType extends ValuedAttributeType {
  @override
  String get id => 'has_color';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => const [];

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

  @override
  String get translationKey => 'has_color';

  @override
  bool appliesTo(LStack stack) => ItemAttributeHooks.hasColor(stack, color);
}

final class _FluidContentsAttributeType extends ValuedAttributeType {
  @override
  String get id => 'has_fluid';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => const [];

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
  bool appliesTo(LStack stack) =>
      ItemAttributeHooks.fluidContents(stack) == fluid;
}

final class _ItemNameAttributeType extends ValuedAttributeType {
  @override
  String get id => 'has_name';

  @override
  List<ItemAttribute> attributesOf(LStack stack) {
    final name = ItemNameAttribute.nameOf(stack);
    return name == null ? const [] : [ItemNameAttribute(name)];
  }

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is String ? ItemNameAttribute(value) : null;
}

/// `ItemNameAttribute`: matches a custom item name.
final class ItemNameAttribute extends ValuedAttribute {
  final String name;

  const ItemNameAttribute(this.name);

  /// The custom name of [stack], `null` if it has none.
  static String? nameOf(LStack stack) =>
      _stringComponent(stack, 'minecraft:custom_name');

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
  List<ItemAttribute> attributesOf(LStack stack) => const [];

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
      ItemAttributeHooks.bookAuthor(stack) == author;
}

final class _BookCopyAttributeType extends ValuedAttributeType {
  @override
  String get id => 'book_copy';

  @override
  List<ItemAttribute> attributesOf(LStack stack) => const [];

  @override
  ItemAttribute? attributeFromValue(Object? value) =>
      value is bool ? BookCopyAttribute(value) : null;
}

/// `BookCopyAttribute`: whether a written book is an original or a copy.
final class BookCopyAttribute extends ValuedAttribute {
  final bool copy;

  const BookCopyAttribute(this.copy);

  @override
  String get typeId => 'book_copy';

  @override
  Object get value => copy;

  @override
  String get translationKey => 'book_copy';

  @override
  bool appliesTo(LStack stack) => ItemAttributeHooks.isBookCopy(stack) == copy;
}

/// The server-provided checks the pure attribute model needs. The filter part fills them in; the
/// defaults keep the model usable in tests (everything unknown is `false`).
abstract final class ItemAttributeHooks {
  static bool Function(String itemKey, String tag) itemInTag = (_, _) => false;
  static bool Function(String itemKey, String group) itemInGroup = (_, _) =>
      false;
  static bool Function(LStack stack, String enchantment) hasEnchantment =
      _hasEnchantmentComponent;
  static int Function(LStack stack) shulkerFillLevel =
      _shulkerFillLevelComponent;
  static bool Function(LStack stack, String color) hasColor =
      _hasColorComponent;
  static String? Function(LStack stack) fluidContents = _fluidComponent;
  static String? Function(LStack stack) bookAuthor = (_) => null;
  static bool? Function(LStack stack) isBookCopy = (_) => null;

  static bool _hasEnchantmentComponent(LStack stack, String enchantment) {
    final bytes = stack.compBytes('minecraft:enchantments');
    if (bytes == null) return false;
    // The enchantment list holds registry ids; the host's key is not part of the stack. Any
    // enchantment is a match when the filter only names one.
    return true;
  }

  static int _shulkerFillLevelComponent(LStack stack) {
    if (!stack.key.contains('shulker_box')) return 0;
    final bytes = stack.compBytes('minecraft:container');
    if (bytes == null) return 0;
    // A non-empty container component fills at least one level.
    return bytes.isEmpty ? 0 : 1;
  }

  static bool _hasColorComponent(LStack stack, String color) =>
      stack.key.contains(color);

  static String? _fluidComponent(LStack stack) {
    final bytes = stack.compBytes('minecraft:bucket_entity_data');
    return bytes == null ? null : null;
  }
}
