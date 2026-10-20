// The factory gauge block and the part that registers it (`FactoryPanelBlock`), its configuration
// and connection payloads.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/panel_support.dart';
import '../../api/payloads.dart' show ItemStackData;
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/link_keys.dart';
import '../host/player_items.dart';
import '../host/runtime.dart';
import '../link/linked_item.dart';
import '../logistics_part.dart';
import '../model/stack.dart';
import 'factory_panel_behaviour.dart';
import 'factory_panel_block_entity.dart';
import 'factory_panel_set_item_menu.dart';

/// `FactoryPanelBlock`.
CreateBlock factoryPanelBlock() => CreateBlock(
  key: 'create:factory_gauge',
  properties: [
    attachFaceProperty,
    horizontalFacingProperty,
    CreateProps.powered,
    CreateProps.waterlogged,
  ],
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'copper',
  canOcclude: false,
  blockEntityType: FactoryPanelBlockEntity.type,
  behavior: BlockBehavior(onUse: _onUse),
);

Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
  final be = Lg.i.store.typed<FactoryPanelBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return BlockUseResult.pass;

  // The clicked state (`useItemOn`'s `state` argument); `e.stateIndex` counts within the block.
  final info = BlockStates.info(e.targetWorld.getBlockStateId(pos: e.pos));
  final slot = targetedSlot(e.cursor, info?.properties ?? const {});
  final held = await _heldStack(e.player, e.hand);

  // `FactoryPanelBlock.useItemOn`: a gauge item adds a panel to an existing gauge block.
  if (held.key == 'create:factory_gauge') {
    if (!LinkedItem.isTuned(held)) return BlockUseResult.success;
    final fixed = LinkedItem.fixCtrlCopiedStack(
      held,
      fallbackFrequency: Lg.i.newUuid(),
    );
    final network = LinkedItem.networkFromStack(fixed);
    if (be.addPanel(slot, network) &&
        !e.sneaking &&
        e.player.getGamemode() != GameMode.creative) {
      await consumeOneInHand(e.player, e.hand);
    }
    return BlockUseResult.success;
  }

  final behaviour = be.panels[slot];
  if (behaviour == null || !behaviour.isActive) return BlockUseResult.pass;

  // `FactoryPanelBlock.onSneakWrenched`: a sneaking wrench removes just this gauge.
  if (e.sneaking && held.key == 'create:wrench') {
    if (be.removePanel(slot)) {
      if (e.player.getGamemode() != GameMode.creative) {
        await giveToPlayer(e.player, LStack.of('create:factory_gauge'));
      }
      if (be.activePanels() == 0) {
        await e.targetWorld.breakBlock(e.pos, drop: false);
      }
    }
    return BlockUseResult.success;
  }
  if (e.sneaking) return BlockUseResult.pass;

  // `FactoryPanelBehaviour.onShortInteract`: a wrench cycles the arrow path.
  if (held.key == 'create:wrench' &&
      (behaviour.targeting.isNotEmpty ||
          behaviour.targetedByLinks.isNotEmpty)) {
    _cycleArrowBend(behaviour);
    return BlockUseResult.success;
  }

  if (behaviour.filter.isEmpty) {
    // An empty hand opens the set-item screen (`FactoryPanelSetItemMenu`); another item is the
    // filter.
    if (held.isEmpty) {
      FactoryPanelSetItemMenus.open(
        e.player,
        FactoryPanelPosition(e.pos.toPos(), slot),
      );
      return BlockUseResult.success;
    }
    if (behaviour.interactWith(held) &&
        e.player.getGamemode() != GameMode.creative) {
      await consumeOneInHand(e.player, e.hand);
    }
    return BlockUseResult.success;
  }

  // A configured gauge binds a linked item to its network.
  if (_isLinkedItem(held.key)) {
    await _assignFrequency(e.player, e.hand, behaviour.network);
  }

  // Otherwise the client opens the configuration screen; the server only accepts the click.
  return BlockUseResult.success;
}

Future<LStack> _heldStack(Player player, Hand hand) async {
  final inventory = player.getInventory();
  try {
    final stack = inventory.getItemInHand(hand: hand);
    return stack == null ? LStack.empty : await Lg.i.read(stack);
  } finally {
    inventory.dispose();
  }
}

