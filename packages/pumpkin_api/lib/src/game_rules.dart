import 'bindings.g.dart';

/// The name of a game rule as used in commands, in snake_case.
extension GameRuleKey on GameRule {
  /// The snake_case name, for example `keep_inventory`.
  String get key {
    final out = StringBuffer();
    for (final unit in name.codeUnits) {
      if (unit >= 0x41 && unit <= 0x5A) {
        out.write('_');
        out.writeCharCode(unit + 0x20);
      } else {
        out.writeCharCode(unit);
      }
    }
    return out.toString();
  }

  /// The rule called [key] (`keep_inventory` or `minecraft:keep_inventory`),
  /// or `null` if there is none.
  static GameRule? fromKey(String key) {
    final wanted = key.startsWith('minecraft:') ? key.substring(10) : key;
    for (final rule in GameRule.values) {
      if (rule.key == wanted) return rule;
    }
    return null;
  }
}

/// Typed access to the game rules of a [World].
extension WorldGameRules on World {
  /// The value of the boolean rule [rule], or `null` if it is an integer rule.
  bool? getGameRuleBool(GameRule rule) => switch (getGameRule(rule: rule)) {
    GameRuleValueBool(:final value) => value,
    GameRuleValueInt() => null,
  };

  /// The value of the integer rule [rule], or `null` if it is a boolean rule.
  int? getGameRuleInt(GameRule rule) => switch (getGameRule(rule: rule)) {
    GameRuleValueInt(:final value) => value,
    GameRuleValueBool() => null,
  };

  /// Sets the boolean rule [rule].
  void setGameRuleBool(GameRule rule, bool value) =>
      setGameRule(rule: rule, value: GameRuleValueBool(value));

  /// Sets the integer rule [rule].
  void setGameRuleInt(GameRule rule, int value) =>
      setGameRule(rule: rule, value: GameRuleValueInt(value));

  /// Sets [rule] to [value], which must be a `bool` or an `int`.
  ///
  /// ```dart
  /// world.setGameRuleValue(GameRule.keepInventory, true);
  /// world.setGameRuleValue(GameRule.randomTickSpeed, 6);
  /// ```
  void setGameRuleValue(GameRule rule, Object value) => switch (value) {
    final bool b => setGameRuleBool(rule, b),
    final int i => setGameRuleInt(rule, i),
    _ => throw ArgumentError.value(value, 'value', 'Expected a bool or an int'),
  };
}
