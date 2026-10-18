import 'package:wasm_components/wasm_components.dart' show ErrorResult;

import 'bindings.g.dart';
import 'host_result.dart';

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
  Future<void> register(EnchantmentManager manager) =>
      manager.register(build());
}

extension EnchantmentManagerApi on EnchantmentManager {
  /// Registers a custom enchantment, given as a [CustomEnchantment] or an
  /// [EnchantmentBuilder]. Throws an [EnchantmentException] on failure.
  Future<void> register(Object enchantment) async {
    final record = switch (enchantment) {
      EnchantmentBuilder() => enchantment.build(),
      CustomEnchantment() => enchantment,
      _ => throw ArgumentError.value(
        enchantment,
        'enchantment',
        'Expected an EnchantmentBuilder or CustomEnchantment',
      ),
    };
    if (await registerEnchantment(enchantment: record) case ErrorResult(:final value)) {
      throw EnchantmentException(value);
    }
  }

  /// The definition of the enchantment [id], or `null` if it isn't registered.
  Future<CustomEnchantment?> find(String id) => getEnchantment(id: id);

  /// Whether an enchantment with this [id] is registered.
  Future<bool> has(String id) => hasEnchantment(id: id);

  /// The ids of all registered enchantments.
  Future<List<String>> ids() => getAllEnchantmentIds();
}

/// An effect component of an enchantment, as in the `effects` of its registry
/// data (`enchantment-effect` in `enchantments.wit`).
final class EnchantmentEffectSpec {
  /// The effect component type, for example `minecraft:ammo_use` or one from
  /// [EnchantmentManagerEffects.registerEffectType].
  final String componentKey;

  /// The component value as network NBT (the root tag type and its payload, no
  /// name).
  final List<int> valueNbt;

  const EnchantmentEffectSpec(this.componentKey, this.valueNbt);
}

/// Effects and costs of plugin enchantments. The host stores and syncs the
/// effect components, but does not evaluate the effects of plugin enchantments
/// itself: read them with [EnchantedItemStack.enchantmentEffect] and apply
/// them in your own events.
extension EnchantmentManagerEffects on EnchantmentManager {
  /// Sets the effect components of a registered enchantment (replaces earlier
  /// ones). They are part of the `minecraft:enchantment` registry data sent to
  /// every client. Throws a [HostException] on failure.
  Future<void> setEffects(String id, List<EnchantmentEffectSpec> effects) =>
      unwrapHostAsync(
        setEnchantmentEffects(
          id: id,
          effects: [
            for (final e in effects)
              EnchantmentEffect(componentKey: e.componentKey, valueNbtBytes: e.valueNbt),
          ],
        ),
        'Setting the effects of $id',
      );

  /// Sets the enchanting costs of a registered enchantment
  /// (`base + perLevel * (level - 1)`); without it the minimum is 1 + 10 per
  /// level and the maximum 21 + 10 per level.
  Future<void> setCosts(
    String id, {
    required int minBase,
    required int minPerLevel,
    required int maxBase,
    required int maxPerLevel,
  }) => unwrapHostAsync(
    setEnchantmentCosts(
      id: id,
      minBase: minBase,
      minPerLevel: minPerLevel,
      maxBase: maxBase,
      maxPerLevel: maxPerLevel,
    ),
    'Setting the costs of $id',
  );

  /// Registers an enchantment effect component type and returns its id, after
  /// the vanilla ones. NeoForge clients get it in
  /// `minecraft:enchantment_effect_component_type`.
  Future<int> registerEffectType(String key) => unwrapHostAsync(
    registerEnchantmentEffectType(key: key),
    'Registering the enchantment effect type $key',
  );
}

/// Enchantment queries on a stack.
extension EnchantedItemStack on ItemStack {
  /// The level of the enchantment [key] (vanilla or plugin) on this stack, 0 if
  /// it is not there.
  Future<int> enchantmentLevelOf(String key) => getEnchantmentLevel(enchantmentKey: key);

  /// The effects of the plugin enchantments on this stack for the effect
  /// component type [componentKey]: a list of compounds
  /// `{enchantment, level, value}`, `null` if there are none.
  Future<NbtTree?> enchantmentEffect(String componentKey) =>
      getEnchantmentEffect(componentKey: componentKey);
}

extension EnchantmentRegistration on Server {
  /// Registers a custom enchantment, see [EnchantmentManagerApi.register].
  Future<void> registerCustomEnchantment(Object enchantment) =>
      getEnchantmentManager().register(enchantment);
}

extension EnchantmentContextRegistration on Context {
  /// Registers a custom enchantment, see [EnchantmentManagerApi.register].
  Future<void> registerCustomEnchantment(Object enchantment) =>
      getServer().registerCustomEnchantment(enchantment);
}

extension CustomEnchantmentItems on ItemStack {
  /// The level of the custom enchantment [id], or `null` if the stack lacks it.
  Future<int?> customEnchantmentLevel(String id) =>
      getCustomEnchantmentLevel(enchantmentId: id);
}

/// Formats [level] as a roman numeral up to 10 (`3` is `III`); larger levels
/// are returned as plain numbers.
String romanNumeral(int level) {
  const numerals = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
  return level >= 1 && level <= 10 ? numerals[level - 1] : '$level';
}
