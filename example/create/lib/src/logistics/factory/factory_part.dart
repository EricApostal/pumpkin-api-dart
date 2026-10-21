// The factory gauge block and the part that registers it (`FactoryPanelBlock`), its configuration
// and connection payloads.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
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
import '../host/shapes.dart';
import '../host/state_props.dart';
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
  // `FactoryPanelBlock.getCollisionShape`: entities pass through the thin panel; only the
  // selection shape (below) is real. `FactoryPanelBlock.getStateForPlacement` needs the clicked
  // face, which a placement rule cannot map to `face`, so [onCanPlace] computes it.
  collisionShape: BlockShape.empty,
  placement: const [PlacementRule.horizontalFacing('facing')],
  blockEntityType: FactoryPanelBlockEntity.type,
  behavior: BlockBehavior(
    onUse: _onUse,
    onCanPlace: _onCanPlace,
    onPlaced: _onPlaced,
    onShape: _onShape,
  ),
);

/// A gauge placement computed from the clicked face, kept until the `player-placed` event (the
/// host has no state-for-placement hook).
final Map<String, _GaugePlacement> _pendingGaugePlacements = {};

final class _GaugePlacement {
  final BState state;
  final String player;

  const _GaugePlacement(this.state, this.player);
}

String _gaugePlacementKey(World world, Pos pos) =>
    '${world.getId()}:${pos.$1},${pos.$2},${pos.$3}';

Direction _dirOf(BlockDirection d) => Direction.values[d.index];

/// `FactoryPanelBlock.canAttachLenient`: the neighbour behind the panel has a collision shape.
bool _canAttachLenient(BlockGetter level, Pos pos, BState state) {
  final connected = faceConnectedDirection(state.props);
  return !level.collisionShapeEmpty(pos.relative(connected.opposite));
}

/// `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement` plus
/// `FactoryPanelBlock.getStateForPlacement`'s floor flip: the first nearest-looking direction
/// whose support has a collision shape (the direction towards the clicked block first, like
/// `BlockPlaceContext.getNearestLookingDirections`).
BState? _gaugeStateForPlacement(
  World world,
  Pos pos,
  Player player,
  Direction support,
) {
  final level = HostBlockGetter(world);
  return faceAttachedStateForPlacement(
    'create:factory_gauge',
    look: player.lookDirection,
    yaw: player.getYaw(),
    towardsClicked: support,
    canAttach: (state) => _canAttachLenient(level, pos, state),
    waterlogged: level.isWater(pos),
    adjust: (state) => state['face'] == 'floor'
        ? state.setDir('facing', state.dir('facing')!.opposite)
        : state,
  );
}

Future<bool> _onCanPlace(Server server, CustomBlockCanPlaceEventData e) async {
  if (!e.canPlace || e.player == null || e.face == null) return e.canPlace;
  final player = Lg.i.player(e.player!.asString);
  if (player == null) return true;
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final fixed = _gaugeStateForPlacement(world, pos, player, _dirOf(e.face!));
  if (fixed == null) return false;
  _pendingGaugePlacements[_gaugePlacementKey(world, pos)] = _GaugePlacement(
    fixed,
    e.player!.asString,
  );
  return true;
}

/// `FactoryPanelBlock.setPlacedBy`: fixes the state computed in [onCanPlace] and adds the first
/// gauge at the clicked quarter with the network of the held item.
Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
  if (e.player == null) return;
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final key = _gaugePlacementKey(world, pos);
  final pending = _pendingGaugePlacements.remove(key);
  // A placement the host did not announce (or a state change of an existing gauge): leave it.
  if (pending == null || pending.player != e.player!.asString) return;

  final info = BlockStates.info(world.getBlockStateId(pos: e.pos));
  if (info?.key != 'create:factory_gauge') return;
  final current = BState('create:factory_gauge', info!.properties);
  final differs = current.props.length != pending.state.props.length ||
      current.props.entries.any(
        (entry) => pending.state.props[entry.key] != entry.value,
      );
  if (differs) await setBlockState(world, pos, pending.state);

  final be = Lg.i.store.typed<FactoryPanelBlockEntity>(world.getId(), e.pos);
  if (be == null) return;
  final player = Lg.i.player(e.player!.asString);
  final slot =
      _clickedSlot(world, pos, player, pending.state) ?? PanelSlot.bottomLeft;
  be.addPanel(slot, player == null ? null : await _heldNetwork(player));
}

/// `p.getTargetedSlot(pos, state, clickLocation)` from the player's current ray.
PanelSlot? _clickedSlot(
  World world,
  Pos pos,
  Player? player,
  BState state,
) {
  if (player == null) return null;
  final eye = player.eyePosition;
  final look = player.lookDirection;
  final hit = world.rayTraceBlock(
    start: eye,
    end: eye + look * 6,
    includeFluids: false,
  );
  if (hit == null ||
      hit.pos.x != pos.$1 ||
      hit.pos.y != pos.$2 ||
      hit.pos.z != pos.$3) {
    return null;
  }
  return targetedSlot(
    (
      hit.hitPos.$1 - pos.$1,
      hit.hitPos.$2 - pos.$2,
      hit.hitPos.$3 - pos.$3,
    ),
    state.props,
  );
}

/// `LogisticallyLinkedBlockItem.networkFromStack(pStack)` of the placed item.
Future<String?> _heldNetwork(Player player) async {
  final inventory = player.getInventory();
  try {
    for (final hand in [Hand.right, Hand.left]) {
      final held = inventory.getItemInHand(hand: hand);
      if (held == null) continue;
      final network = LinkedItem.networkFromStack(await Lg.i.read(held));
      if (network != null) return network;
    }
  } finally {
    inventory.dispose();
  }
  return null;
}

/// `FactoryPanelBlock.getShape`: the panels of the block entity, or the fallback slab when the
/// entity is not there. The collision shape stays empty (entities pass through).
Future<List<BlockBox>?> _onShape(
  Server server,
  CustomBlockShapeEventData e,
) async {
  if (e.kind == BlockShapeKind.collision) return null;
  final be = Lg.i.store.typed<FactoryPanelBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be != null) return be.getShape();
  final info = BlockStates.info(e.targetWorld.getBlockStateId(pos: e.pos));
  final props = info?.properties ?? const <String, String>{};
  final connected = faceConnectedDirection(props);
  return rotateBoxes(
    const [BlockBox(0, 0, 0, 1, 2 / 16, 1)],
    Direction.up,
    connected,
  );
}

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
      await FactoryPanelSetItemMenus.open(
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

/// `AngleHelper.horizontalAngle` (`Direction.toYRot`, negated on the x axis): south 0, west -90,
/// north 180, east 90 degrees.
double _horizontalAngle(Direction d) => switch (d) {
  Direction.south => 0,
  Direction.west => -math.pi / 2,
  Direction.north => math.pi,
  Direction.east => math.pi / 2,
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
