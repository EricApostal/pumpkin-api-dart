// The peculiar and the haunted bell: `AbstractBellBlock` / `AbstractCreateBellEntity` (ringing),
// `HauntedCreateBellEntity` (the soul pulse), `PeculiarBellBlock` (turns into a haunted bell over
// a soul fire) and `HauntedBellPulser` (a held haunted bell pulses around the player).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart';
import '../../contraptions/behaviours/bell_movement_behaviour.dart';
import '../../contraptions/core/movement.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../host/env.dart';
import '../host/runtime.dart';
import '../model/dir.dart';
import 'bell_movement.dart';
import 'bell_nbt.dart';

const String peculiarBellEntityType = 'create:peculiar_bell';
const String hauntedBellEntityType = 'create:cursed_bell';

/// `AbstractCreateBellEntity` and `HauntedCreateBellEntity`.
final class CreateBellEntity extends CreateBlockEntity {
  static const ringDuration = 74;
  static const hauntedDistance = 10;
  static const hauntedRechargeTicks = 65;
  static const hauntedEffectTicks = 20;

  final bool haunted;

  CreateBellEntity(super.worldId, super.pos, {required this.haunted});

  bool isRinging = false;
  int ringingTicks = 0;
  Dir ringDirection = Dir.north;
  int effectTicks = 0;
  bool _ringPending = false;

  EquipmentRuntime get _rt => EquipmentRuntime.instance;

  /// `ring(world, pos, direction)`.
  bool ring(Dir direction) {
    if (haunted) {
      if (isRinging && ringingTicks < hauntedRechargeTicks) return false;
      final w = world;
      if (w != null) _rt.bells.sendPulse(w, this.pos, hauntedDistance, false);
      effectTicks = hauntedEffectTicks;
    }
    isRinging = true;
    ringingTicks = 0;
    ringDirection = direction;
    _ringPending = true;
    sendData();
    return true;
  }

  @override
  void tick() {
    super.tick();
    if (isRinging) ++ringingTicks;
    if (ringingTicks >= ringDuration) {
      isRinging = false;
      ringingTicks = 0;
    }
    if (haunted && effectTicks > 0) effectTicks--;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (haunted) tag.putInt('EffectTicks', effectTicks);
    // `if (!clientPacket || ringingTicks != 0 || !isRinging) return;` - the sync is written a
    // tick after `ring`, so the flag stands in for `ringingTicks == 0`.
    if (!clientPacket || !isRinging || !(ringingTicks == 0 || _ringPending)) return;
    _ringPending = false;
    tag.putString('Ringing', ringDirectionNbtName(ringDirection));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (haunted) effectTicks = tag.getInt('EffectTicks') ?? 0;
    // `AbstractBellBlockEntity.read`: the client tag carries the ring direction; a missing or
    // unknown name falls back to `Direction.values()[0]` (down).
    if (!clientPacket || !tag.containsKey('Ringing')) return;
    ringDirection = ringDirectionFromNbtName(tag.getString('Ringing') ?? '');
    ringingTicks = 0;
    isRinging = true;
  }
}

final class BellHost {
  final EquipmentEnv env;

  BellHost(this.env);

  /// Held haunted bell warmup: uuid -> ticks left (`HauntedBellPulser.WARMUP`).
  final Map<String, int> _warmup = {};
  int _tick = 0;

  static const pulserDistance = 3;
  static const pulserRechargeTicks = 8;
  static const pulserWarmupTicks = 10;

  void install(CreateContext ctx) {
    ctx.listen(Events.worldTick, (server, e) => _tick = e.tick);
    ctx.listen(Events.playerTick, _onPlayerTick);
    ctx.listen(Events.projectileHit, _onProjectileHit);

    // `AllBlocks`: the peculiar bell uses the vanilla bell actor; the haunted bell also sends
    // soul pulses to the blocks it travels over.
    MovementBehaviours.register('create:peculiar_bell', const BellMovementBehaviour());
    MovementBehaviours.register('create:haunted_bell', HauntedBellMovementBehaviour(env));
  }

  // -- HauntedBellPulser -------------------------------------------------------------------------

