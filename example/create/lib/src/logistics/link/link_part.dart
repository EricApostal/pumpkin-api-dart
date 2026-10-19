// The stock link block and the part that registers it (`PackagerLinkBlock`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/link_keys.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import 'packager_link_block_entity.dart';

/// `PackagerLinkBlock`.
CreateBlock stockLinkBlock() => CreateBlock(
  key: 'create:stock_link',
  properties: [
    attachFaceProperty,
    horizontalFacingProperty,
    CreateProps.powered,
    CreateProps.waterlogged,
  ],
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  blockEntityType: PackagerLinkBlockEntity.type,
  behavior: BlockBehavior(
    onNeighborUpdate: _onNeighborUpdate,
    onPlaced: _onPlaced,
  ),
);

Future<void> _onNeighborUpdate(
  Server server,
  CustomBlockNeighborUpdateEventData e,
) async {
  final be = Lg.i.store.typed<PackagerLinkBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return;
  await be.refreshPower();
}

Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
  final uuid = e.player?.asString;
  if (uuid == null) return;
  final be = Lg.i.store.typed<PackagerLinkBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return;
  be.placedBy = uuid;
  be.notifyUpdate();
}

/// The `packager_link` part.
final class LinkPart extends LogisticsPart {
  @override
  String get name => 'link';

  @override
  void register(CreateRegistry registry) {
    registry.block(stockLinkBlock());
    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: PackagerLinkBlockEntity.type,
        validBlocks: ['create:stock_link'],
        create: PackagerLinkBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    // The global logistics data is loaded with the overworld (see the module).
    unawaited(Future<void>.value());
  }
}
