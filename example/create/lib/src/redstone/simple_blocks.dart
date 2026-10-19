// The small redstone blocks: redstone contact, desk bell, analog lever and rose quartz lamp.
// Logic that does not need the host is in `lamp_logic.dart`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/util.dart' hide pos;
import '../core/block_entity.dart';
import '../core/blocks.dart';
import 'lamp_logic.dart';
import 'support/level.dart';
import 'support/manifest_block.dart';
import 'support/placement.dart';
import 'support/placer.dart';
import 'support/shapes.dart';
import 'support/rs_runtime.dart';

Direction _facing(Map<String, String> p, [Direction fallback = Direction.north]) =>
    Direction.byName(p['facing'] ?? '') ?? fallback;

// -- Redstone contact ----------------------------------------------------------------------

/// `RedstoneContactBlock`.
final class RedstoneContactBlock {
  static const String key = 'redstone_contact';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      placement: const [PlacementRule.lookingDirection('facing', opposite: true)],
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _onNeighborUpdate,
        onUpdateShape: _onUpdateShape,
        onScheduledTick: _onTick,
        // getSignal: weak power; the contact has no getDirectSignal.
        onWeakPower: (server, e) {
          final p = block.stateOf(e.stateIndex);
          return redstoneContactSignal(
            powered: p['powered'] == 'true',
            facing: _facing(p, Direction.up),
            side: e.face.toDirection().opposite,
          );
        },
        canConnectRedstone: (server, e) => redstoneContactConnects(
          facing: _facing(block.stateOf(e.stateIndex), Direction.up),
          side: e.direction?.toDirection(),
        ),
      ),
    );
    return block;
  }

  /// `hasValidContact(level, pos, direction)`.
  static bool validContact(Lvl lvl, Pos pos, Direction direction) {
    final info = lvl.info(pos.relative(direction));
    if (info == null) return false;
    final f = info.properties['facing'];
    return hasValidContact(info.key, f == null ? null : Direction.byName(f), direction);
  }

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    var props = block.stateOf(e.stateIndex);
    final ctx = placeContextOf(server, e);
    if (ctx != null) {
      // getStateForPlacement: the contact faces what it was clicked against.
      final placed = contactPlacement(ctx, (p, d) => validContact(lvl, p, d));
      if (placed['facing'] != props['facing'] || placed['powered'] != props['powered']) {
        await lvl.setProps(pos, placed, neighbors: true);
        props = {...props, ...placed};
      }
    }
    final valid = validContact(lvl, pos, _facing(props, Direction.up));
    if ((props['powered'] == 'true') != valid) lvl.scheduleTick(pos, 1);
  }

  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final p = block.stateOf(e.stateIndex);
    final valid = validContact(lvl, pos, _facing(p, Direction.up));
    if ((p['powered'] == 'true') != valid) lvl.scheduleTick(pos, 1);
  }

  /// `updateShape`: follows the contact in front of the block.
  FutureOr<int?> _onUpdateShape(Server server, CustomBlockUpdateShapeEventData e) {
    final p = block.stateOf(e.stateIndex);
    final facing = _facing(p, Direction.up);
    if (e.direction.toDirection() != facing) return null;
    final valid = validContact(Lvl(e.targetWorld), e.pos.toPos(), facing);
    if ((p['powered'] == 'true') == valid) return null;
    return block.layout.indexOf({...block.definition.defaultState, ...p, 'powered': '$valid'});
  }

  Future<void> _onTick(Server server, CustomBlockTickEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final p = lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex);
    final valid = validContact(lvl, pos, _facing(p, Direction.up));
    if ((p['powered'] == 'true') != valid) await lvl.setProps(pos, {'powered': '$valid'}, neighbors: true);
  }
}

// -- Desk bell -------------------------------------------------------------------------------

/// `DeskBellBlockEntity`.
final class DeskBellBlockEntity extends CreateBlockEntity {
  static const String type = 'create:desk_bell';

  int blockStateTimer = 0;
  bool _ding = false;

  DeskBellBlockEntity(super.worldId, super.pos);

  /// `ding()` (server side).
  void ding() {
    blockStateTimer = 20;
    _ding = true;
    sendData();
  }

