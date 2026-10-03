import 'bindings.g.dart';
import 'blocks.dart';
import 'menu_layout.dart';

/// Item rarity, which tints the item name.
enum ItemRarity {
  /// White (the default).
  common,

  /// Yellow.
  uncommon,

  /// Aqua.
  rare,

  /// Light purple.
  epic,
}

/// An attribute modifier on an [ItemSpec]: a plain, comparable description.
///
/// ```dart
/// const ItemAttribute(Attribute.attackDamage, 'my_plugin:bonus', 4,
///     ModifierOperation.add, AttributeModifierSlot.mainHand)
/// ```
final class ItemAttribute {
  /// The attribute changed.
  final Attribute attribute;

  /// Unique id of the modifier.
  final String id;

  /// The amount.
  final double amount;

  /// How [amount] is applied.
  final ModifierOperation operation;

  /// The slot in which the item has to be for the modifier to apply.
  final AttributeModifierSlot slot;

  /// Describes a modifier.
  const ItemAttribute(
    this.attribute,
    this.id,
    this.amount, [
    this.operation = ModifierOperation.add,
    this.slot = AttributeModifierSlot.any,
  ]);

  @override
  bool operator ==(Object other) =>
      other is ItemAttribute &&
      other.attribute == attribute &&
      other.id == id &&
      other.amount == amount &&
      other.operation == operation &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash(attribute, id, amount, operation, slot);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A plain description of an item stack: material, name, lore, enchantments
/// and a few components. It holds no host resources, so it can be a `const`,
/// kept in fields, compared, and turned into a fresh [ItemStack] with [build]
/// each time one is needed (stacks are consumed when put into an inventory).
///
/// ```dart
/// const sword = ItemSpec(
///   'diamond_sword',
///   name: 'Excalibur',
///   lore: ['Forged in Dart'],
///   enchantments: [(Enchantment.sharpness, 5)],
/// );
/// player.inventory.give(sword.build());
/// ```
///
/// Texts are plain strings. A name or lore line containing `&` followed by a
/// colour or format code (`&6Gold &lbold`) is parsed as legacy formatting.
/// Names and lore are shown non-italic unless [italic] is `true`.
final class ItemSpec {
  /// Registry key of the item (`diamond` or `minecraft:diamond`).
  final String key;

  /// Stack size.
  final int count;

  /// Custom display name, or `null` for the item's own name.
  final String? name;

  /// Lore lines.
  final List<String> lore;

  /// `(enchantment, level)` pairs.
  final List<(Enchantment, int)> enchantments;

  /// Attribute modifiers.
  final List<ItemAttribute> attributes;

  /// The `custom-model-data` value (selects a resource pack model).
  final int? customModelData;

  /// Whether the item can't break.
  final bool unbreakable;

  /// `true` forces the enchantment glint on, `null` leaves it as is. (The
  /// host can only force it on.)
  final bool? glint;

  /// Durability damage already taken.
  final int? damage;

  /// Maximum durability.
  final int? maxDamage;

  /// Maximum stack size override.
  final int? maxStackSize;

  /// Rarity (name colour).
  final ItemRarity? rarity;

  /// Item model id (`namespace:path`) overriding the item's look.
  final String? itemModel;

  /// Whether name and lore are italic (the vanilla default for custom
  /// names). `false` by default, which suits menus.
  final bool italic;

  /// Describes an item.
  const ItemSpec(
    this.key, {
    this.count = 1,
    this.name,
    this.lore = const [],
    this.enchantments = const [],
    this.attributes = const [],
    this.customModelData,
    this.unbreakable = false,
    this.glint,
    this.damage,
    this.maxDamage,
    this.maxStackSize,
    this.rarity,
    this.itemModel,
    this.italic = false,
  });

