// The redstone requester block and the part that registers it (`RedstoneRequesterBlock`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import 'redstone_requester_block_entity.dart';

/// `axis` of the redstone requester (manifest value order).
final BlockProperty requesterAxis = BlockProperty.enumeration('axis', [
  'x',
  'z',
]);

/// `RedstoneRequesterBlock`.
CreateBlock redstoneRequesterBlock() => CreateBlock(
  key: 'create:redstone_requester',
  properties: [requesterAxis, CreateProps.powered],
  hardness: 1.5,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  canOcclude: false,
  blockEntityType: RedstoneRequesterBlockEntity.type,
  behavior: BlockBehavior(
    onNeighborUpdate: _onNeighborUpdate,
    onPlaced: _onPlaced,
    onUse: _onUse,
    onComparatorOutput: _comparator,
  ),
);

Future<void> _onNeighborUpdate(
  Server server,
  CustomBlockNeighborUpdateEventData e,
) async {
  final be = Lg.i.store.typed<RedstoneRequesterBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return;
  final powered = await e.targetWorld.hasRedstoneNeighborSignal(e.pos);
  final stateId = e.targetWorld.getBlockStateId(pos: e.pos);
  final info = BlockStates.info(stateId);
  if ((info?.properties['powered'] == 'true') != powered) {
    await e.targetWorld.setBlockState(
      pos: e.pos,
      state: BlockStates.setValues(stateId, {
        'powered': powered ? 'true' : 'false',
      }),
      updateFlags: BlockUpdateFlags.clientsOnly,
    );
  }
  be.onRedstonePowerChanged();
}

Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
  final uuid = e.player?.asString;
  if (uuid == null) return;
  final player = Lg.i.player(uuid);
  if (player == null) return;
  final yaw = player.getYaw();
  final horizontal = ((yaw % 360) + 360) % 360;
  final axis =
      (horizontal >= 45 && horizontal < 135) ||
          (horizontal >= 225 && horizontal < 315)
      ? 'z'
      : 'x';
  final world = e.targetWorld;
  await world.setBlockState(
    pos: e.pos,
    state: BlockStates.setValues(world.getBlockStateId(pos: e.pos), {
      'axis': axis,
    }),
    updateFlags: BlockUpdateFlags.clientsOnly,
  );
}

Future<int?> _comparator(
  Server server,
  CustomBlockComparatorOutputEventData e,
) async {
  final be = Lg.i.store.typed<RedstoneRequesterBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  return be != null && be.lastRequestSucceeded ? 15 : 0;
}

Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
  final be = Lg.i.store.typed<RedstoneRequesterBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return BlockUseResult.pass;
  if (e.sneaking) return BlockUseResult.pass;
  if (!be.behaviour.mayInteract(e.player.getId().asString))
    return BlockUseResult.success;
  // The configuration screen is client side; nothing else happens on use.
  return BlockUseResult.success;
}

/// The `requester` part.
final class RequesterPart extends LogisticsPart {
  @override
  String get name => 'requester';

  @override
  void register(CreateRegistry registry) {
    registry.block(redstoneRequesterBlock());
    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: RedstoneRequesterBlockEntity.type,
        validBlocks: ['create:redstone_requester'],
        create: RedstoneRequesterBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    // `RedstoneRequesterConfigurationPacket`.
    rt.bus.onServerbound('create:configure_redstone_requester', (
      player,
      fields,
    ) {
      final pos = fields['pos'] as Pos;
      final be = rt.store.typed<RedstoneRequesterBlockEntity>(
        rt.playerWorldId(player),
        pos.toBlockPos(),
      );
      if (be == null) return;
      if (!be.behaviour.mayInteract(player.getId().asString)) return;

      be.encodedTargetAdress = fields['address'] as String? ?? '';
      final amounts = fields['amounts'];
      final stacks = be.encodedRequest.stacks;
      if (amounts is List) {
        for (var i = 0; i < stacks.length && i < amounts.length; i++) {
          final amount = amounts[i];
          if (amount is! int || stacks[i].stack.isEmpty) continue;
          stacks[i] = BigStack(stacks[i].stack, amount);
        }
      }
      if (!be.encodedRequest.orderedStacksMatchOrderedRecipes()) {
        be.encodedRequest = PackageOrderWithCrafts.simple(
          be.encodedRequest.stacks,
        );
      }
      be.allowPartialRequests = fields['allowPartial'] == true;
      be.sendData();
    });
  }
}
