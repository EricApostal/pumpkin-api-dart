
import 'bindings.g.dart';
import 'blocks.dart';


TextComponent _text(Object text) => switch (text) {
  final String s => TextComponent.text(plain: s),
  final TextComponent c => c,
  _ => throw ArgumentError.value(text, 'text', 'Expected a String or TextComponent'),
};

/// Creates item stacks.
abstract final class ItemStacks {
  /// Creates a stack of [count] items of the kind [key] (`diamond`,
  /// `minecraft:diamond` or a custom `namespace:item`).
  ///
  /// [name] and every entry of [lore] can be a plain `String` or a
  /// `TextComponent`; components passed in are consumed. [enchantments] is a
  /// list of `(enchantment, level)` records.
  ///
  /// ```dart
  /// final sword = ItemStacks.of(
  ///   'diamond_sword',
  ///   name: 'Excalibur',
  ///   lore: ['Forged in Dart'],
  ///   enchantments: [(Enchantment.sharpness, 5)],
  /// );
  /// ```
  static ItemStack of(
    String key, {
    int count = 1,
    Object? name,
    List<Object> lore = const [],
    List<(Enchantment, int)> enchantments = const [],
  }) {
    final stack = ItemStack.create(
      registryKey: normalizeRegistryKey(key),
      count: count,
    );
    if (name != null) stack.setCustomName(name: _text(name));
    for (final line in lore) {
      stack.addLore(line: _text(line));
    }
    for (final (enchantment, level) in enchantments) {
      stack.addEnchantment(enchantment: enchantment, level: level);
    }
    return stack;
  }
}

/// Conveniences for [ItemStack].
///
/// Methods that take a `TextComponent` consume it, see the notes on each.
extension ItemStackHelpers on ItemStack {
  /// The registry key of the item, as the host reports it.
  String get key => getRegistryKey();

  /// Whether this stack is of the kind [key] (`diamond` or
  /// `minecraft:diamond`).
  bool matches(String key) => registryKeysMatch(getRegistryKey(), key);

  /// Whether the stack holds [maxCount] items. (`count`, `maxCount` and
  /// `customName` are properties of [ItemStack] itself; setting a custom name
  /// consumes the component.)
  bool get isFull => getCount() >= getMaxCount();

  /// Sets the custom name to the plain [text].
  void setName(String text) => customName = TextComponent.text(plain: text);

  /// Adds a lore line. [line] is a `String` or a `TextComponent`, which is
  /// consumed.
  void addLoreLine(Object line) => addLore(line: _text(line));

  /// Replaces the lore with [lines], each a `String` or a `TextComponent`.
  /// Components are consumed.
  void setLoreLines(List<Object> lines) =>
      setLore(lore: [for (final line in lines) _text(line)]);

  /// The level of [enchantment] on this stack, or 0 if it isn't enchanted
  /// with it.
  int enchantmentLevel(Enchantment enchantment) {
    for (final value in getEnchantments()) {
      if (value.enchantment == enchantment) return value.level;
    }
    return 0;
  }

  /// Whether this stack has [enchantment].
  bool hasEnchantment(Enchantment enchantment) =>
      enchantmentLevel(enchantment) > 0;

  /// Enchants this stack. [level] defaults to 1.
  void enchant(Enchantment enchantment, [int level = 1]) =>
      addEnchantment(enchantment: enchantment, level: level);

  /// The level of the custom enchantment [id], or 0 if it is missing.
  int customEnchantmentLevel(String id) {
    final level = getCustomEnchantmentLevel(enchantmentId: id);
    return level ?? 0;
  }
}
