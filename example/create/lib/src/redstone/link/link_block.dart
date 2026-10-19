// `RedstoneLinkBlock` and `RedstoneLinkBlockEntity`: the wireless redstone link, a
// transmitter (reads redstone around it) or a receiver (outputs the network strength).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/panel_support.dart';
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../support/level.dart';
import '../support/manifest_block.dart';
import '../support/rs_runtime.dart';
import '../support/shapes.dart';
import 'link_behaviour.dart';
import 'link_slots.dart';

Direction _facing(Map<String, String> p) => Direction.byName(p['facing'] ?? 'north') ?? Direction.north;

/// `RedstoneLinkBlockEntity`.
final class RedstoneLinkBlockEntity extends CreateBlockEntity {
  static const String type = 'create:redstone_link';

  bool receivedSignalChanged = false;
  int receivedSignal = 0;
  int transmittedSignal = 0;
  bool transmitter = false;

  late final PanelSupportBehaviour panelSupport;
  late final LinkBehaviour link;

  RedstoneLinkBlockEntity(super.worldId, super.pos) {
    panelSupport = addBehaviour(
      PanelSupportBehaviour.of(
        Rs.i.ctx,
        isOutput: () => link.isListening,
        outputPower: () => receivedSignal > 0,
        onNotify: _updateTransmittedSignal,
      ),
    );
    link = addBehaviour(
      LinkBehaviour.switchable(
        handler: () => Rs.i.links,
        slotTest: _slotTest,
        transmitter: false,
        transmission: () => transmittedSignal,
        signalCallback: setSignal,
      ),
    );
  }

  bool _slotTest(bool first, Vec3 localHit) {
    final props = world == null ? null : Lvl(world!).info(pos.toPos())?.properties;
    final facing = props == null ? Direction.north : _facing(props);
    return frequencySlotHit(facing, localHit, first: first);
  }

  void _updateTransmittedSignal() {
    final w = world;
    if (w == null) return;
    unawaited(RedstoneLinkBlock.updateTransmittedSignal(Lvl(w), pos.toPos()));
  }

  /// `getSignal`.
  int get signal => transmittedSignal;

  /// `setSignal`.
  void setSignal(int power) {
    if (receivedSignal != power) receivedSignalChanged = true;
    receivedSignal = power;
  }

  /// `transmit`.
  void transmit(int strength) {
    transmittedSignal = strength;
    link.notifySignalChange();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('Transmitter', transmitter);
    tag.putInt('Receive', receivedSignal);
    tag.putBool('ReceivedChanged', receivedSignalChanged);
    tag.putInt('Transmit', transmittedSignal);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    transmitter = tag.getBool('Transmitter') ?? false;
    link.switchMode(transmitter: transmitter, rejoin: false);
    super.read(tag, clientPacket: clientPacket);

    receivedSignal = tag.getInt('Receive') ?? 0;
    receivedSignalChanged = tag.getBool('ReceivedChanged') ?? false;
    if (!link.newPosition) transmittedSignal = tag.getInt('Transmit') ?? 0;
  }

  @override
  void tick() {
    super.tick();
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);
    final p = pos.toPos();
    final info = lvl.info(p);
    if (info == null || info.key != 'create:redstone_link') return;

    final shouldTransmit = info.properties['receiver'] != 'true';
    if (shouldTransmit != transmitter) {
      transmitter = shouldTransmit;
      link.switchMode(transmitter: transmitter);
    }

    if (transmitter) return;

    final powered = info.properties['powered'] == 'true';
    if ((receivedSignal > 0) != powered) {
      receivedSignalChanged = true;
      unawaited(lvl.setProps(p, {'powered': '${!powered}'}, neighbors: true));
    }

    if (receivedSignalChanged) unawaited(updateSelfAndAttached(lvl, info.properties));
  }

  /// `updateSelfAndAttached`: the strength changed, so the link, the block it sits on and
  /// their neighbours re-read it.
  Future<void> updateSelfAndAttached(Lvl lvl, Map<String, String> props) async {
    final attachedPos = pos.toPos().relative(_facing(props).opposite);
    sendData();
    await lvl.updateNeighbors(pos.toPos());
    await lvl.updateNeighbors(attachedPos);
    receivedSignalChanged = false;
    panelSupport.notifyPanels();
  }

  @override
  void onRemoved() {
    super.onRemoved();
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);
    final p = pos.toPos();
    // The block is gone: its former neighbours re-read their input.
    unawaited(lvl.updateNeighbors(p));
    panelSupport.notifyPanels();
  }
}

