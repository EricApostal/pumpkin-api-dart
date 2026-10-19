// Host glue of the redstone diodes: the toggle latch, the powered latch and the three
// brass diodes (pulse repeater, extender, timer). The rules live in `diode_logic.dart`;
// this file reads block states, writes them back with the right flags and keeps the
// output with the neighbours in step (vanilla `DiodeBlock.onPlace` ->
// `updateNeighborsInFront`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../support/level.dart';
import '../support/manifest_block.dart';
import '../support/value_settings.dart';
import 'diode_logic.dart';

/// The vanilla `DiodeBlock.SHAPE`: a 2 pixel slab.
const BlockShape diodeShape = BlockShape.boxes([BlockBox(0, 0, 0, 1, 2 / 16, 1)]);

/// Keys of the blocks that are `DiodeBlock`s (for `shouldPrioritize`).
const Set<String> diodeBlockKeys = {
  'minecraft:repeater',
  'minecraft:comparator',
  'create:pulse_repeater',
  'create:pulse_extender',
  'create:pulse_timer',
  'create:powered_latch',
  'create:powered_toggle_latch',
};

/// [DiodeEnv] over the host.
final class HostDiodeEnv implements DiodeEnv {
  final Lvl lvl;

  const HostDiodeEnv(this.lvl);

  @override
  Future<int> signalFrom(Pos reader, Direction d) => lvl.signalFrom(reader, d);

  @override
  int? wirePowerAt(Pos pos) {
    final info = lvl.info(pos);
    if (info == null || info.key != 'minecraft:redstone_wire') return null;
    return int.tryParse(info.properties['power'] ?? '') ?? 0;
  }

  @override
  Direction? diodeFacingAt(Pos pos) {
    final info = lvl.info(pos);
    if (info == null || !diodeBlockKeys.contains(info.key)) return null;
    final f = info.properties['facing'];
    return f == null ? null : Direction.byName(f);
  }
}

/// The [DiodeState] of a property map.
DiodeState diodeStateOf(Map<String, String> p) => DiodeState(
  facing: Direction.byName(p['facing'] ?? 'north') ?? Direction.north,
  powered: p['powered'] == 'true',
  powering: p['powering'] == 'true',
  poweredSide: p['powered_side'] == 'true',
  inverted: p['inverted'] == 'true',
);

TickPriority _priority(String name) => switch (name) {
  'extremelyHigh' => TickPriority.extremelyHigh,
  'veryHigh' => TickPriority.veryHigh,
  _ => TickPriority.high,
};

/// `DiodeBlock.updateNeighborsInFront`: tells the block in front of the output (and its
/// neighbours, for strong power through a solid block) that the output changed.
Future<void> updateNeighborsInFront(Lvl lvl, Pos pos, Direction facing) =>
    lvl.updateNeighbors(pos.relative(facing.opposite));

/// `DiodeBlock.canSurvive`: a rigid block below.
bool diodeCanSurvive(Lvl lvl, Pos pos) => lvl.canSupportRigid(pos.below);

/// The use result of a click that should fall through to the item.
BlockUseResult _passOn(bool withItem) => withItem ? BlockUseResult.tryEmptyHand : BlockUseResult.pass;

/// Whether the held item of a `with item` use is Create's wrench.
Future<bool> heldIsWrench(CustomBlockUseEventData e) async {
  if (!e.withItem) return false;
  return await e.item.getRegistryKey() == 'create:wrench';
}

// -- Latches ----------------------------------------------------------------------------

/// `ToggleLatchBlock` and `PoweredLatchBlock` (the powered latch extends the toggle latch).
final class LatchBlock {
  final LatchKind kind;
  final String key;

  LatchBlock(this.kind, this.key);

  late final CreateBlock block;