  void _onPlayerTick(Server server, PlayerTickEventData e) {
    final player = e.player;
    if (player.isSpectator) return;
    final g = EquipmentRuntime.instance.armor.gearOf(player.getId().asString);
    if (g.main != 'create:haunted_bell' && g.off != 'create:haunted_bell') {
      _warmup.remove(player.getId().asString);
      return;
    }
    final uuid = player.getId().asString;
    final left = _warmup[uuid] ?? pulserWarmupTicks;
    final firstPulse = left == 1;
    _warmup[uuid] = left - 1;
    if (left - 1 > 0) return;
    if (firstPulse || _tick % pulserRechargeTicks != 0) {
      final p = player.getPosition();
      sendPulse(player.getWorld(), BlockPos(x: p.$1.floor(), y: p.$2.floor(), z: p.$3.floor()), pulserDistance, false);
    }
  }

  /// `HauntedBellPulser.sendPulse`: the soul pulse effect for the clients that track the chunk.
  void sendPulse(World world, BlockPos pos, int distance, bool canOverlap) {
    env.bus.sendToTracking('create:soul_pulse', world, pos, {
      'pos': (pos.x, pos.y, pos.z),
      'distance': distance,
      'canOverlap': canOverlap,
    });
  }

  // -- Block behaviour ---------------------------------------------------------------------------------

  /// Behaviour of one bell block (`haunted` selects the sound and the extras).
  BlockBehavior behavior({required bool haunted}) => BlockBehavior(
    onUse: (server, e) => _onUse(server, e, haunted),
    onNeighborUpdate: (server, e) => _onNeighborUpdate(server, e, haunted),
    onPlaced: (server, e) => _onPlaced(server, e, haunted),
  );

  CreateBellEntity? _be(World world, BlockPos pos) => env.ctx.blockEntities.typed<CreateBellEntity>(world.getId(), pos);