/// `RedstoneLinkBlock`.
final class RedstoneLinkBlock {
  static const String key = 'redstone_link';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      blockEntityType: RedstoneLinkBlockEntity.type,
      placement: const [PlacementRule.clickedFace('facing')],
      shapeRules: [
        // REDSTONE_BRIDGE: the tablet facing south; vertical links use the square tablet.
        ...directionalShapeRules('facing', [pixelBox(3, 1, 0, 13, 15, 3)], Direction.south, directions: Direction.horizontals),
        ...directionalShapeRules('facing', [pixelBox(2, 2, 0, 14, 14, 3)], Direction.south, directions: [Direction.up, Direction.down]),
      ],
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _onNeighborUpdate,
        onScheduledTick: _onTick,
        onCanPlace: (server, e) {
          final face = e.face?.toDirection();
          if (face == null) return e.canPlace;
          return e.canPlace && !Lvl(e.targetWorld).canBeReplaced(e.pos.toPos().relative(face.opposite));
        },
        onWeakPower: (server, e) => _received(e),
        onStrongPower: (server, e) {
          final p = block.stateOf(e.stateIndex);
          // getDirectSignal: only towards the facing side.
          if (e.face.toDirection().opposite != _facing(p)) return 0;
          return _received(e);
        },
        canConnectRedstone: (server, e) => e.direction != null,
        onUse: _onUse,
        isPathfindable: (server, e) => false,
      ),
    );
    return block;
  }

  int _received(CustomBlockRedstonePowerEventData e) {
    if (block.stateOf(e.stateIndex)['receiver'] != 'true') return 0;
    return Rs.i.be<RedstoneLinkBlockEntity>(e.targetWorld, e.pos)?.receivedSignal ?? 0;
  }

  BlockEntityTypeSpec entitySpec() => BlockEntityTypeSpec(
    key: RedstoneLinkBlockEntity.type,
    validBlocks: const ['create:redstone_link'],
    create: RedstoneLinkBlockEntity.new,
    tickInterval: 1,
  );

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    // onPlace: a block that is moving (a contraption) does not update.
    if (e.moved) return;
    await updateTransmittedSignal(lvl, e.pos.toPos());
  }

  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final props = lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex);
    final facing = _facing(props);
    // The block it hangs on changed: break when nothing carries the link any more.
    if (e.sourcePos.toPos() == pos.relative(facing.opposite)) {
      if (!canSurvive(lvl, pos, facing)) {
        await lvl.destroyBlock(pos);
        return;
      }
    }
    lvl.scheduleTick(pos, 1);
  }

  /// `canSurvive`: the block behind must not be replaceable.
  static bool canSurvive(Lvl lvl, Pos pos, Direction facing) => !lvl.canBeReplaced(pos.relative(facing.opposite));

  Future<void> _onTick(Server server, CustomBlockTickEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    await updateTransmittedSignal(lvl, pos);
    final props = lvl.info(pos)?.properties;
    if (props == null || props['receiver'] == 'true') return;
    // sendBlockUpdated for the link and the block it sits on.
    Rs.i.be<RedstoneLinkBlockEntity>(e.targetWorld, e.pos)?.sendData();
  }

  /// `useWithoutItem`: a sneaking click toggles between transmitting and receiving.
  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    if (e.withItem) return BlockUseResult.tryEmptyHand;
    if (!e.sneaking) return BlockUseResult.pass;
    final lvl = Lvl(e.targetWorld);
    if (await toggleMode(lvl, e.pos.toPos())) {
      lvl.scheduleTick(e.pos.toPos(), 1);
      return BlockUseResult.success;
    }
    return BlockUseResult.pass;
  }

  /// `toggleMode`.
  static Future<bool> toggleMode(Lvl lvl, Pos pos) async {
    final info = lvl.info(pos);
    if (info == null || info.key != 'create:redstone_link') return false;
    final be = Rs.i.store.typed<RedstoneLinkBlockEntity>(lvl.id, BlockPos(x: pos.x, y: pos.y, z: pos.z));
    if (be == null) return false;
    final wasReceiver = info.properties['receiver'] == 'true';
    final blockPowered = await lvl.hasNeighborSignal(pos);
    await lvl.setProps(pos, {'receiver': '${!wasReceiver}', 'powered': '$blockPowered'}, neighbors: true);
    be.transmit(wasReceiver ? 0 : await getPower(lvl, pos, _facing(info.properties)));
    return true;
  }

  /// `getPower`.
  static Future<int> getPower(Lvl lvl, Pos pos, Direction facing) => lvl.linkStylePower(pos, facing);

  /// `updateTransmittedSignal`.
  static Future<void> updateTransmittedSignal(Lvl lvl, Pos pos) async {
    final info = lvl.info(pos);
    if (info == null || info.key != 'create:redstone_link') return;
    if (info.properties['receiver'] == 'true') return;

    var power = await getPower(lvl, pos, _facing(info.properties));
    final be = Rs.i.store.typed<RedstoneLinkBlockEntity>(lvl.id, BlockPos(x: pos.x, y: pos.y, z: pos.z));

    var powerFromPanels = 0;
    if (be != null) {
      final tri = be.panelSupport.shouldBePoweredTristate();
      powerFromPanels = tri == null ? -1 : (tri ? 15 : 0);
    }
    // Suppress the update if an input panel exists but is not loaded.
    if (powerFromPanels == -1) return;

    if (powerFromPanels > power) power = powerFromPanels;

    final previouslyPowered = info.properties['powered'] == 'true';
    if (previouslyPowered != power > 0) {
      await lvl.setProps(pos, {'powered': '${!previouslyPowered}'});
    }
    be?.transmit(power);
  }
}