/// `LogisticallyLinkedBlockItem` subclasses (stock link, stock ticker, redstone requester).
bool _isLinkedItem(String key) =>
    key == 'create:stock_link' ||
    key == 'create:stock_ticker' ||
    key == 'create:redstone_requester';

Future<void> _assignFrequency(Player player, Hand hand, String network) async {
  final inventory = player.getInventory();
  try {
    final current = inventory.getItemInHand(hand: hand);
    if (current == null) return;
    final stack = await Lg.i.read(current);
    if (stack.isEmpty) return;
    final host = await Lg.i.write(LinkedItem.assignFrequency(stack, network));
    if (host != null) await inventory.setItemInHand(hand: hand, item: host);
  } finally {
    inventory.dispose();
  }
}

/// `FactoryPanelBehaviour.onShortInteract`'s wrench branch: every connection of the gauge cycles
/// through the four arrow bend modes together.
void _cycleArrowBend(FactoryPanelBehaviour behaviour) {
  var sharedMode = -1;
  var notifySelf = false;
  for (final target in behaviour.targeting) {
    final at = FactoryPanelBehaviour.at(behaviour.panelBE.worldId, target);
    if (at == null) continue;
    final connection = at.targetedBy[behaviour.getPanelPosition()];
    if (connection == null) continue;
    if (sharedMode == -1) sharedMode = (connection.arrowBendMode + 1) % 4;
    connection.arrowBendMode = sharedMode;
    at.panelBE.notifyUpdate();
  }
  for (final connection in behaviour.targetedByLinks.values) {
    if (sharedMode == -1) sharedMode = (connection.arrowBendMode + 1) % 4;
    connection.arrowBendMode = sharedMode;
    notifySelf = true;
  }
  if (notifySelf) behaviour.panelBE.notifyUpdate();
}

/// The `api/panel_support.dart` view of this module's gauges.
final class _FactoryPanelAccess implements FactoryPanelAccess {
  final LgRuntime rt;

  _FactoryPanelAccess(this.rt);

  @override
  FactoryPanelHandle? panelAt(String worldId, FactoryPanelPos position) {
    final slot = PanelSlot.byName(position.slot.serializedName);
    if (slot == null) return null;
    return FactoryPanelBehaviour.at(
      worldId,
      FactoryPanelPosition(position.pos, slot),
    );
  }
}

/// `FactoryPanelBlock.getTargetedSlot(pos, state, clickLocation)`, in local click coordinates.
PanelSlot targetedSlot(
  (double, double, double) localClick,
  Map<String, String> properties,
) {
  final face = properties['face'] ?? 'floor';
  final facing =
      Direction.byName(properties['facing'] ?? 'north') ?? Direction.north;
  final xRot = face == 'ceiling'
      ? math.pi / 2
      : (face == 'floor' ? -math.pi / 2 : 0.0);
  final yRot = (face == 'ceiling' ? math.pi : 0.0) + _horizontalAngle(facing);

  var bestDistance = double.maxFinite;
  var bestSlot = PanelSlot.bottomLeft;
  for (final slot in PanelSlot.values) {
    var vec = (0.25 + slot.xOffset * 0.5, 0.0, 0.25 + slot.yOffset * 0.5);
    vec = _rotateCentered(vec, math.pi, Axis.y);
    vec = _rotateCentered(vec, xRot + math.pi / 2, Axis.x);
    vec = _rotateCentered(vec, yRot, Axis.y);
    final dx = vec.$1 - localClick.$1,
        dy = vec.$2 - localClick.$2,
        dz = vec.$3 - localClick.$3;
    final diff = dx * dx + dy * dy + dz * dz;
    if (diff > bestDistance) continue;
    bestDistance = diff;
    bestSlot = slot;
  }
  return bestSlot;
}

double _horizontalAngle(Direction d) => switch (d) {
  Direction.south => 0,
  Direction.west => math.pi / 2,
  Direction.north => math.pi,
  Direction.east => -math.pi / 2,
  _ => 0,
};

