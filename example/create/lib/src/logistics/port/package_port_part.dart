// The package port blocks (frogport, postboxes) and the part that registers them, plus the
// configuration and placement payloads (`PackagePortConfigurationPacket`,
// `PackagePortPlacementPacket`).
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/trains.dart'
    show GlobalStation, SchedulePortInventories, StationPackagePorts;
import '../../api/util.dart' hide pos;
import '../../conveyance/chain/chain_conveyor_block_entity.dart';
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/link_keys.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import 'mail_transfer_hooks.dart';
import 'package_port_block_entity.dart';
import 'package_port_target.dart';
import 'port_inventories.dart';
import 'station_ports.dart';

/// The postbox colours (`AllBlocks.PACKAGE_POSTBOXES`).
const List<String> postboxColors = [
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
];

/// `FrogportBlock`.
CreateBlock frogportBlock() => CreateBlock(
  key: 'create:package_frogport',
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  canOcclude: false,
  blockEntityType: FrogportBlockEntity.type,
  behavior: BlockBehavior(
    onUse: _onUse,
    onPlaced: _onFrogportPlaced,
    onComparatorOutput: _comparator,
  ),
);

/// `PostboxBlock`.
CreateBlock postboxBlock(String color) => CreateBlock(
  key: 'create:${color}_postbox',
  properties: [
    horizontalFacingProperty,
    CreateProps.open,
    CreateProps.waterlogged,
  ],
  hardness: 2,
  blastResistance: 2,
  soundType: 'wood',
  blockEntityType: PostboxBlockEntity.type,
  placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
  behavior: BlockBehavior(
    onUse: _onUse,
    onComparatorOutput: _comparator,
    onPlaced: (server, e) async => _requestPortTarget(e),
  ),
);

/// `PackagePortItem.place` (the item of both the frogport and the postboxes): after the port is
/// placed, ask the client to flush its target selection
/// (`PackagePortTargetSelectionHandler.flushSettings`), which then sends
/// `create:place_package_port`. Without it a port is placed address-less.
void _requestPortTarget(CustomBlockPlacedEventData e) {
  final uuid = e.player?.asString;
  if (uuid == null) return;
  final player = Lg.i.player(uuid);
  if (player == null) return;
  Lg.i.bus.sendClientbound('create:s_place_package_port', player, {
    'pos': (e.pos.x, e.pos.y, e.pos.z),
  });
}

/// `FrogportBlock.setPlacedBy`: the port looks at the player that placed it.
Future<void> _onFrogportPlaced(
  Server server,
  CustomBlockPlacedEventData e,
) async {
  _requestPortTarget(e);
  final uuid = e.player?.asString;
  if (uuid == null) return;
  final player = Lg.i.player(uuid);
  if (player == null) return;
  final be = Lg.i.store.typed<FrogportBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return;
  final (px, _, pz) = player.getPosition();
  final dx = e.pos.x + 0.5 - px;
  final dz = e.pos.z + 0.5 - pz;
  final yaw = math.atan2(dx, dz) * 180 / math.pi;
  be.passiveYaw = (yaw / 11.25).round() * 11.25;
  be.sendData();
}

Future<int?> _comparator(
  Server server,
  CustomBlockComparatorOutputEventData e,
) async {
  final be = Lg.i.store.typed<PackagePortBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  return be?.comparatorOutput ?? 0;
}

Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
  final be = Lg.i.store.typed<PackagePortBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return BlockUseResult.pass;
  // `FrogportBlock.useItemOn` / `PostboxBlock.useItemOn`: `be.use(player)` handles the clipboard
  // and opens the address screen.
  if (!await be.use(e.player)) return BlockUseResult.tryEmptyHand;
  return BlockUseResult.success;
}

/// The `port` part.
final class PortPart extends LogisticsPart {
  @override
  String get name => 'port';

