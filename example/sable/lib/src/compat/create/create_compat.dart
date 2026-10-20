// The Create compatibility layer of Sable, pure half.
//
// Sable knows Create, never the other way round: this library lives in
// `package:sable` and imports `package:create`. It gives Sable three things:
//
// * the block contributions of Create's blocks (lift providers, custom centres
//   of mass, collision callbacks, assembly listeners) as a registry keyed by
//   block key, because Dart block states are data and cannot implement an
//   interface;
// * the contraption bridge: a Create contraption entity as a
//   `KinematicContraption`, with its mass, bounds, lift providers and the
//   transforms its collider and disassembly need;
// * the pure per-block behaviour ports (belt, ejector, saw, crushing wheel,
//   fan airflow, link ranges, ...).
//
// `install()` wires the registry into Sable. The host-side adapters (the ones
// that need Create's block entity classes) are in `create_host.dart`, reachable
// through `package:sable/sable_create_host.dart`.
//
// Pure: no host imports.
library;

import '../../sublevel/model/server_level_plot.dart' show LiftProviderContext, ServerLevelPlot;
import 'create_blocks.dart';

export 'contraption_collider.dart';
export 'contraption_physics.dart';
export 'create_air_current.dart';
export 'create_behaviours.dart';
export 'create_block_hooks.dart';
export 'create_blocks.dart';
export 'create_interactions.dart';
export 'create_machines.dart';

/// The Create compatibility layer: what a plugin calls to turn it on.
abstract final class CreateCompat {
  /// Registers Create's blocks and installs the lift provider lookup of the
  /// sub-level plots.
  ///
  /// Idempotent. Call it after the Create plugin registered its content and
  /// before the first sub-level ticks.
  static void install() {
    CreateCompatBlocks.install();
    ServerLevelPlot.liftProviderLookup = liftProviderAt;
  }

  /// Forgets everything this layer registered (tests, plugin unload).
  static void uninstall() {
    CreateCompatBlocks.uninstall();
    ServerLevelPlot.liftProviderLookup = null;
  }

  /// Whether the layer is installed.
  static bool get installed => CreateCompatBlocks.installed;

  /// The plot's lift provider lookup: the raw state string is parsed, then the
  /// registry answers.
  static LiftProviderContext? liftProviderAt((int, int, int) pos, String state) {
    final entry = CreateCompatBlocks.liftProviderAt(pos, parseBlockState(state));
    if (entry == null) return null;
    return LiftProviderContext(pos, state, (entry.normal.x, entry.normal.y, entry.normal.z));
  }
}
