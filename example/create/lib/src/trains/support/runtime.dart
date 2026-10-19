// The trains module's shared runtime: what block handlers, block entities and the railway
// manager need at call time (the context, the payload bus, the services). Handlers are built in
// `register()`, before any of this exists, and read it lazily through [Tr].
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/worlds.dart';
import 'level.dart';

/// The module's runtime state; created in `TrainsModule.onLoad`.
final class TrainsRuntime {
  final CreateContext ctx;

  TrainsRuntime(this.ctx);

  Logger get log => ctx.log;
  BlockEntityStore get store => ctx.blockEntities;
  Worlds get worlds => ctx.worlds;

  /// The payload bus of the protocol module, `null` when it is not loaded.
  PayloadBus? get bus => ctx.services.find<PayloadBus>();

  /// The world id of an event world (keeps the handle for later).
  String worldId(World w) => worlds.touch(w);

  /// The kept world with [id], or `null`.
  World? worldById(String id) => worlds.byId(id);

  /// The block entity of type `T` at [pos] of [world].
  T? be<T extends CreateBlockEntity>(World world, BlockPos pos) => store.typed<T>(worldId(world), pos);

  /// Extension point for the other layers: services this module looks up lazily.
  T? service<T extends Object>() => ctx.services.find<T>();
}

/// Access to the runtime from handlers.
abstract final class Tr {
  static TrainsRuntime? _instance;

  static TrainsRuntime get i => _instance ?? (throw StateError('The trains module is not loaded'));

  static bool get loaded => _instance != null;

  static void install(TrainsRuntime runtime) => _instance = runtime;

  static void clear() => _instance = null;

  /// A [Lvl] of an event world.
  static Lvl lvl(World w) => Lvl(w);
}
