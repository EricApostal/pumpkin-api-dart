// The factory gauge block and the part that registers it (`FactoryPanelBlock`), its configuration
// and connection payloads.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart' show ItemStackData;
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/link_keys.dart';
import '../host/player_items.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../model/stack.dart';
import 'factory_panel_behaviour.dart';
import 'factory_panel_block_entity.dart';

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

  final held = await Lg.i.read(e.item);
  if (held.key == 'create:factory_gauge') {
    final info = BlockStates.info(e.stateIndex);
    final slot = targetedSlot(e.cursor, info?.properties ?? const {});
    final added = be.addPanel(slot, null);
    if (added) {
      if (!e.sneaking) await consumeOneInHand(e.player, e.hand);
      return BlockUseResult.success;
    }
    return BlockUseResult.success;
  }

  // An empty hand or any other item opens the configuration screen on the client; the server
  // only needs to accept the click.
  return BlockUseResult.success;
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
    // `FactoryPanelConnectionPacket`.
    rt.bus.onServerbound('create:connect_factory_panel', (player, fields) {
      final to = FactoryPanelPosition.fromMap(fields['toPos']);
      final from = FactoryPanelPosition.fromMap(fields['fromPos']);
      if (to == null || from == null) return;
      final behaviour = FactoryPanelBehaviour.at(rt.playerWorldId(player), to);
      if (behaviour == null) return;
      // Relocation (`relocate`) moves a gauge to another slot; the connection itself is the
      // same. Only the connection is applied here.
      behaviour.addConnection(from);
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
