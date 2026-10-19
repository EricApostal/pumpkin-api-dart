// `BlazeBurnerFuel` and the item data maps of the blaze burner (pure). The two maps are
// `create:regular_blaze_burner_fuels` and `create:superheated_blaze_burner_fuels`; the value is
// either an object with `burn_time` or a bare positive integer, exactly like the Java codec.
//
// The maps are data driven. `superheated` starts with Create's own `create:blaze_cake` (3200
// ticks); regular fuels come from the data pack (and NeoForge's furnace fuel data map, which the
// host cannot read; the processing module keeps its fallback table for that case).
abstract final class BlazeBurnerFuels {
  /// `CreateDataMaps.REGULAR_BLAZE_BURNER_FUELS`.
  static const String regularId = 'create:regular_blaze_burner_fuels';

  /// `CreateDataMaps.SUPERHEATED_BLAZE_BURNER_FUELS`.
  static const String superheatedId = 'create:superheated_blaze_burner_fuels';

  /// `REGULAR_BLAZE_BURNER_FUELS`: item key to burn time.
  static final Map<String, BlazeBurnerFuel> regular = {};

  /// `SUPERHEATED_BLAZE_BURNER_FUELS`; Create's own data file lists `create:blaze_cake`.
  static final Map<String, BlazeBurnerFuel> superheated = {
    'create:blaze_cake': const BlazeBurnerFuel(3200),
  };

  /// Registers a regular fuel.
  static void registerRegular(String itemKey, int burnTime) {
    if (burnTime <= 0)
      throw ArgumentError.value(burnTime, 'burnTime', 'must be positive');
    regular[itemKey] = BlazeBurnerFuel(burnTime);
  }

  /// Registers a superheated fuel.
  static void registerSuperheated(String itemKey, int burnTime) {
    if (burnTime <= 0)
      throw ArgumentError.value(burnTime, 'burnTime', 'must be positive');
    superheated[itemKey] = BlazeBurnerFuel(burnTime);
  }

  /// The regular fuel of [itemKey], or `null`.
  static BlazeBurnerFuel? regularFuel(String itemKey) => regular[itemKey];

  /// The superheated fuel of [itemKey], or `null`.
  static BlazeBurnerFuel? superheatedFuel(String itemKey) =>
      superheated[itemKey];

  /// `holder.getData(REGULAR_BLAZE_BURNER_FUELS).burnTime()`.
  static int? regularBurnTime(String itemKey) => regular[itemKey]?.burnTime;

  /// `holder.getData(SUPERHEATED_BLAZE_BURNER_FUELS).burnTime()`.
  static int? superheatedBurnTime(String itemKey) =>
      superheated[itemKey]?.burnTime;

  /// Loads a `data_maps/item/<map>.json` `values` object into [regular] or [superheated].
  /// Invalid values are skipped; [mapId] must be one of [regularId] / [superheatedId].
  static void applyDataMap(String mapId, Map<String, Object?> values) {
    final target = switch (mapId) {
      regularId => regular,
      superheatedId => superheated,
      _ => throw ArgumentError.value(
        mapId,
        'mapId',
        'not a blaze burner fuel data map',
      ),
    };
    for (final entry in values.entries) {
      final fuel = BlazeBurnerFuel.fromJson(entry.value);
      if (fuel != null) target[entry.key] = fuel;
    }
  }

  /// Removes every registration (tests and resource reloads).
  static void clear() {
    regular.clear();
    superheated.clear();
  }
}

/// `BlazeBurnerFuel`: how long an item burns in a blaze burner, in ticks.
final class BlazeBurnerFuel {
  /// `burn_time`, always positive.
  final int burnTime;

  const BlazeBurnerFuel(this.burnTime);

  /// `BlazeBurnerFuel.CODEC`: an object with `burn_time`, or a bare positive integer.
  static BlazeBurnerFuel? fromJson(Object? json) {
    if (json is int) return json > 0 ? BlazeBurnerFuel(json) : null;
    if (json is Map<Object?, Object?>) {
      final value = json['burn_time'];
      if (value is int && value > 0) return BlazeBurnerFuel(value);
    }
    return null;
  }

  /// The canonical object form (`{"burn_time": n}`).
  Map<String, Object?> toJson() => {'burn_time': burnTime};

  @override
  bool operator ==(Object other) =>
      other is BlazeBurnerFuel && other.burnTime == burnTime;

  @override
  int get hashCode => burnTime.hashCode;

  @override
  String toString() => 'BlazeBurnerFuel($burnTime)';
}
