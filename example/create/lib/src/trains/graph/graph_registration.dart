// Registration of the graph area for the trains module (`TrainsModule` calls these): the hooks that
// connect the pure edge points to the host (block entities), and the handler of the serverbound
// `create:track_graph_request`. The payload channels themselves are declared by the protocol module
// for the whole manifest.
import '../../api/payloads.dart';
import '../../common/host_bridge.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../signal/track_edge_point.dart';
import '../support/level.dart';
import '../track/track_targeting_behaviour.dart';
import 'track_graph_request_packet.dart';

/// Phase 1: nothing to declare (the graph has no blocks of its own).
void registerGraph(CreateRegistry registry) {}

/// Phase 2: the edge point hooks and the graph request handler.
void loadGraph(CreateContext ctx) {
  installEdgePointHooks(ctx);
  final bus = ctx.services.find<PayloadBus>();
  bus?.onServerbound('create:track_graph_request', (player, fields) {
    final netId = fields['netId'];
    if (netId is! int) return;
    TrackGraphRequestPacket(netId).handle(player);
  });
}

/// Phase 3: nothing.
void serverGraphLoaded(CreateRuntime runtime) {}

/// Plugin unload.
void unloadGraph() {
  EdgePointHooks.describe = (be) => be is EdgePointOwnerInfo
      ? be
      : throw ArgumentError('Unknown block entity $be');
  EdgePointHooks.reportedPower = (_) => false;
  EdgePointHooks.observerFilter = (_) => null;
  EdgePointHooks.invalidateTargeting = null;
}

/// Connects [EdgePointHooks] to the block entities of [ctx]. Other modules' hooks
/// (`reportedPower`, `observerFilter`) are set by the signal and observer registrations.
void installEdgePointHooks(CreateContext ctx) {
  final store = ctx.blockEntities;
  EdgePointHooks.describe = (blockEntity) {
    if (blockEntity is EdgePointOwnerInfo) return blockEntity;
    if (blockEntity is CreateBlockEntity) {
      final pos = blockEntity.pos.toPos();
      final world = blockEntity.world;
      final props = world == null
          ? const <String, String>{}
          : (Lvl(world).info(pos)?.properties ?? const {});
      // `getLevel().dimension()`: the dimension key, not `blockEntity.worldId` (the store's world
      // id, the folder name). The edge point writes this into the graph's dimension palette, and
      // the client resolves the node's block entity by it.
      //
      // `world` is `null` only while its world is not loaded, and an edge point is rebuilt when the
      // world loads; until then the world id keeps the point addressable.
      final dimension = world?.getDimension() ?? blockEntity.worldId;
      return EdgePointOwnerInfo(pos, dimension, props);
    }
    throw ArgumentError('Not a block entity: $blockEntity');
  };
  EdgePointHooks.invalidateTargeting = (level, dimension, pos, migrationData) {
    // The hook is handed a dimension key (`getBlockEntityDimension()`); the store is keyed by the
    // world id. `Worlds.byId` resolves both strings (`Server.getWorldByName` accepts either).
    final worldId = ctx.worlds.worldIdOf(dimension) ?? dimension;
    final be = store.at(worldId, pos.toBlockPos());
    final behaviour = be
        ?.getBehaviour<TrackTargetingBehaviour<TrackEdgePoint>>();
    behaviour?.invalidateEdgePoint(migrationData);
  };
}