  @override
  void tick() {
    super.tick();
    if (blockStateTimer == 0) return;
    blockStateTimer--;
    if (blockStateTimer > 0) return;
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);
    final p = pos.toPos();
    final info = lvl.info(p);
    if (info != null && info.key == 'create:desk_bell' && info.properties['powered'] == 'true') {
      unawaited(DeskBellBlock.unPress(lvl, p, info.properties));
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (clientPacket && _ding) NbtHelper.putMarker(tag, 'Ding');
    _ding = false;
  }
}

/// `DeskBellBlock`.
final class DeskBellBlock {
  static const String key = 'desk_bell';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      blockEntityType: DeskBellBlockEntity.type,
      placement: const [PlacementRule.clickedFace('facing'), PlacementRule.inWater('waterlogged')],
      collisionShape: const BlockShape.boxes([BlockBox(3 / 16, 0, 3 / 16, 13 / 16, 3 / 16, 13 / 16), BlockBox(4 / 16, 0, 4 / 16, 12 / 16, 9 / 16, 12 / 16)]),
      selectionShape: const BlockShape.boxes([BlockBox(3 / 16, 0, 3 / 16, 13 / 16, 3 / 16, 13 / 16), BlockBox(4 / 16, 0, 4 / 16, 12 / 16, 9 / 16, 12 / 16)]),
      shapeRules: _shapeRules(),
      behavior: BlockBehavior(
        onUse: _onUse,
        onStateReplaced: _onReplaced,
        onWeakPower: (server, e) => block.stateOf(e.stateIndex)['powered'] == 'true' ? 15 : 0,
        onStrongPower: (server, e) {
          final p = block.stateOf(e.stateIndex);
          return p['powered'] == 'true' && _facing(p, Direction.up) == e.face.toDirection().opposite ? 15 : 0;
        },
        isPathfindable: (server, e) => false,
      ),
    );
    return block;
  }

  static List<ShapeRule> _shapeRules() => [
    for (final d in Direction.values)
      ShapeRule(
        when: {'facing': d.serializedName},
        collisionShape: BlockShape.boxes(rotateBoxes(const [BlockBox(3 / 16, 0, 3 / 16, 13 / 16, 3 / 16, 13 / 16), BlockBox(4 / 16, 0, 4 / 16, 12 / 16, 9 / 16, 12 / 16)], Direction.up, d)),
        selectionShape: BlockShape.boxes(rotateBoxes(const [BlockBox(3 / 16, 0, 3 / 16, 13 / 16, 3 / 16, 13 / 16), BlockBox(4 / 16, 0, 4 / 16, 12 / 16, 9 / 16, 12 / 16)], Direction.up, d)),
      ),
  ];

  /// `useWithoutItem`.
  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    // playSound(AllSoundEvents.DESK_BELL_USE)
    e.targetWorld.playCustomSound(
      soundName: 'create:desk_bell',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 1,
    );
    final props = lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex);
    await lvl.setProps(pos, {'powered': 'true'}, neighbors: true);
    await _updateNeighbours(lvl, pos, props);
    Rs.i.be<DeskBellBlockEntity>(e.targetWorld, e.pos)?.ding();
    return BlockUseResult.success;
  }

  /// `updateNeighbours`: the bell and the block it is attached to.
  static Future<void> _updateNeighbours(Lvl lvl, Pos pos, Map<String, String> props) async {
    await lvl.updateNeighbors(pos);
    await lvl.updateNeighbors(pos.relative(_facing(props, Direction.up).opposite));
  }

  /// `unPress`.
  static Future<void> unPress(Lvl lvl, Pos pos, Map<String, String> props) async {
    await lvl.setProps(pos, {'powered': 'false'}, neighbors: true);
    await _updateNeighbours(lvl, pos, props);
  }

  /// `affectNeighborsAfterRemoval`: a powered bell that is removed updates its neighbours.
  Future<void> _onReplaced(Server server, CustomBlockStateReplacedEventData e) async {
    if (e.moved) return;
    final p = block.stateOf(e.oldStateIndex);
    if (p['powered'] != 'true') return;
    await _updateNeighbours(Lvl(e.targetWorld), e.pos.toPos(), p);
  }
}

// -- Analog lever ------------------------------------------------------------------------------

/// `AnalogLeverBlockEntity`.
final class AnalogLeverBlockEntity extends CreateBlockEntity {
  static const String type = 'create:analog_lever';

  int state = 0;
  int lastChange = 0;

  AnalogLeverBlockEntity(super.worldId, super.pos);

  @override
  bool get syncsToClient => true;