  /// A copy with some fields replaced. Pass `clearName: true` to remove the
  /// name.
  ItemSpec copyWith({
    String? key,
    int? count,
    String? name,
    bool clearName = false,
    List<String>? lore,
    List<(Enchantment, int)>? enchantments,
    List<ItemAttribute>? attributes,
    int? customModelData,
    bool? unbreakable,
    bool? glint,
    int? damage,
    int? maxDamage,
    int? maxStackSize,
    ItemRarity? rarity,
    String? itemModel,
    bool? italic,
  }) => ItemSpec(
    key ?? this.key,
    count: count ?? this.count,
    name: clearName ? null : (name ?? this.name),
    lore: lore ?? this.lore,
    enchantments: enchantments ?? this.enchantments,
    attributes: attributes ?? this.attributes,
    customModelData: customModelData ?? this.customModelData,
    unbreakable: unbreakable ?? this.unbreakable,
    glint: glint ?? this.glint,
    damage: damage ?? this.damage,
    maxDamage: maxDamage ?? this.maxDamage,
    maxStackSize: maxStackSize ?? this.maxStackSize,
    rarity: rarity ?? this.rarity,
    itemModel: itemModel ?? this.itemModel,
    italic: italic ?? this.italic,
  );

  TextComponent _text(String text) {
    final component = text.contains('&')
        ? TextComponent.fromLegacyStringWithCode(input: text, codeSymbol: 0x26)
        : TextComponent.text(plain: text);
    if (!italic) component.italic(value: false);
    return component;
  }

  /// Creates a new [ItemStack]. Every call makes a fresh one; hand it to
  /// the host (inventory, `setItem`, ...) which consumes it.
  ItemStack build() {
    final stack = ItemStack.create(
      registryKey: normalizeRegistryKey(key),
      count: count,
    );
    final n = name;
    if (n != null) stack.setCustomName(name: _text(n));
    if (lore.isNotEmpty) {
      stack.setLore(lore: [for (final line in lore) _text(line)]);
    }
    for (final (enchantment, level) in enchantments) {
      stack.addEnchantment(enchantment: enchantment, level: level);
    }
    for (final a in attributes) {
      stack.addAttributeModifier(
        modifier: ItemAttributeModifier(
          attribute: a.attribute,
          modifier: AttributeModifier(
            id: a.id,
            amount: a.amount,
            operation: a.operation,
          ),
          slot: a.slot,
        ),
      );
    }
    void component(DataComponent c, List<int> bytes) =>
        stack.setComponent(component: c, value: bytes);
    final cmd = customModelData;
    if (cmd != null) {
      component(DataComponent.customModelData, ComponentBytes.customModelData(cmd));
    }
    if (unbreakable) component(DataComponent.unbreakable, const []);
    if (glint == true) {
      component(DataComponent.enchantmentGlintOverride, const [1]);
    }
    final d = damage;
    if (d != null) component(DataComponent.damage, ComponentBytes.varInt(d));
    final md = maxDamage;
    if (md != null) component(DataComponent.maxDamage, ComponentBytes.varInt(md));
    final ms = maxStackSize;
    if (ms != null) {
      component(DataComponent.maxStackSize, ComponentBytes.varInt(ms));
    }
    final r = rarity;
    if (r != null) component(DataComponent.rarity, ComponentBytes.varInt(r.index));
    final model = itemModel;
    if (model != null) {
      component(DataComponent.itemModel, ComponentBytes.string(model));
    }
    return stack;
  }

  @override
  bool operator ==(Object other) =>
      other is ItemSpec &&
      other.key == key &&
      other.count == count &&
      other.name == name &&
      _listEq(other.lore, lore) &&
      _listEq(other.enchantments, enchantments) &&
      _listEq(other.attributes, attributes) &&
      other.customModelData == customModelData &&
      other.unbreakable == unbreakable &&
      other.glint == glint &&
      other.damage == damage &&
      other.maxDamage == maxDamage &&
      other.maxStackSize == maxStackSize &&
      other.rarity == rarity &&
      other.itemModel == itemModel &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(
    key,
    count,
    name,
    Object.hashAll(lore),
    Object.hashAll(enchantments),
    Object.hashAll(attributes),
    customModelData,
    unbreakable,
    glint,
    damage,
    maxDamage,
    maxStackSize,
    rarity,
    itemModel,
    italic,
  );

