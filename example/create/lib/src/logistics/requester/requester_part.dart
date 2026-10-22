// The redstone requester block and the part that registers it (`RedstoneRequesterBlock`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/player_items.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import 'redstone_requester_block_entity.dart';
import 'redstone_requester_menu.dart';

/// `axis` of the redstone requester (manifest value order).
final BlockProperty requesterAxis = BlockProperty.enumeration('axis', [
  'x',
  'z',
]);

/// `RedstoneRequesterBlock`.
CreateBlock redstoneRequesterBlock() => CreateBlock(
  key: 'create:redstone_requester',
  mapColor: manifestMapColor('redstone_requester'),
  properties: [requesterAxis, CreateProps.powered],
  hardness: 1.5,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  canOcclude: false,
  blockEntityType: RedstoneRequesterBlockEntity.type,
  // `getStateForPlacement`: `pContext.getHorizontalDirection().getAxis()`.
  placement: const [PlacementRule.horizontalAxis('axis')],
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
  // `RedstoneRequesterBlock.setPlacedBy`: a requester placed from an item that was programmed at
  // a stock keeper keeps the order and the address of the item.
  final uuid = e.player?.asString;
  final player = uuid == null ? null : Lg.i.player(uuid);
  if (player != null) {
    final be = Lg.i.store.typed<RedstoneRequesterBlockEntity>(
      e.targetWorld.getId(),
      e.pos,
    );
    final data = await heldRequestData(player);
    if (be != null && data != null) {
      final read = data.readFromItem(e.pos.toPos(), e.targetWorld.getId());
      be.setRequestData(read);
      player.showActionbar(
        text: TextComponent.translate(
          key: read.isValid
              ? 'create.redstone_requester.keeper_connected'
              : 'create.redstone_requester.keeper_too_far_away',
          with_: const [],
        ),
      );
    }
  }

  // `RedstoneRequesterBlock.getStateForPlacement`: `POWERED` is the neighbour signal at the
  // placement position (the axis comes from the `horizontalAxis` placement rule).
  if (!await e.targetWorld.hasNeighborSignal(pos: e.pos)) return;
  final stateId = e.targetWorld.getBlockStateId(pos: e.pos);
  final info = BlockStates.info(stateId);
  if (info?.properties['powered'] == 'true') return;
  await e.targetWorld.setBlockState(
    pos: e.pos,
    state: BlockStates.setValues(stateId, {'powered': 'true'}),
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
  if (!be.behaviour.mayInteract(e.player.getId().asString)) {
    // `LogisticallyLinkedBehaviour.mayInteractMessage`.
    e.player.sendSystemMessage(
      text: TextComponent.translate(
        key: 'create.logistically_linked.protected',
        with_: const [],
      ),
      overlay: true,
    );
    return BlockUseResult.success;
  }
  // `RedstoneRequesterBlockEntity.use`: the configuration screen
  // (`RedstoneRequesterMenu`, opened with the block position as extra data).
  await RedstoneRequesterMenus.open(e.player, be, e.targetWorld.getId());
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

    // The screen itself (`RedstoneRequesterMenu`).
    RedstoneRequesterMenus.install(ctx, rt);
  }
}