  /// `changeState(back)`.
  void changeState(bool back) {
    final step = analogLeverStep(state, back: back);
    state = step.state;
    if (step.changed) lastChange = 15;
    sendData();
  }

  @override
  void tick() {
    super.tick();
    if (lastChange > 0) {
      lastChange--;
      if (lastChange == 0) _updateOutput();
    }
  }

  void _updateOutput() {
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);
    final p = pos.toPos();
    final props = lvl.info(p)?.properties;
    if (props == null) return;
    unawaited(AnalogLeverBlock.updateNeighbors(lvl, p, props));
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('State', state);
    tag.putInt('ChangeTimer', lastChange);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    state = tag.getInt('State') ?? 0;
    lastChange = tag.getInt('ChangeTimer') ?? 0;
    super.read(tag, clientPacket: clientPacket);
  }
}

/// `AnalogLeverBlock`.
final class AnalogLeverBlock {
  static const String key = 'analog_lever';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      blockEntityType: AnalogLeverBlockEntity.type,
      shapeRules: leverShapeRules(),
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _onNeighborUpdate,
        onUse: _onUse,
        onStateReplaced: _onReplaced,
        onWeakPower: (server, e) => _state(e.targetWorld, e.pos),
        onStrongPower: (server, e) {
          final p = block.stateOf(e.stateIndex);
          final connected = analogLeverConnected(p['face'] ?? 'floor', _facing(p));
          return analogLeverDirectSignal(_state(e.targetWorld, e.pos), connected, e.face.toDirection().opposite);
        },
        isPathfindable: (server, e) => false,
      ),
    );
    return block;
  }

  int _state(World world, BlockPos pos) => Rs.i.be<AnalogLeverBlockEntity>(world, pos)?.state ?? 0;

  /// The vanilla lever shapes (selection only; the block has no collision).
  static List<ShapeRule> leverShapeRules() {
    BlockBox px(double x0, double y0, double z0, double x1, double y1, double z1) =>
        BlockBox(x0 / 16, y0 / 16, z0 / 16, x1 / 16, y1 / 16, z1 / 16);
    BlockShape s(BlockBox b) => BlockShape.boxes([b]);
    final rules = <ShapeRule>[];
    for (final facing in Direction.horizontals) {
      final nsAxis = facing.axis == Axis.z;
      rules.add(ShapeRule(when: {'face': 'floor', 'facing': facing.serializedName}, selectionShape: s(nsAxis ? px(5, 0, 4, 11, 3, 12) : px(4, 0, 5, 12, 3, 11))));
      rules.add(ShapeRule(when: {'face': 'ceiling', 'facing': facing.serializedName}, selectionShape: s(nsAxis ? px(5, 13, 4, 11, 16, 12) : px(4, 13, 5, 12, 16, 11))));
      rules.add(ShapeRule(
        when: {'face': 'wall', 'facing': facing.serializedName},
        selectionShape: s(switch (facing) {
          Direction.north => px(5, 4, 10, 11, 12, 16),
          Direction.south => px(5, 4, 0, 11, 12, 6),
          Direction.west => px(10, 4, 5, 16, 12, 11),
          _ => px(0, 4, 5, 6, 12, 11),
        }),
      ));
    }
    return rules;
  }

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final ctx = placeContextOf(server, e);
    if (ctx == null) return;
    final lvl = Lvl(e.targetWorld);
    final placed = faceAttachedPlacement(ctx, HostPlaceWorld(lvl));
    if (placed == null) {
      await lvl.destroyBlock(e.pos.toPos());
      return;
    }
    final current = block.stateOf(e.stateIndex);
    if (placed['face'] != current['face'] || placed['facing'] != current['facing']) {
      await lvl.setProps(e.pos.toPos(), placed, neighbors: true);
    }
  }

  /// `FaceAttachedHorizontalDirectionalBlock.updateShape`: no support, no lever.
  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final p = lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex);
    if (!faceAttachedCanSurvive(pos, p['face'] ?? 'floor', _facing(p), HostPlaceWorld(lvl))) {
      await lvl.destroyBlock(pos);
    }
  }

  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    if (e.withItem) return BlockUseResult.tryEmptyHand;
    final be = Rs.i.be<AnalogLeverBlockEntity>(e.targetWorld, e.pos);
    if (be == null) return BlockUseResult.pass;
    be.changeState(e.sneaking);
    Lvl(e.targetWorld).playLeverClick(e.pos.toPos(), 0.2, analogLeverPitch(be.state));
    return BlockUseResult.success;
  }

  /// `affectNeighborsAfterRemoval`.
  Future<void> _onReplaced(Server server, CustomBlockStateReplacedEventData e) async {
    if (e.moved) return;
    await updateNeighbors(Lvl(e.targetWorld), e.pos.toPos(), block.stateOf(e.oldStateIndex));
  }

  /// `updateNeighbors(state, world, pos)`: the lever and the block it hangs on.
  static Future<void> updateNeighbors(Lvl lvl, Pos pos, Map<String, String> props) async {
    await lvl.updateNeighbors(pos);
    final connected = analogLeverConnected(props['face'] ?? 'floor', _facing(props));
    await lvl.updateNeighbors(pos.relative(connected.opposite));
  }
}

