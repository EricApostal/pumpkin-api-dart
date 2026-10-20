// The lift providers of Simulated, by block key.
//
// Sable's `ServerLevelPlot` asks a `liftProviderAt(pos, state)` hook for the
// provider of a block it just changed; the hook is per plot, so this registry is
// what the plugin answers with. Sails are the only lift provider of the mod.
//
// Pure: no host imports.
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart'
    show BlockSubLevelLiftProvider, LiftProviderContext, Vector3d;

import '../content/blocks/symmetric_sail/symmetric_sail_lift_provider.dart';

/// The lift providers of the mod.
abstract final class SimLiftProviders {
  /// The providers by block key.
  static final Map<String, BlockSubLevelLiftProvider> _providers = {};

  /// Registers [provider] for [blockKey].
  static void register(String blockKey, BlockSubLevelLiftProvider provider) =>
      _providers[blockKey] = provider;

  /// The provider of [blockKey], or `null`.
  static BlockSubLevelLiftProvider? providerOf(String blockKey) => _providers[blockKey];

  /// The context of [state] at [pos], or `null` when the block is not a provider.
  static LiftProviderContext? contextOf(Pos pos, BState state) {
    final provider = _providers[state.key];
    if (provider == null) return null;
    final Direction normal = provider.sable$getNormal(state);
    return LiftProviderContext(
      pos,
      state,
      Vector3d(normal.stepX.toDouble(), normal.stepY.toDouble(), normal.stepZ.toDouble()),
    );
  }

  /// The provider contexts of [positions] for a plot.
  ///
  /// sable's `ServerLevelPlot` stores a second, private `LiftProviderContext`
  /// (the one its barrel hides), so the plugin converts these contexts when it
  /// fills `plot.liftProviders`; see `PumpkinSimulatedHost`.
  static Map<Pos, LiftProviderContext> contextsFor(
    Iterable<Pos> positions,
    BState Function(Pos) stateAt,
  ) => {
    for (final pos in positions) pos: ?contextOf(pos, stateAt(pos)),
  };

  /// Removes every registration (tests).
  static void clear() => _providers.clear();
}

/// The key of a plot position in `ServerLevelPlot.liftProviders`.
int packPlotPos(Pos pos) => ((pos.$1 & 0x3FFFFFF) << 38) | ((pos.$3 & 0x3FFFFFF) << 12) | (pos.$2 & 0xFFF);

/// Registers the sail providers of every colour.
void registerSimLiftProviders() {
  const provider = SymmetricSailLiftProvider();
  for (final colour in const [
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
  ]) {
    SimLiftProviders.register('simulated:${colour}_symmetric_sail', provider);
  }
}