(double, double, double) _rotateCentered(
  (double, double, double) p,
  double radians,
  Axis axis,
) {
  final x = p.$1 - 0.5, y = p.$2 - 0.5, z = p.$3 - 0.5;
  final c = math.cos(radians), s = math.sin(radians);
  final (double, double, double) r = switch (axis) {
    Axis.x => (x, y * c - z * s, y * s + z * c),
    Axis.y => (x * c + z * s, y, -x * s + z * c),
    Axis.z => (x * c - y * s, x * s + y * c, z),
  };
  return (r.$1 + 0.5, r.$2 + 0.5, r.$3 + 0.5);
}

/// The `factory` part.
final class FactoryPart extends LogisticsPart {
  @override
  String get name => 'factory';

  @override
  void register(CreateRegistry registry) {
    registry.block(factoryPanelBlock());
    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: FactoryPanelBlockEntity.type,
        validBlocks: ['create:factory_gauge'],
        create: FactoryPanelBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    ctx.services.provide<FactoryPanelAccess>(_FactoryPanelAccess(rt));
    FactoryPanelSetItemMenus.install(ctx, rt);

    // `FactoryPanelConnectionPacket`.
    rt.bus.onServerbound('create:connect_factory_panel', (player, fields) {
      final to = FactoryPanelPosition.fromMap(fields['toPos']);
      final from = FactoryPanelPosition.fromMap(fields['fromPos']);
      if (to == null || from == null) return;
      final behaviour = FactoryPanelBehaviour.at(rt.playerWorldId(player), to);
      if (behaviour == null) return;
      if (fields['relocate'] == true) {
        unawaited(behaviour.moveTo(from, player));
      } else {
        behaviour.addConnection(from);
      }
    });

    // `FactoryPanelConfigurationPacket`.
    rt.bus.onServerbound('create:configure_factory_panel', (player, fields) {
      final position = FactoryPanelPosition.fromMap(fields['position']);
      if (position == null) return;
      final be = rt.store.typed<FactoryPanelBlockEntity>(
        rt.playerWorldId(player),
        position.pos.toBlockPos(),
      );
      final behaviour = be?.panels[position.slot];
      if (behaviour == null) return;

      final reset = fields['reset'] == true;
      behaviour.recipeAddress = reset
          ? ''
          : (fields['address'] as String? ?? '');
      behaviour.recipeOutput = reset
          ? 1
          : (fields['outputAmount'] as int? ?? 1);
      behaviour.promiseClearingInterval = reset
          ? -1
          : (fields['promiseClearingInterval'] as int? ?? -1);
      behaviour.activeCraftingArrangement = reset
          ? []
          : [
              for (final s
                  in (fields['craftingArrangement'] as List<dynamic>? ??
                      const []))
                if (s is ItemStackData) rt.wire.fromData(s),
            ];

      if (reset) {
        behaviour.forceClearPromises = true;
        behaviour.disconnectAll();
        behaviour.setFilter(LStack.empty);
        behaviour.count = 0;
        be!.redraw = true;
        be.notifyUpdate();
        return;
      }

      if (fields['redstoneReset'] == true) {
        behaviour.disconnectAllLinks();
        be!.notifyUpdate();
        return;
      }

      final inputAmounts = fields['inputAmounts'];
      if (inputAmounts is Map) {
        for (final entry in inputAmounts.entries) {
          final key = FactoryPanelPosition.fromMap(entry.key);
          if (key == null) continue;
          final connection = behaviour.targetedBy[key];
          if (connection == null) continue;
          connection.amount = entry.value is int
              ? entry.value as int
              : connection.amount;
        }
      }

      final removeConnection = FactoryPanelPosition.fromMap(
        fields['removeConnection'],
      );
      if (removeConnection != null) {
        behaviour.targetedBy.remove(removeConnection);
        final source = FactoryPanelBehaviour.at(
          rt.playerWorldId(player),
          removeConnection,
        );
        if (source != null) {
          source.targeting.remove(behaviour.getPanelPosition());
          source.panelBE.sendData();
        }
      }

      if (fields['clearPromises'] == true) behaviour.forceClearPromises = true;
      be!.notifyUpdate();
    });
  }
}
