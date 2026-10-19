// The package port blocks (frogport, postboxes) and the part that registers them, plus the
// configuration and placement payloads (`PackagePortConfigurationPacket`,
// `PackagePortPlacementPacket`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/link_keys.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import 'package_port_block_entity.dart';
import 'package_port_target.dart';

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
  behavior: BlockBehavior(onUse: _onUse),
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
  behavior: BlockBehavior(onUse: _onUse),
);

Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
  final be = Lg.i.store.typed<PackagePortBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return BlockUseResult.pass;
  if (e.sneaking) return BlockUseResult.tryEmptyHand;
  // The address configuration screen is client side.
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

      be.target = target;
      be.sendData();
    });
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
