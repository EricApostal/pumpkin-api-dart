/// Hooks the `/create` command tree of the `infrastructure` module calls into other modules, and
/// the debug information registry. A module that owns the matching logic provides the hook as a
/// service in its `onLoad`:
///
/// ```dart
/// ctx.services.provide<RailwayCommandHooks>(MyRailwayHooks());
/// ```
///
/// The commands look the hooks up when they run (`services.find`), so the order of modules does not
/// matter; without a hook the command answers that the feature is not installed.
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/common.dart';
import '../infrastructure/debug/debug_info.dart';
import 'infra_data.dart';

export '../infrastructure/debug/debug_info.dart';
export 'infra_data.dart';

// ---------------------------------------------------------------- trains

/// Provided by the trains module: `Create.RAILWAYS`.
abstract interface class RailwayCommandHooks {
  /// The summary for a source at [location] in [worldId].
  RailwaySummary summarize(String worldId, Vec3 location);

  /// The train with this uuid, or `null`.
  TrainSummary? findTrain(String id);

  /// `train.invalid = true`. Returns false when there is no such train.
  bool removeTrain(String id);
}

// ---------------------------------------------------------------- glue, clone

/// Provided by the module that owns `SuperGlueEntity`.
abstract interface class GlueCommandHooks {
  /// `new SuperGlueEntity(world, SuperGlueEntity.span(from, to))` with the place sound.
  Future<bool> placeGlue(World world, Pos from, Pos to);

  /// `CloneCommand.cloneGlue`: copies the glue cropped to [area], moved by [offset]. Returns the count.
  Future<int> cloneGlue(World world, BlockBounds area, Pos offset);
}

// ---------------------------------------------------------------- contraptions

/// Provided by the contraptions module: `/create passenger`.
abstract interface class PassengerCommandHooks {
  /// Seats [rider] on [vehicle] like `PassengerCommand.run` when the vehicle is a contraption
  /// entity (seat [index] of its contraption); returns false when it is not one, then the caller
  /// mounts the rider like a plain vehicle. Riders that are contraption entities are refused.
  Future<bool> trySeat(Entity vehicle, Entity rider, int index);

  /// Whether [entity] is a carriage or controlled contraption entity (they cannot be riders).
  bool isContraptionEntity(Entity entity);
}

/// Provided by the module that owns minecart couplings: `/create coupling`.
abstract interface class MinecartCouplingHooks {
  /// `CouplingHandler.tryToCoupleCarts`.
  Future<void> couple(World world, int cartId1, int cartId2, {Player? source});

  /// Removes the coupling between two carts.
  Future<CouplingRemoval> remove(World world, int cartId1, int cartId2);

  /// `MinecartController.decouple`: returns the number of couplings removed (0 when none).
  Future<int> removeAll(World world, int cartId);
}

/// Provided by the contraptions module: the last assembly exception of a block entity.
abstract interface class AssemblyExceptionHooks {
  AssemblyExceptionInfo? lastAssemblyException(World world, Pos pos);
}

// ---------------------------------------------------------------- debug info

/// `DebugInformation`: sections shown by `/create debuginfo` (server side).
/// Provided by the infrastructure module.
abstract interface class DebugInformation {
  /// `registerServerInfo`. Registration must happen synchronously in `onLoad`/`onServerLoaded`.
  void registerServerInfo(DebugInfoSection section);

  /// The sections registered so far.
  List<DebugInfoSection> get serverInfo;
}