  @override
  void register(CreateRegistry registry) {
    registry.block(frogportBlock());
    for (final color in postboxColors) {
      registry.block(postboxBlock(color));
    }

    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: FrogportBlockEntity.type,
        validBlocks: ['create:package_frogport'],
        create: FrogportBlockEntity.new,
        tickInterval: 1,
      ),
    );
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: PostboxBlockEntity.type,
        validBlocks: [
          for (final color in postboxColors) 'create:${color}_postbox',
        ],
        create: PostboxBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    // `GlobalStation.runMailTransfer` moves the packages between a train at the station and the
    // connected postboxes: `PackageItem`, the postbox lookup and the carriages' item storage are
    // this module's, so it provides the hooks the trains module leaves unset.
    GlobalStation.mailHooks = PortMailTransferHooks(rt);
    // `StationBlockEntity.attachPackagePort`: the station keeps the postbox' offline buffer.
    ctx.services.provide<StationPackagePorts>(PostboxStationPorts());
    // `FetchPackagesInstruction.start` reads the packages of a station's ports through this
    // (`TrainHost.ports`); without it every station looks package-free.
    ctx.services.provide<SchedulePortInventories>(
      PortPackageInventories(
        inventoryAt: (dimension, pos) {
          final postbox = rt.store.typed<PostboxBlockEntity>(
            dimension,
            pos.toBlockPos(),
          );
          return postbox == null ? null : PostboxPackageInventory(postbox);
        },
        hasDimension: (dimension) => rt.world(dimension) != null,
      ),
    );

    // `PackagePortConfigurationPacket`.
    rt.bus.onServerbound('create:package_port_configuration', (player, fields) {
      final pos = fields['pos'] as Pos;
      final be = rt.store.typed<PackagePortBlockEntity>(
        rt.playerWorldId(player),
        pos.toBlockPos(),
      );
      if (be == null) return;
      final newFilter = fields['newFilter'] as String? ?? '';
      final acceptPackages = fields['acceptPackages'] == true;
      if (be.addressFilter == newFilter && be.acceptsPackages == acceptPackages)
        return;
      be.addressFilter = newFilter;
      be.acceptsPackages = acceptPackages;
      be.filterChanged();
      be.sendData();
    });

    // `PackagePortPlacementPacket`.
    rt.bus.onServerbound('create:place_package_port', (player, fields) {
      final pos = fields['pos'] as Pos;
      final target = decodeTarget(fields['target']);
      if (target == null) return;
      final worldId = rt.playerWorldId(player);
      final be = rt.store.typed<PackagePortBlockEntity>(
        worldId,
        pos.toBlockPos(),
      );
      if (be == null) return;
      if (!target.canSupport(be.blockKey)) return;

      final absolute = pos + target.relativePos;
      final dx = absolute.$1 - pos.$1,
          dy = absolute.$2 - pos.$2,
          dz = absolute.$3 - pos.$3;
      final distanceSq = dx * dx + dy * dy + dz * dz;
      final limit = rt.packagePortRange + 2;
      if (distanceSq > limit * limit) return;

      // `PackagePortTarget.setup`: a chain conveyor target remembers which way the chain runs, so
      // a reversed chain does not send packages the wrong way round.
      var resolved = target;
      if (target.type == PackagePortTargetType.chainConveyor) {
        final chain = rt.store.typed<ChainConveyorBlockEntity>(
          worldId,
          (pos + target.relativePos).toBlockPos(),
        );
        if (chain != null) resolved = target.withFlipped(chain.speed < 0);
      }

      be.target = resolved;
      be.sendData();
      // `ppbe.use(player)`: the port opens its screen right after it was pointed at a target.
      unawaited(be.use(player));
    });
  }

  @override
  void onUnload() {
    // The runtime the hooks read is going away with this module.
    GlobalStation.mailHooks = null;
  }
}

/// The `PackagePortTarget` of a decoded placement payload.
PackagePortTarget? decodeTarget(Object? value) {
  if (value is! Map) return null;
  if (value.containsKey('type')) return PackagePortTarget.fromMap(value);

  final chain = value['create:chain_conveyor'];
  if (chain is Map) {
    final relative = chain['relativePos'];
    if (relative is! List || relative.length != 3) return null;
    final connection = chain['connection'];
    return PackagePortTarget(
      PackagePortTargetType.chainConveyor,
      (relative[0] as int, relative[1] as int, relative[2] as int),
      chainPos: (chain['chainPos'] as num?)?.toDouble() ?? 0,
      connection: connection is List && connection.length == 3
          ? (connection[0] as int, connection[1] as int, connection[2] as int)
          : null,
      flipped: chain['flipped'] == true,
    );
  }

  final station = value['create:train_station'];
  if (station is List && station.length == 3) {
    return PackagePortTarget(PackagePortTargetType.trainStation, (
      station[0] as int,
      station[1] as int,
      station[2] as int,
    ));
  }
  return null;
}