  /// `canRingFrom(state, hitDir, heightChange)`.
  static bool canRingFrom(Map<String, String> props, Dir hitDir, double heightChange) {
    if (hitDir.axis == Ax.y) return false;
    if (heightChange > 0.8124) return false;
    final facing = Dir.parse(props['facing'] ?? 'north') ?? Dir.north;
    switch (props['attachment']) {
      case 'floor':
      case 'ceiling':
        return facing.axis == hitDir.axis;
      case 'single_wall':
      case 'double_wall':
        return facing.axis != hitDir.axis;
    }
    return false;
  }

  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e, bool haunted) async {
    final world = e.targetWorld;
    final props = {for (final (k, v) in world.getBlockState(pos: e.pos).properties) k: v};
    final dir = e.face.dir;
    if (!canRingFrom(props, dir, e.cursor.$2)) return BlockUseResult.pass;
    final ok = await ring(world, e.pos, dir, haunted, e.player);
    return ok ? BlockUseResult.success : BlockUseResult.pass;
  }

  /// `AbstractBellBlock.ring`.
  Future<bool> ring(World world, BlockPos pos, Dir direction, bool haunted, Player? player) async {
    final be = _be(world, pos);
    if (be == null || !be.ring(direction)) return false;
    if (player != null) {
      try {
        player.incrementCustomStatistic(stat: CustomStatistic.bellRing, amount: 1);
      } on Object {
        // the statistic is not available on this host
      }
    }
    if (haunted) {
      env.playSoundAtBlock(world, pos.p3, 'haunted_bell_use', volume: 4);
      if (player != null) await env.award(player, 'haunted_bell');
    } else {
      env.playSoundAtBlock(world, pos.p3, 'peculiar_bell_use', volume: 2, pitch: 0.94);
    }
    return true;
  }

  /// Redstone: a rising signal rings the bell (`neighborChanged`); the peculiar bell also checks
  /// for the soul fire below.
  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e, bool haunted) async {
    final world = e.targetWorld;
    final state = world.getBlockState(pos: e.pos);
    final props = {for (final (k, v) in state.properties) k: v};
    if (!haunted && await _tryConvert(world, e.pos, state.id, props)) return;
    final shouldPower = await world.hasNeighborSignal(pos: e.pos);
    final powered = props['powered'] == 'true';
    if (shouldPower == powered) return;
    final id = BlockStates.setValue(state.id, 'powered', '$shouldPower');
    await world.setBlockState(pos: e.pos, state: id, updateFlags: BlockUpdateFlags.normal);
    if (!shouldPower) return;
    final facing = Dir.parse(props['facing'] ?? 'north') ?? Dir.north;
    final attachment = props['attachment'];
    final dir = (attachment == 'ceiling' || attachment == 'floor') ? facing : facing.clockWise;
    await ring(world, e.pos, dir, haunted, null);
  }

  /// `PeculiarBellBlock.tryConvert`: a peculiar bell on top of soul fire becomes a haunted bell.
  Future<bool> _tryConvert(World world, BlockPos pos, int stateId, Map<String, String> props) async {
    final under = world.getBlockState(pos: pos.p3.down1.blockPos).blockName;
    if (under != 'minecraft:soul_fire' && under != 'minecraft:soul_campfire') return false;
    final id = BlockRegistry.resolveState('create:haunted_bell', {
      'facing': props['facing'] ?? 'north',
      'attachment': props['attachment'] ?? 'floor',
      'powered': props['powered'] ?? 'false',
    });
    if (id == null) return false;
    env.playSoundAtBlock(world, pos.p3, 'haunted_bell_convert');
    await world.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal);
    return true;
  }

  /// Placement: the attachment and facing from the neighbours (vanilla `BellBlock.getStateForPlacement`
  /// uses the clicked face, which the placed event does not carry), the haunted bell's first effect.
  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e, bool haunted) async {
    final world = e.targetWorld;
    final be = _be(world, e.pos);
    final fromPlayer = e.player != null && !e.moved;
    if (fromPlayer) {
      final player = server.getPlayerByUuid(id: e.player!);
      await _fixAttachment(world, e.pos, player);
    }
    if (!haunted) {
      final state = world.getBlockState(pos: e.pos);
      final props = {for (final (k, v) in state.properties) k: v};
      await _tryConvert(world, e.pos, state.id, props);
      return;
    }
    // `onPlace`: only when the block was not a haunted bell before
    final old = e.oldStateId;
    final wasHaunted = old != null && BlockStates.blockKey(old) == 'create:haunted_bell';
    if (be != null && !wasHaunted) {
      be.effectTicks = CreateBellEntity.hauntedEffectTicks;
      be.sendData();
    }
  }

  Future<void> _fixAttachment(World world, BlockPos pos, Player? player) async {
    final state = world.getBlockState(pos: pos);
    final horizontal = player == null ? Dir.north : Dir.fromYRot(player.getYaw());
    String attachment = 'floor';
    Dir facing = horizontal;
    final below = world.getBlockState(pos: pos.p3.down1.blockPos);
    final above = world.getBlockState(pos: pos.p3.up1.blockPos);
    if (below.upSideSolid) {
      attachment = 'floor';
    } else if (above.downSideSolid) {
      attachment = 'ceiling';
    } else {
      bool solid(Dir d) {
        final s = world.getBlockState(pos: pos.p3.rel(d).blockPos);
        return switch (d.opposite) {
          Dir.north => s.northSideSolid,
          Dir.south => s.southSideSolid,
          Dir.west => s.westSideSolid,
          Dir.east => s.eastSideSolid,
          _ => false,
        };
      }

      Dir? found;
      for (final d in [horizontal.opposite, horizontal.clockWise, horizontal.counterClockWise, horizontal]) {
        if (solid(d)) {
          found = d;
          break;
        }
      }
      if (found == null) return;
      facing = found;
      attachment = solid(found.opposite) ? 'double_wall' : 'single_wall';
    }
    var id = BlockStates.setValue(state.id, 'attachment', attachment);
    id = BlockStates.setValue(id, 'facing', facing.name);
    if (id != state.id) await world.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal);
  }

  /// `BellBlock.onProjectileHit`: an arrow ringing the bell.
  Future<void> _onProjectileHit(Server server, ProjectileHitEventData e) async {
    final pos = e.hitBlockPos;
    if (pos == null) return;
    final entity = findProjectile(server, e.entityId);
    if (entity == null) return;
    final world = entity.getWorld();
    final be = _be(world, pos);
    if (be == null) return;
    final v = entity.getVelocity();
    final dir = Dir.nearest(-v.$1, 0, -v.$3);
    final props = {for (final (k, val) in world.getBlockState(pos: pos).properties) k: val};
    final h = e.hitPosition.$2 - pos.y;
    if (!canRingFrom(props, dir, h)) return;
    await ring(world, pos, dir, be.haunted, null);
  }

  Entity? findProjectile(Server server, int id) {
    for (final w in server.getAllWorlds()) {
      final e = w.getEntityById(id: id);
      if (e != null) return e;
    }
    return null;
  }
}