  @override
  String toString() => 'ItemSpec($key x$count${name == null ? '' : ', "$name"'})';
}

/// A fluent builder for [ItemSpec]s and [ItemStack]s.
///
/// ```dart
/// final stack = ItemBuilder('diamond_sword')
///     .name('&6Excalibur')
///     .lore(['Forged in Dart', 'Very sharp'])
///     .enchant(Enchantment.sharpness, 5)
///     .unbreakable()
///     .customModelData(7)
///     .build();
/// ```
///
/// [build] creates a new [ItemStack] each time; [spec] returns the plain
/// description to store in menus.
final class ItemBuilder {
  ItemSpec _spec;

  /// Starts a builder for the item [key] (`diamond`, `minecraft:diamond`).
  ItemBuilder(String key, {int count = 1}) : _spec = ItemSpec(key, count: count);

  /// Starts from an existing [spec].
  ItemBuilder.from(ItemSpec spec) : _spec = spec;

  /// Sets the stack size.
  ItemBuilder count(int count) => _with(_spec.copyWith(count: count));

  /// Sets the display name (see [ItemSpec] for `&` codes).
  ItemBuilder name(String name) => _with(_spec.copyWith(name: name));

  /// Replaces the lore.
  ItemBuilder lore(List<String> lines) => _with(_spec.copyWith(lore: List.of(lines)));

  /// Appends a lore line.
  ItemBuilder addLore(String line) =>
      _with(_spec.copyWith(lore: [..._spec.lore, line]));

  /// Adds an enchantment ([level] defaults to 1).
  ItemBuilder enchant(Enchantment enchantment, [int level = 1]) => _with(
    _spec.copyWith(enchantments: [..._spec.enchantments, (enchantment, level)]),
  );

  /// Adds an attribute modifier.
  ItemBuilder attribute(
    Attribute attribute,
    double amount, {
    String? id,
    ModifierOperation operation = ModifierOperation.add,
    AttributeModifierSlot slot = AttributeModifierSlot.any,
  }) => _with(
    _spec.copyWith(
      attributes: [
        ..._spec.attributes,
        ItemAttribute(
          attribute,
          id ?? 'item_builder:${_spec.attributes.length}',
          amount,
          operation,
          slot,
        ),
      ],
    ),
  );

  /// Sets the resource-pack model number.
  ItemBuilder customModelData(int value) =>
      _with(_spec.copyWith(customModelData: value));

  /// Makes the item unbreakable.
  ItemBuilder unbreakable([bool value = true]) =>
      _with(_spec.copyWith(unbreakable: value));

  /// Forces the enchantment glint on.
  ItemBuilder glint([bool value = true]) => _with(_spec.copyWith(glint: value));

  /// Sets the durability damage taken.
  ItemBuilder damage(int value) => _with(_spec.copyWith(damage: value));

  /// Sets the maximum durability.
  ItemBuilder maxDamage(int value) => _with(_spec.copyWith(maxDamage: value));

  /// Sets the maximum stack size.
  ItemBuilder maxStackSize(int value) => _with(_spec.copyWith(maxStackSize: value));

  /// Sets the rarity.
  ItemBuilder rarity(ItemRarity value) => _with(_spec.copyWith(rarity: value));

  /// Sets the item model id.
  ItemBuilder model(String id) => _with(_spec.copyWith(itemModel: id));

  /// Makes name and lore italic.
  ItemBuilder italic([bool value = true]) => _with(_spec.copyWith(italic: value));

  ItemBuilder _with(ItemSpec spec) {
    _spec = spec;
    return this;
  }