  Pos _pos(BlockPos p) => p.toPos();

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
      collisionShape: diodeShape,
      selectionShape: diodeShape,
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _onNeighborUpdate,
        onScheduledTick: _onTick,
        onCanPlace: (server, e) => e.canPlace && diodeCanSurvive(Lvl(e.targetWorld), _pos(e.pos)),
        onWeakPower: (server, e) => _signal(e.stateIndex, e.face),
        onStrongPower: (server, e) => _signal(e.stateIndex, e.face),
        canConnectRedstone: (server, e) {
          final s = diodeStateOf(block.stateOf(e.stateIndex));
          return LatchLogic.wireConnects(kind, s, e.direction?.toDirection());
        },
        onUse: _onUse,
      ),
    );
    return block;
  }

  int _signal(int stateIndex, BlockDirection face) =>
      LatchLogic.signal(diodeStateOf(block.stateOf(stateIndex)), face.toDirection().opposite);

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = _pos(e.pos);
    final state = diodeStateOf(block.stateOf(e.stateIndex));
    final logic = LatchLogic(kind, HostDiodeEnv(lvl));
    // setPlacedBy: schedule a tick when the input is already on.
    if (await logic.shouldTurnOn(pos, state)) lvl.scheduleTick(pos, 1);
    await updateNeighborsInFront(lvl, pos, state.facing);
  }

  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = _pos(e.pos);
    if (!diodeCanSurvive(lvl, pos)) {
      await lvl.destroyBlock(pos);
      return;
    }
    final state = diodeStateOf(block.stateOf(e.stateIndex));
    final logic = LatchLogic(kind, HostDiodeEnv(lvl));
    final req = await logic.checkTickOnNeighbor(pos, state);
    if (req != null) lvl.scheduleTick(pos, req.delay, priority: _priority(req.priority));
  }

  Future<void> _onTick(Server server, CustomBlockTickEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = _pos(e.pos);
    final before = diodeStateOf(lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex));
    final logic = LatchLogic(kind, HostDiodeEnv(lvl));
    final result = await logic.tick(pos, before);
    if (result.state != before) {
      await lvl.setProps(pos, {
        'powered': '${result.state.powered}',
        'powering': '${result.state.powering}',
        'powered_side': '${result.state.poweredSide}',
      });
      await updateNeighborsInFront(lvl, pos, before.facing);
    }
    final s = result.schedule;
    if (s != null) lvl.scheduleTick(pos, s.delay, priority: _priority(s.priority));
  }

  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    if (e.sneaking) return _passOn(e.withItem);
    if (await heldIsWrench(e)) return _passOn(e.withItem);
    final lvl = Lvl(e.targetWorld);
    final pos = _pos(e.pos);
    final state = diodeStateOf(lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex));
    if (!LatchLogic.canActivate(kind, state)) return _passOn(e.withItem);
    // activated(): flip POWERING with a lever click.
    lvl.playLeverClick(pos, 0.3, !state.powering ? 0.6 : 0.5);
    await lvl.setProps(pos, {'powering': '${!state.powering}'});
    await updateNeighborsInFront(lvl, pos, state.facing);
    return BlockUseResult.success;
  }
}

// -- Brass diodes -------------------------------------------------------------------------

/// The block entity of the pulse repeater, extender and timer
/// (`BrassDiodeBlockEntity` and its three subclasses).
final class BrassDiodeBlockEntity extends CreateBlockEntity {
  final BrassDiodeMachine machine;
  late final ScrollValueBehaviour maxState;

  /// The last `POWERING` value this entity wrote and that the world may not show yet.
  bool? _pendingPowering;
  int _pendingTicks = 0;

  BrassDiodeBlockEntity(super.worldId, super.pos, BrassDiodeKind kind) : machine = BrassDiodeMachine(kind) {
    maxState = addBehaviour(
      ScrollValueBehaviour(
        min: 2,
        max: 60 * 20 * 60,
        value: machine.maxState,
        callback: (v) {
          machine.onMaxDelayChanged(v);
          sendData();
        },
        toSettings: BrassDiodeMachine.toValueSettings,
        fromSettings: BrassDiodeMachine.fromValueSettings,
        shortInteract: _shortInteract,
      ),
    );
  }

  /// `BrassDiodeScrollValueBehaviour.onShortInteract` -> `BrassDiodeBlock.toggle`.
  void _shortInteract(Player player) {
    final w = world;
    if (w == null) return;
    unawaited(BrassDiodeBlock.toggleAt(Lvl(w), pos.toPos()));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    machine.state = tag.getInt('State') ?? 0;
    super.read(tag, clientPacket: clientPacket);
    machine.maxState = maxState.value;
    machine.state = machine.state.clamp(0, machine.maxState);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('State', machine.state);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void tick() {
    super.tick();
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);
    final p = pos.toPos();
    final info = lvl.info(p);
    if (info == null || !info.key.startsWith('create:pulse_')) return;
    final powered = info.properties['powered'] == 'true';
    var powering = info.properties['powering'] == 'true';
    // A write of the previous tick may not be visible yet.
    final pending = _pendingPowering;
    if (pending != null) {
      if (pending == powering || ++_pendingTicks > 3) {
        _pendingPowering = null;
        _pendingTicks = 0;
      } else {
        powering = pending;
      }
    }
    final before = machine.state;
    final change = machine.tick(powered: powered, powering: powering);
    if (machine.state != before) markDirty();
    if (change != null) {
      _pendingPowering = change;
      _pendingTicks = 0;
      final facing = Direction.byName(info.properties['facing'] ?? 'north') ?? Direction.north;
      unawaited(() async {
        await lvl.setProps(p, {'powering': '$change'}, neighbors: true);
        await updateNeighborsInFront(lvl, p, facing);
      }());
    }
  }
}

/// `BrassDiodeBlock`: the pulse repeater, pulse extender and pulse timer.
final class BrassDiodeBlock {
  final String key;
  final BrassDiodeKind kind;

  BrassDiodeBlock(this.key, this.kind);

