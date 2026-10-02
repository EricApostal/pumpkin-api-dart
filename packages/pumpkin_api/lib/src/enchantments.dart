import 'package:wasm_components/wasm_components.dart' show ErrorResult;

import 'bindings.g.dart';

/// Thrown when a custom enchantment is invalid or the server rejects it.
final class EnchantmentException implements Exception {
  /// What went wrong.
  final String message;
  const EnchantmentException(this.message);

  @override
  String toString() => 'EnchantmentException: $message';
}

/// Describes a custom enchantment and registers it with the server.
///
/// Set the properties with cascades, then call [register] (or [build]):
///
/// ```dart
/// EnchantmentBuilder('my_plugin:lifesteal', 'Life Steal')
///   ..maxLevel = 3
///   ..supportedItems = '#minecraft:enchantable/weapon'
///   ..exclusiveWith.add('my_plugin:poison_touch')
///   ..register(context.getServer().getEnchantmentManager());
/// ```
///
/// [description] is a [String] or a [TextComponent]; a component can only be
/// used by one [build].
final class EnchantmentBuilder {
  /// Unique id such as `my_plugin:lifesteal`.
  String id;

  /// Display name, a [String] or [TextComponent].
  Object description;

  /// Maximum level, at least 1.
  int maxLevel = 1;

  /// Base anvil cost multiplier.
  int anvilCost = 4;

  /// Item id, or tag starting with `#`, the enchantment can be applied to.
  String supportedItems = '#minecraft:enchantable/weapon';

  /// Rarity from 1 to 10; higher is more common.
  int weight = 5;

  /// Equipment slots in which the enchantment is active.
  List<AttributeModifierSlot> slots = [AttributeModifierSlot.mainHand];

  /// Ids of enchantments this one can't be combined with.
  List<String> exclusiveWith = [];

  /// Starts an enchantment with an [id] and display name.
  EnchantmentBuilder(this.id, this.description);

  /// Throws an [EnchantmentException] if the settings are invalid.
  void validate() {
    if (id.trim().isEmpty) {
      throw const EnchantmentException('enchantment id cannot be empty');
    }
    if (maxLevel < 1) {
      throw const EnchantmentException('enchantment max level must be at least 1');
    }
    if (description is! String && description is! TextComponent) {
      throw const EnchantmentException('description must be a String or TextComponent');
    }
  }

  /// Validates and creates the [CustomEnchantment] record.
  CustomEnchantment build() {
    validate();
    final text = description;
    return CustomEnchantment(
      id: id,
      description: text is TextComponent ? text : TextComponent.text(plain: text as String),
      maxLevel: maxLevel,
      anvilCost: anvilCost,
      supportedItems: supportedItems,
      weight: weight,
      slots: List.of(slots),
      exclusiveSet: List.of(exclusiveWith),
    );
  }

  /// Registers the enchantment with [manager]. Throws an
  /// [EnchantmentException] if it is invalid or rejected by the server.
  void register(EnchantmentManager manager) => manager.register(build());
}

extension EnchantmentManagerApi on EnchantmentManager {
  /// Registers a custom enchantment, given as a [CustomEnchantment] or an
  /// [EnchantmentBuilder]. Throws an [EnchantmentException] on failure.
  void register(Object enchantment) {
    final record = switch (enchantment) {
      EnchantmentBuilder() => enchantment.build(),
      CustomEnchantment() => enchantment,
      _ => throw ArgumentError.value(
        enchantment,
        'enchantment',
        'Expected an EnchantmentBuilder or CustomEnchantment',
      ),
    };
    if (registerEnchantment(enchantment: record) case ErrorResult(:final value)) {
      throw EnchantmentException(value);
    }
  }

  /// The definition of the enchantment [id], or `null` if it isn't registered.
  CustomEnchantment? find(String id) {
    final found = getEnchantment(id: id);
    return found.hasValue ? found.requireValue() : null;
  }

  /// Whether an enchantment with this [id] is registered.
  bool has(String id) => hasEnchantment(id: id);

  /// The ids of all registered enchantments.
  List<String> get ids => getAllEnchantmentIds();
}

extension EnchantmentRegistration on Server {
  /// Registers a custom enchantment, see [EnchantmentManagerApi.register].
  void registerCustomEnchantment(Object enchantment) =>
      getEnchantmentManager().register(enchantment);
}

extension EnchantmentContextRegistration on Context {
  /// Registers a custom enchantment, see [EnchantmentManagerApi.register].
  void registerCustomEnchantment(Object enchantment) =>
      getServer().registerCustomEnchantment(enchantment);
}

extension CustomEnchantmentItems on ItemStack {
  /// The level of the custom enchantment [id], or `null` if the stack lacks it.
  int? customEnchantmentLevel(String id) {
    final level = getCustomEnchantmentLevel(enchantmentId: id);
    return level.hasValue ? level.requireValue() : null;
  }
}

/// Formats [level] as a roman numeral up to 10 (`3` is `III`); larger levels
/// are returned as plain numbers.
String romanNumeral(int level) {
  const numerals = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
  return level >= 1 && level <= 10 ? numerals[level - 1] : '$level';
}
