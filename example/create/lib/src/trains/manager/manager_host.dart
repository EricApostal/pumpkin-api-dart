// The host glue of the railway manager: the transport of the graph / edge group packets, the
// [TrainLevel] of each world, and the server tick and player hooks Java installs in
// `CommonEvents` (`RAILWAYS.tick(world)`, `RAILWAYS.sync.serverTick()`, `playerLogin` /
// `playerLogout`). Without it the pure manager never runs.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../entity/train_host.dart' show HostTrainLevel;
import '../entity/train_level.dart' show TrainLevel;
import '../support/runtime.dart';
import 'create.dart';
import 'global_railway_manager.dart';
import 'railway_network.dart';

HostTrainLevels? _levels;

/// Installs the network, the train levels and the tick / player listeners.
void installRailwayManager(CreateContext ctx) {
  final bus = ctx.services.find<PayloadBus>();
  RailwayNet.current = bus == null
      ? const NullRailwayNetwork()
      : HostRailwayNetwork(bus);

  final levels = _levels = HostTrainLevels(ctx.blockEntities);
  RailwayHooks.trainLevelById = levels.of;
  RailwayHooks.trainLevelFactory = (world) =>
      world is World ? levels.of(world.getId()) : null;

  ctx.listen(
    Events.worldUnload,
    (server, e) => levels.forget(e.targetWorld.getId()),
  );
  ctx.onWorldTick((t) {
    final level = levels.of(t.worldId);
    if (level != null) Create.RAILWAYS.tick(level);
  });
  ctx.listen(
    Events.serverTickEnd,
    (server, e) => Create.RAILWAYS.sync.serverTick(),
  );
  ctx.listen(
    Events.playerJoin,
    (server, e) => Create.RAILWAYS.playerLogin(e.player),
  );
  ctx.listen(
    Events.playerLeave,
    (server, e) => Create.RAILWAYS.playerLogout(e.player),
  );
}

/// Drops the host hooks and the kept levels.
void uninstallRailwayManager() {
  RailwayNet.current = const NullRailwayNetwork();
  RailwayHooks.trainLevelById = null;
  RailwayHooks.trainLevelFactory = null;
  RailwayHooks.sendAddTrainTo = null;
  _levels?.clear();
  _levels = null;
}

/// The [TrainLevel] of every loaded world, created once per world so the schedule conditions'
/// redstone probe keeps its state between ticks.
final class HostTrainLevels {
  final BlockEntityStore store;
  final Map<String, HostTrainLevel> _byId = {};

  HostTrainLevels(this.store);

  HostTrainLevel? of(String worldId) {
    final world = store.worlds.byId(worldId);
    if (world == null) {
      _byId.remove(worldId);
      return null;
    }
    final cached = _byId[worldId];
    if (cached != null) return cached;
    final level = HostTrainLevel(world, levelOfDimension: of);
    _byId[worldId] = level;
    return level;
  }

  void forget(String worldId) => _byId.remove(worldId);

  void clear() => _byId.clear();
}

/// Sends the railway packets as custom payloads. The pure packets already write the manifest
/// wire format; the bus is the only transport and takes field maps, so the bytes are decoded
/// back into fields (the manifest schemas are verified against those writers).
final class HostRailwayNetwork implements RailwayNetwork {
  final PayloadBus bus;

  HostRailwayNetwork(this.bus);

  @override
  void sendToAll(String channel, Uint8List data) {
    final fields = _decode(channel, data);
    if (fields == null) return;
    bus.sendClientboundAll(channel, bus.roster.players, fields);
  }

  @override
  void sendTo(Object player, String channel, Uint8List data) {
    if (player is! Player) return;
    final fields = _decode(channel, data);
    if (fields == null) return;
    bus.sendClientbound(channel, player, fields);
  }

  Map<String, Object?>? _decode(String channel, Uint8List data) {
    try {
      return bus.decode(channel, data);
    } on Object catch (e) {
      if (Tr.loaded) {
        Tr.i.log.warn('Could not send railway packet on $channel', error: e);
      }
      return null;
    }
  }
}
