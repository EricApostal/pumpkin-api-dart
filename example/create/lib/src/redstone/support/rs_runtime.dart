// The module's shared runtime: what block handlers and block entities need at call
// time (the context, the link network, the payload bus). Handlers are built in
// `register()`, before any of this exists, and read it lazily through [Rs].
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/worlds.dart';
import '../link/link_network.dart';
import '../../infrastructure/config/create_configs.dart';
import '../display/display_core.dart';
import 'level.dart';

/// The module's runtime state; created in `RedstoneModule.onLoad`.
final class RsRuntime {
  final CreateContext ctx;

  late final RedstoneLinkNetworkHandler links = RedstoneLinkNetworkHandler(linkRange: () => linkRange);

  /// The display sources and targets.
  final DisplayRegistry displays = DisplayRegistry();

  RsRuntime(this.ctx);

  /// `logistics.linkRange` (the server config, default 256).
  int get linkRange => ctx.services.find<CreateConfigs>()?.server.logistics.linkRange.value ?? 256;

  /// `logistics.displayLinkRange` (default 64).
  int get displayLinkRange => ctx.services.find<CreateConfigs>()?.server.logistics.displayLinkRange.value ?? 64;

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
}

/// Access to the runtime from handlers.
abstract final class Rs {
  static RsRuntime? _instance;

  static RsRuntime get i => _instance ?? (throw StateError('The redstone module is not loaded'));

  static bool get loaded => _instance != null;

  static void install(RsRuntime runtime) => _instance = runtime;

  static void clear() => _instance = null;

  /// A [Lvl] of an event world.
  static Lvl lvl(World w) => Lvl(w);
}