  /// The plain description built so far.
  ItemSpec get spec => _spec;

  /// Creates a new [ItemStack].
  ItemStack build() => _spec.build();
}


/// Namespaced registry key handling (`zombie` -> `minecraft:zombie`).
///
/// The generated enums expose their WIT name (`wireName`, kebab-case such as
/// `iron-golem`); registry keys are snake_case with a namespace
/// (`minecraft:iron_golem`). These helpers convert between the two.
abstract final class RegistryKeys {
  /// Adds the `minecraft:` namespace when [key] has none.
  static String normalize(String key) => normalizeRegistryKey(key);

  /// The part after the namespace (`minecraft:zombie` -> `zombie`).
  static String path(String key) {
    final i = key.indexOf(':');
    return i < 0 ? key : key.substring(i + 1);
  }

  /// The namespace of [key], `minecraft` when there is none.
  static String namespaceOf(String key) {
    final i = key.indexOf(':');
    return i < 0 ? 'minecraft' : key.substring(0, i);
  }

  /// Whether [key] looks like a registry key: lower-case letters, digits,
  /// `_ - . /` in the path and an optional namespace.
  static bool isValid(String key) =>
      RegExp(r'^([a-z0-9_.-]+:)?[a-z0-9_./-]+$').hasMatch(key);

  /// The WIT (kebab-case) name of a registry [key]: `minecraft:iron_golem`
  /// -> `iron-golem`.
  static String toWireName(String key) => path(key).replaceAll('_', '-');

  /// The registry key of a WIT name: `iron-golem` -> `minecraft:iron_golem`.
  static String fromWireName(String wireName, [String namespace = 'minecraft']) =>
      '$namespace:${wireName.replaceAll('-', '_')}';
}

/// Registry keys of entity types.
extension EntityTypeKey on EntityType {
  /// The registry key, `minecraft:zombie`.
  String get registryKey => RegistryKeys.fromWireName(wireName);

  /// The type for [key] (`zombie` or `minecraft:zombie`), or `null`.
  static EntityType? fromKey(String key) =>
      EntityType.fromWireName(RegistryKeys.toWireName(key));
}

/// Registry keys of biomes.
extension BiomeKey on Biome {
  /// The registry key, `minecraft:plains`.
  String get registryKey => RegistryKeys.fromWireName(wireName);

  /// The biome for [key], or `null`.
  static Biome? fromKey(String key) =>
      Biome.fromWireName(RegistryKeys.toWireName(key));
}

/// Registry keys of particles.
extension ParticleKey on Particle {
  /// The registry key, `minecraft:flame`.
  String get registryKey => RegistryKeys.fromWireName(wireName);

  /// The particle for [key], or `null`.
  static Particle? fromKey(String key) =>
      Particle.fromWireName(RegistryKeys.toWireName(key));
}

/// Registry keys of enchantments.
extension EnchantmentKey on Enchantment {
  /// The registry key, `minecraft:sharpness`.
  String get registryKey => RegistryKeys.fromWireName(wireName);

  /// The enchantment for [key], or `null`.
  static Enchantment? fromKey(String key) =>
      Enchantment.fromWireName(RegistryKeys.toWireName(key));
}

/// Registry keys of attributes.
extension AttributeKey on Attribute {
  /// The registry key, e.g. `minecraft:attack_damage`.
  String get registryKey => RegistryKeys.fromWireName(wireName);

  /// The attribute for [key], or `null`.
  static Attribute? fromKey(String key) =>
      Attribute.fromWireName(RegistryKeys.toWireName(key));
}

/// Registry keys of damage types.
extension DamageTypeKey on DamageType {
  /// The registry key, e.g. `minecraft:player_attack`.
  String get registryKey => RegistryKeys.fromWireName(wireName);

  /// The damage type for [key], or `null`.
  static DamageType? fromKey(String key) =>
      DamageType.fromWireName(RegistryKeys.toWireName(key));
}
