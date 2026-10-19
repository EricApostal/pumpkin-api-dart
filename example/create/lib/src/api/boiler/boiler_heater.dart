// `BoilerHeater` and the blaze burner's boiler contribution (pure). The registry itself lives in
// the fluids module (`fluids/boiler.dart`) because the boiler consumes it; this file is the public
// API entry point: `BoilerHeater.REGISTRY.register(...)` in Java is `BoilerHeaters.register(...)`
// here, and `BoilerHeaters.blazeBurner` is [BlazeBurner.heatOf].
import '../../common/pos.dart';
import '../../fluids/boiler.dart' as boiler;
import '../../fluids/fluid_world.dart';
import '../../processing/recipe/heat.dart';
import '../block_state.dart';

export '../../fluids/boiler.dart' show BoilerHeaterFn, BoilerHeaters;

/// `BoilerHeater`: the heat a block gives to a boiler on top of it.
typedef BoilerHeater = boiler.BoilerHeaterFn;

/// The boiler values of [BoilerHeater] (`PASSIVE_HEAT`, `NO_HEAT`) and the blaze burner's
/// contribution (`BoilerHeaters.blazeBurner`).
abstract final class BlazeBurner {
  /// `BoilerHeater.PASSIVE_HEAT`.
  static const double passiveHeat = boiler.BoilerHeaters.passiveHeat;

  /// `BoilerHeater.NO_HEAT`.
  static const double noHeat = boiler.BoilerHeaters.noHeat;

  /// `BoilerHeaters.blazeBurner(level, pos, state)`: `noHeat` for an unlit burner, `2` for a
  /// seething one, `1` from fading upwards and passive heat while smouldering.
  static double heatOf(BState state) {
    final value = state['blaze'] ?? state['heat_level'];
    if (value == null) return noHeat;
    final level = HeatLevel.byName(value) ?? HeatLevel.none;
    return switch (level) {
      HeatLevel.none => noHeat,
      HeatLevel.seething => 2,
      HeatLevel.fading || HeatLevel.kindled => 1,
      HeatLevel.smouldering => passiveHeat,
    };
  }

  /// Whether the burner has a flame (`HeatLevel != NONE`).
  static bool isLit(BState state) => heatOf(state) != noHeat;

  /// `BoilerHeater.findHeat(level, pos, state)` for a blaze burner; other blocks use
  /// `BoilerHeaters.findHeat`.
  static double findHeat(FluidWorld level, Pos pos, BState state) =>
      boiler.BoilerHeaters.findHeat(level, pos, state);
}
