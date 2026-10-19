// `PulleyBlockEntity`: a rope pulley that lowers and raises a contraption. The rope is made of
// `create:rope` blocks with a `create:pulley_magnet` at the end; the offset is the rope length.
//
// Java: `content/contraptions/pulley/PulleyBlockEntity`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter, setBlockState;
import '../../common/common.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';
import '../core/level.dart';
import '../core/movement_checks.dart';
import '../entity/contraption_entity.dart';
import '../entity/i_control_contraption.dart';
import '../piston/linear_actuator_block_entity.dart';
import 'pulley_contraption.dart';

/// `AllBlocks.ROPE` / `AllBlocks.PULLEY_MAGNET`.
const String ropeKey = 'create:rope';
const String pulleyMagnetKey = 'create:pulley_magnet';

bool isRopeState(BState state) =>
    state.key == ropeKey || state.key == pulleyMagnetKey;

class PulleyBlockEntity extends LinearActuatorBlockEntity {
  PulleyBlockEntity(super.worldId, super.pos);

  int initialOffset = 0;

  /// The pulley that owns the shared contraption (`mirrorParent`) and the pulleys that copy it.
  Pos? mirrorParent;
  List<Pos>? mirrorChildren;

  /// `getAttachedContraption`: a mirroring pulley shows its parent's contraption.
  AbstractContraptionEntity? get attachedContraption => movedContraption;

  BState get stateNow =>
      HostBlockGetter.stateOfId(world!.getBlockStateId(pos: this.pos));

  @override
  bool get isPassive => mirrorParent != null;

  /// The rope pulley never places its contraption back by itself (`MOVE_NEVER_PLACE`).
  @override
  MovementMode get movementMode => MovementMode.moveNeverPlace;

  @override
  Future<void> assemble() async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    if (level == null || factory == null) return;
    if (stateNow.key != 'create:rope_pulley') return;
    if (speed == 0 && mirrorParent == null) return;

    final maxLength = level.settings.maxRopeLength;
    var i = 1;
    while (i <= maxLength) {
      final ropePos = localPos.belowBy(i);
      if (!isRopeState(level.stateAt(ropePos))) break;
      ++i;
    }
    offset = (i - 1).toDouble();
    if (offset >= getExtensionRange() && speed > 0) return;
    if (offset <= 0 && speed < 0) return;

    if (mirrorParent == null) {
      needsContraption = false;
      final anchor = localPos.belowBy((offset + 1).floor());
      initialOffset = offset.floor();
      final contraption = PulleyContraption(initialOffset);
      var canAssemble = await contraption.assemble(level, anchor);

      if (canAssemble) {
        final movementDirection = speed > 0 ? Direction.down : Direction.up;
        if (ContraptionCollision.isCollidingWithWorld?.call(
              level,
              contraption,
              anchor.relative(movementDirection),
              movementDirection,
            ) ??
            false) {
          canAssemble = false;
        }
      }

      if (!canAssemble && speed > 0) return;

      await _removeRopes(level);

      if (contraption.blocks.isNotEmpty) {
        await contraption.removeBlocksFromWorld(level, posZero);
        final entity = factory.createControlled(worldId, localPos, contraption);
        movedContraption = entity;
        entity.setPos(anchor.toVec3());
        factory.spawn(worldId, entity);
        forceMove = true;
        needsContraption = true;

        for (var collider in contraption.getOrCreateColliders(
          level,
          Direction.up,
        )) {
          if (collider.$2 != 0) continue;
          final global = collider + anchor;
          final be = ActuatorRuntimeLookup.pulleyAt(worldId, (
            global.$1,
            this.pos.y,
            global.$3,
          ));
          be?.startMirroringOther(localPos);
        }
      }
    }

    if (mirrorParent != null) await _removeRopes(level);