  late final CreateBlock block;

  String get entityType => 'create:$key';

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      blockEntityType: entityType,
      placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
      collisionShape: diodeShape,
      selectionShape: diodeShape,
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _onNeighborUpdate,
        onScheduledTick: _onTick,
        onCanPlace: (server, e) => e.canPlace && diodeCanSurvive(Lvl(e.targetWorld), e.pos.toPos()),
        onWeakPower: (server, e) => _signal(e.stateIndex, e.face),
        onStrongPower: (server, e) => _signal(e.stateIndex, e.face),
        canConnectRedstone: (server, e) {
          final side = e.direction?.toDirection();
          if (side == null) return false;
          return side.axis == diodeStateOf(block.stateOf(e.stateIndex)).facing.axis;
        },
        onUse: _onUse,
      ),
    );
    return block;
  }

  BlockEntityTypeSpec entitySpec() => BlockEntityTypeSpec(
    key: entityType,
    validBlocks: ['create:$key'],
    create: (w, p) => BrassDiodeBlockEntity(w, p, kind),
    tickInterval: 1,
  );

  int _signal(int stateIndex, BlockDirection face) {
    final s = diodeStateOf(block.stateOf(stateIndex));
    if (s.facing != face.toDirection().opposite) return 0;
    return BrassDiodeMachine.outputSignal(powering: s.powering, inverted: s.inverted);
  }

  /// `AbstractDiodeBlock`/`DiodeBlock` behaviour shared with the latches: the brass diodes
  /// use `DiodeBlock.tick` too, but with `getDelay` 2 and no extra state.
  LatchLogic _logic(Lvl lvl) => LatchLogic(LatchKind.toggle, HostDiodeEnv(lvl));

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final state = diodeStateOf(block.stateOf(e.stateIndex));
    if (await _logic(lvl).shouldTurnOn(pos, state)) lvl.scheduleTick(pos, 1);
    await updateNeighborsInFront(lvl, pos, state.facing);
  }

  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    if (!diodeCanSurvive(lvl, pos)) {
      await lvl.destroyBlock(pos);
      return;
    }
    final state = diodeStateOf(block.stateOf(e.stateIndex));
    final logic = _logic(lvl);
    // DiodeBlock.checkTickOnNeighbor with getDelay() == 2.
    final req = await logic.checkTickOnNeighbor(pos, state);
    if (req != null) lvl.scheduleTick(pos, 2, priority: _priority(req.priority));
  }

  Future<void> _onTick(Server server, CustomBlockTickEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final before = diodeStateOf(lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex));
    // DiodeBlock.tick: powered follows the input, with a delayed re-check when it turned on
    // although the input is already gone.
    final logic = _logic(lvl);
    final shouldTurnOn = await logic.shouldTurnOn(pos, before);
    if (before.powered && !shouldTurnOn) {
      await lvl.setProps(pos, {'powered': 'false'});
    } else if (!before.powered) {
      await lvl.setProps(pos, {'powered': 'true'});
      if (!shouldTurnOn) lvl.scheduleTick(pos, 2, priority: TickPriority.veryHigh);
    }
    await updateNeighborsInFront(lvl, pos, before.facing);
  }

  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    if (e.sneaking) return _passOn(e.withItem);
    if (await heldIsWrench(e)) return _passOn(e.withItem);
    await toggleAt(Lvl(e.targetWorld), e.pos.toPos());
    return BlockUseResult.success;
  }

  /// `BrassDiodeBlock.toggle`: flips `INVERTED` with a lever click.
  static Future<void> toggleAt(Lvl lvl, Pos pos) async {
    final info = lvl.info(pos);
    if (info == null || !info.properties.containsKey('inverted')) return;
    final inverted = info.properties['inverted'] == 'true';
    await lvl.setProps(pos, {'inverted': '${!inverted}'}, neighbors: true);
    lvl.playLeverClick(pos, 0.3, !inverted ? 0.6 : 0.5);
    final facing = Direction.byName(info.properties['facing'] ?? 'north') ?? Direction.north;
    await updateNeighborsInFront(lvl, pos, facing);
  }
}

/// Convenience for the module: all diode blocks and their entity types.
final class DiodeBlocks {
  final LatchBlock toggleLatch = LatchBlock(LatchKind.toggle, 'powered_toggle_latch');
  final LatchBlock poweredLatch = LatchBlock(LatchKind.powered, 'powered_latch');
  final BrassDiodeBlock pulseRepeater = BrassDiodeBlock('pulse_repeater', BrassDiodeKind.repeater);
  final BrassDiodeBlock pulseExtender = BrassDiodeBlock('pulse_extender', BrassDiodeKind.extender);
  final BrassDiodeBlock pulseTimer = BrassDiodeBlock('pulse_timer', BrassDiodeKind.timer);

  List<BrassDiodeBlock> get brass => [pulseRepeater, pulseExtender, pulseTimer];
}