// -- Rose quartz lamp ----------------------------------------------------------------------------

/// `RoseQuartzLampBlock`.
final class RoseQuartzLampBlock {
  static const String key = 'rose_quartz_lamp';
  static const String blockKey = 'create:rose_quartz_lamp';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      // The host has one luminance per block: the lit state (POWERING) cannot be expressed.
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _onNeighborUpdate,
        onScheduledTick: _onTick,
        onWeakPower: _weak,
        onStrongPower: (server, e) => 0,
      ),
    );
    return block;
  }

  static bool _isLamp(Lvl lvl, Pos p) => lvl.blockKey(p) == blockKey;

  static bool _isPowering(Lvl lvl, Pos p) => lvl.info(p)?.properties['powering'] == 'true';

  /// `getSignal`.
  FutureOr<int> _weak(Server server, CustomBlockRedstonePowerEventData e) {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final face = e.face.toDirection(); // the side facing the reader
    final side = face.opposite; // vanilla `side`: reader to lamp
    final readerKey = lvl.blockKey(pos.relative(face));
    final kind = readerKey == blockKey
        ? LampReader.lamp
        : readerKey == 'minecraft:comparator'
        ? LampReader.comparator
        : LampReader.other;
    return roseQuartzSignal(
      pos: pos,
      side: side,
      powering: block.stateOf(e.stateIndex)['powering'] == 'true',
      readerKind: kind,
      isLamp: (p) => _isLamp(lvl, p),
      isPowering: (p) => _isPowering(lvl, p),
    );
  }

  /// `getStateForPlacement`: POWERED follows the neighbours.
  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    if (e.player == null) return;
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final signal = await lvl.hasNeighborSignal(pos);
    if (signal != (block.stateOf(e.stateIndex)['powered'] == 'true')) {
      await lvl.setProps(pos, {'powered': '$signal'});
    }
  }

  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final props = lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex);
    final signal = await lvl.hasNeighborSignal(pos);
    switch (roseQuartzOnNeighborChanged(powered: props['powered'] == 'true', neighbourSignal: signal)) {
      case LampAction.nothing:
        return;
      case LampAction.switchOff:
        await lvl.setProps(pos, {'powered': 'false'});
      case LampAction.activate:
        for (final cluster in roseQuartzCluster(pos, (p) => _isLamp(lvl, p))) {
          await lvl.setProps(cluster, {'powering': 'false'});
          lvl.scheduleTick(cluster, 1);
        }
        await lvl.setProps(pos, {'powered': 'true', 'powering': 'true', 'activate': 'true'});
        await lvl.updateNeighbors(pos);
        lvl.scheduleTick(pos, 1);
    }
  }

  Future<void> _onTick(Server server, CustomBlockTickEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final props = lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex);
    final next = roseQuartzTick(activate: props['activate'] == 'true', powering: props['powering'] == 'true');
    if (next != null) {
      await lvl.setProps(pos, {'activate': '${next.activate}', 'powering': '${next.powering}'});
    }
    await lvl.updateNeighbors(pos);
  }

  /// `getRotatedBlockState` + `onWrenched`: the wrench flips POWERING and updates the cluster.
  static Future<void> wrench(Lvl lvl, Pos pos) async {
    final props = lvl.info(pos)?.properties;
    if (props == null) return;
    await lvl.setProps(pos, {'powering': '${props['powering'] != 'true'}'}, neighbors: true);
    for (final cluster in roseQuartzCluster(pos, (p) => _isLamp(lvl, p))) {
      await lvl.updateNeighbors(cluster);
    }
  }
}