    running = true;
    sendData();
  }

  Future<void> _removeRopes(ContraptionLevel level) async {
    final world = this.world;
    if (world == null) return;
    for (var i = offset.truncate(); i > 0; i--) {
      final ropePos = localPos.belowBy(i);
      final old = level.stateAt(ropePos);
      final water = old.flag('waterlogged');
      await setBlockState(
        world,
        ropePos,
        water ? const BState('minecraft:water') : BState.air,
        flags: {BlockFlagsFlag.notifyListeners, BlockFlagsFlag.moved},
      );
    }
  }

  /// `shouldCreateRopes`: the elevator pulley never leaves a rope behind.
  bool get shouldCreateRopes => true;

  @override
  void disassemble() {
    final world = this.world;
    if (world == null) return;
    if (!running && movedContraption == null && mirrorParent == null) return;
    offset = getGridOffset(offset).toDouble();
    if (movedContraption != null) resetContraptionToOffset();

    if (!removed && shouldCreateRopes) {
      unawaited(_placeRopes());
    }

    if (movedContraption != null && mirrorParent == null) {
      unawaited(movedContraption!.disassemble());
    }
    _notifyMirrorsOfDisassembly();
    movedContraption?.remove();
    movedContraption = null;
    initialOffset = 0;
    running = false;
    sendData();
  }

  Future<void> _placeRopes() async {
    final world = this.world;
    if (world == null) return;
    final length = offset.truncate();
    if (length > 0) {
      final magnetPos = localPos.belowBy(length);
      final fluid = HostBlockGetter(world).isWater(magnetPos);
      await world.breakBlock(
        BlockPos(x: magnetPos.$1, y: magnetPos.$2, z: magnetPos.$3),
        drop: false,
      );
      await setBlockState(
        world,
        magnetPos,
        BState(pulleyMagnetKey, {'waterlogged': '$fluid'}),
      );
    }
    for (var i = 1; i <= length - 1; i++) {
      final ropePos = localPos.belowBy(i);
      final fluid = HostBlockGetter(world).isWater(ropePos);
      await setBlockState(
        world,
        ropePos,
        BState(ropeKey, {'waterlogged': '$fluid'}),
      );
    }
  }

  @override
  Vec3 toPosition(double offset) {
    final contraption = movedContraption?.contraption;
    if (contraption is PulleyContraption) {
      return contraption.anchor.toVec3() +
          (0, (contraption.getInitialOffset() - offset).toDouble(), 0);
    }
    return vec3Zero;
  }

  @override
  void visitNewPosition() {
    if (movedContraption != null) return;
    if (speed <= 0) return;
    final level = ActuatorHosts.levelOf(worldId);
    if (level == null) return;
    final posBelow = localPos.belowBy(
      (offset + getMovementSpeed()).truncate() + 1,
    );
    final state = level.stateAt(posBelow);
    if (!BlockMovementChecks.isMovementNecessary(state, level, posBelow))
      return;
    if (BlockMovementChecks.isBrittle(state, level)) return;
    disassemble();
    assembleNextTick = true;
  }

  @override
  int getExtensionRange() {
    final world = this.world;
    if (world == null) return 0;
    final minY = world.getMinY();
    return math.max(
      0,
      math.min(
        ActuatorRuntime.instance.settings.maxRopeLength,
        (this.pos.y - 1) - minY,
      ),
    );
  }

  @override
  int getInitialOffset() => initialOffset;

  @override
  Vec3 toMotionVector(double speed) => (0, -speed, 0);

  /// `startMirroringOther`: a pulley at the same height shares the contraption of [parent].
  void startMirroringOther(Pos parent) {
    if (parent == localPos) return;
    final parentBe = ActuatorRuntimeLookup.pulleyAt(worldId, parent);
    if (parentBe == null) return;
    (parentBe.mirrorChildren ??= []).add(localPos);
    parentBe.markDirty();
    mirrorParent = parent;
    unawaited(assemble());
    markDirty();
  }

  /// `notifyMirrorsOfDisassembly`.
  void _notifyMirrorsOfDisassembly() {
    final children = mirrorChildren;
    if (children == null) return;
    for (final childPos in children) {
      final be = ActuatorRuntimeLookup.pulleyAt(worldId, childPos);
      if (be == null) continue;
      be.offset = offset;
      be.disassemble();
      be.mirrorParent = null;
      be.markDirty();
    }
    children.clear();
    markDirty();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    initialOffset = tag.getInt('InitialOffset') ?? 0;
    needsContraption = tag.getBool('NeedsContraption') ?? false;
    super.read(tag, clientPacket: clientPacket);

    mirrorParent = tag.containsKey('MirrorParent')
        ? _readBlockPos(tag, 'MirrorParent')
        : null;
    final children = tag.getList('MirrorChildren');
    mirrorChildren = tag.containsKey('MirrorChildren') && children != null
        ? [
            for (final entry in children)
              // `NBTHelper.readBlockPos(t, "Pos")`: each entry holds the position under `Pos`.
              if (entry is NbtCompound) _readBlockPos(entry, 'Pos'),
          ]
        : null;

    if (mirrorParent != null) offset = 0;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('InitialOffset', initialOffset);
    super.write(tag, clientPacket: clientPacket);
    final parent = mirrorParent;
    // `compound.store("MirrorParent", BlockPos.CODEC, ...)`: `BlockPos.CODEC` is an int array.
    if (parent != null)
      tag.putIntArray('MirrorParent', [parent.$1, parent.$2, parent.$3]);
    final children = mirrorChildren;
    if (children != null) {
      tag.putList('MirrorChildren', [
        for (final p in children)
          NbtCompound()..putIntArray('Pos', [p.$1, p.$2, p.$3]),
      ]);
    }
  }
}

/// `NBTHelper.readBlockPos(compound, key)`: `BlockPos.CODEC` (an int array) or the legacy
/// `{X, Y, Z}` compound.
Pos _readBlockPos(NbtCompound tag, String key) {
  final array = tag.getIntArray(key);
  if (array != null && array.length >= 3) return (array[0], array[1], array[2]);
  final compound = tag.getCompound(key);
  if (compound == null) return posZero;
  return (
    compound.getInt('X') ?? 0,
    compound.getInt('Y') ?? 0,
    compound.getInt('Z') ?? 0,
  );
}

/// The block entity lookup the pulley needs (avoids a direct store dependency in tests).
abstract final class ActuatorRuntimeLookup {
  static PulleyBlockEntity? pulleyAt(String worldId, Pos pos) {
    final runtime = ActuatorRuntime.instance;
    return runtime.store.typed<PulleyBlockEntity>(
      worldId,
      BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
    );
  }
}
