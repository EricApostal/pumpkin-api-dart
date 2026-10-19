// The server side of the chain conveyor payloads: `ChainConveyorConnectionPacket` (connect or
// remove a chain), `ChainPackageInteractionPacket` (put a package on / take it off a chain) and
// `ServerboundChainConveyorRidingPacket` (`ServerChainConveyorHandler`'s player list).
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../api/payloads.dart' show PayloadBus;
import '../../common/pos.dart';
import '../../common/vec_helper.dart' show AngleHelper;
import '../items/item_codec.dart';
import '../items/item_data.dart';
import '../runtime.dart';
import 'chain_conveyor_block_entity.dart';
import 'chain_conveyor_logic.dart';

/// Registers the serverbound handlers on the payload bus.
void installChainConveyorPackets(ConveyanceRuntime rt, PayloadBus bus) {
  bus.onServerbound('create:chain_conveyor_connect', (player, fields) {
    final pos = _posOf(fields['pos']);
    final targetPos = _posOf(fields['targetPos']);
    final connect = fields['connect'] == true;
    if (pos == null || targetPos == null) return;
    final kept = player.keep();
    unawaited(
      _connect(rt, kept, pos, targetPos, connect)
          .catchError((Object e, StackTrace s) {
            rt.log.error(
              'Handling a chain connection failed',
              error: e,
              stackTrace: s,
            );
          })
          .whenComplete(kept.dispose),
    );
  });

  bus.onServerbound('create:chain_package_interaction', (player, fields) {
    final pos = _posOf(fields['pos']);
    final rawConnection = _posOf(fields['selectedConnection']);
    final connection = rawConnection == posZero ? null : rawConnection;
    final chainPosition = (fields['chainPosition'] as num?)?.toDouble() ?? 0;
    final removing = fields['removingPackage'] == true;
    if (pos == null) return;
    final kept = player.keep();
    unawaited(
      _packageInteraction(rt, kept, pos, connection, chainPosition, removing)
          .catchError((Object e, StackTrace s) {
            rt.log.error(
              'Handling a chain package interaction failed',
              error: e,
              stackTrace: s,
            );
          })
          .whenComplete(kept.dispose),
    );
  });

  bus.onServerbound('create:chain_conveyor_riding', (player, fields) {
    final stop = fields['stop'] == true;
    final uuid = player.getId().asString;
    final entity = player.asEntity();
    entity.setFallDistance(distance: 0);
    entity.dispose();
    if (stop) {
      ServerChainConveyorHandler.handleStopRiding(uuid);
    } else {
      ServerChainConveyorHandler.handleTTL(uuid);
    }
  });
}

Pos? _posOf(Object? value) => value is (int, int, int) ? value : null;

Future<void> _connect(
  ConveyanceRuntime rt,
  Player player,
  Pos pos,
  Pos targetPos,
  bool connect,
) async {
  final world = player.getWorld();
  final worldId = rt.ctx.worlds.touch(world);
  world.dispose();
  final keptWorld = rt.worldOf(worldId);
  final maxRange = rt.maxChainConveyorLength + 16;
  if (!pos.closerThan(targetPos, (maxRange - 16 + 1).toDouble())) return;

  final be = rt.typedAt<ChainConveyorBlockEntity>(worldId, pos);
  if (be == null) return;
  final clbe = rt.typedAt<ChainConveyorBlockEntity>(worldId, targetPos);
  if (clbe == null) return;

  const chainKey = 'minecraft:iron_chain';
  if (connect && !player.isCreative) {
    final chainCost = getChainCost(targetPos - pos);
    final hasEnough = await be.getChainsFromInventory(
      player,
      chainKey,
      chainCost,
      simulate: true,
    );
    if (!hasEnough) return;
    await be.getChainsFromInventory(player, chainKey, chainCost);
  }

  if (!connect) {
    if (!player.isCreative) {
      var chainCost = getChainCost(targetPos - pos);
      while (chainCost > 0) {
        final count = math.min(chainCost, 64);
        await ItemCodec.giveToPlayer(player, ItemValue(chainKey, count));
        chainCost -= 64;
      }
    }
    be.chainDestroyed(targetPos - pos, false, true);
    keptWorld?.playSound(
      sound: Sound.blockChainBreak,
      category: SoundCategory.blocks,
      pos: (targetPos.x + .5, targetPos.y + .5, targetPos.z + .5),
      volume: 1,
      pitch: 1,
    );
  }

  if (connect) {
    if (!clbe.addConnectionTo(pos)) return;
  } else {
    clbe.removeConnectionTo(pos);
  }

  if (connect) {
    if (!be.addConnectionTo(targetPos)) clbe.removeConnectionTo(pos);
  } else {
    be.removeConnectionTo(targetPos);
  }
}

