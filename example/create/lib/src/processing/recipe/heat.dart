// `BlazeBurnerBlock.HeatLevel` and `HeatCondition` (pure).

/// `BlazeBurnerBlock.HeatLevel`: the value of the `blaze` property of a blaze burner.
enum HeatLevel {
  none,
  smouldering,
  fading,
  kindled,
  seething;

  /// The serialized name (`Lang.asId(name())`), which is the value of the `blaze` state property.
  String get serializedName => name;

  static HeatLevel byIndex(int index) => values[index];

  static HeatLevel? byName(String name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// `nextActiveLevel`: the next level after `none`, wrapping.
  HeatLevel nextActiveLevel() => byIndex(index % (values.length - 1) + 1);

  /// `isAtLeast`.
  bool isAtLeast(HeatLevel other) => index >= other.index;
}

/// `HeatCondition`: the heat a basin recipe needs.
enum HeatCondition {
  none(0xffffff),
  heated(0xE88300),
  superheated(0x5C93E8);

  final int color;
  const HeatCondition(this.color);

  String get serializedName => name;

  static HeatCondition? byName(String name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// `testBlazeBurner`.
  bool testBlazeBurner(HeatLevel level) {
    if (this == superheated) return level == HeatLevel.seething;
    if (this == heated) return level != HeatLevel.none && level != HeatLevel.smouldering;
    return true;
  }

  /// `visualizeAsBlazeBurner`.
  HeatLevel visualizeAsBlazeBurner() {
    if (this == superheated) return HeatLevel.seething;
    if (this == heated) return HeatLevel.kindled;
    return HeatLevel.none;
  }

  String get translationKey => 'recipe.heat_requirement.$name';
}