Future<void> _packageInteraction(
  ConveyanceRuntime rt,
  Player player,
  Pos pos,
  Pos? connection,
  double chainPosition,
  bool removing,
) async {
  final world = player.getWorld();
  final worldId = rt.ctx.worlds.touch(world);
  world.dispose();
  final be = rt.typedAt<ChainConveyorBlockEntity>(worldId, pos);
  if (be == null) return;

  if (removing) {
    var bestDiff = double.infinity;
    ChainConveyorPackage? best;
    final list = connection == null
        ? be.loopingPackages
        : be.travellingPackages[connection];
    if (list == null || list.isEmpty) return;

    for (final liftPackage in list) {
      final diff = connection == null
          ? AngleHelper.getShortestAngleDiff(
              liftPackage.chainPosition,
              chainPosition,
            ).abs()
          : (liftPackage.chainPosition - chainPosition).abs();
      if (diff > bestDiff) continue;
      bestDiff = diff;
      best = liftPackage;
    }
    if (best == null) return;

    await ItemCodec.giveToPlayer(player, best.item);
    list.remove(best);
    be.sendData();
    return;
  }

  final held = player.getItemInHand(hand: Hand.right);
  final value = held == null ? ItemValue.empty : await ItemCodec.read(held);
  if (value.isEmpty) {
    held?.dispose();
    return;
  }
  final box = ChainConveyorPackage(
    chainPosition,
    value,
    ChainConveyorPackage.nextNetId(),
  );

  if (!be.canAcceptPackagesFor(connection)) {
    held?.dispose();
    return;
  }

  if (!player.isCreative && held != null) {
    final count = await held.getCount();
    if (count <= 1) {
      await player.getInventory().setItemInHand(hand: Hand.right, item: null);
    } else {
      await held.setCount(count: count - 1);
    }
  }
  held?.dispose();

  if (connection == null) {
    be.addLoopingPackage(box);
  } else {
    be.addTravellingPackage(box, connection);
  }
}

/// `ServerChainConveyorHandler`: the players hanging on chains, with a short TTL that the
/// client refreshes each tick while it rides.
abstract final class ServerChainConveyorHandler {
  static final Map<String, int> hangingPlayers = {};
  static int ticks = 0;

  static void handleTTL(String uuid) {
    final count = hangingPlayers.length;
    hangingPlayers[uuid] = 20;
    if (hangingPlayers.length != count) sync();
  }

  static void handleStopRiding(String uuid) {
    final before = hangingPlayers.remove(uuid);
    if (before != null && before != 0) sync();
  }

  /// `tick()`: decrements the TTLs and syncs when a player left or every ten ticks.
  static void tick(ConveyanceRuntime rt) {
    ticks++;
    final before = hangingPlayers.length;
    hangingPlayers.removeWhere((_, ttl) => ttl - 1 <= 0);
    for (final key in hangingPlayers.keys) {
      hangingPlayers[key] = hangingPlayers[key]! - 1;
    }
    final after = hangingPlayers.length;
    if (ticks % 10 != 0 && before == after) return;
    sync();
  }

  static void sync() {
    if (!ConveyanceRuntime.loaded) return;
    final bus = ConveyanceRuntime.i.bus;
    if (bus == null) return;
    bus.sendClientboundAll(
      'create:clientbound_chain_conveyor',
      bus.roster.players,
      {
        'uuids': [for (final uuid in hangingPlayers.keys) uuid],
      },
    );
  }
}
