// The borehead bearing: a bearing whose contraption mines the blocks in front
// of its rock cutting wheels.
//
// Java: `content/blocks/borehead_bearing/{BoreheadBearingBlock,
// BoreheadBearingBlockEntity,BoreheadAttachedStorage}`,
// `content/contraptions/borehead_contraption/BoreheadBearingContraption`,
// `network/borehead_bearing/ClientboundMultiMiningSync`.
//
// The numbers are in the pure [BoreheadBearingLogic]; this file is the block,
// the block entity (kinetic speed, stalling, saved state, the mining loop) and
// the block's interaction.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:math' as math;

import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/bearing/bearing_block_entities.dart' show MechanicalBearingBlockEntity;
import 'package:create/src/contraptions/blocks/actuator_contract.dart' show ActuatorHosts;
import 'package:create/src/contraptions/core/structure_info.dart' show AssemblyException;
import 'package:create/src/contraptions/entity/controlled_contraption_entity.dart'
    show ControlledContraptionEntity;
import 'package:create/src/contraptions/storage/stacks.dart' show ItemSlotsHelper, StoredStack;
import 'package:create/src/kinetics/block_defs.dart' show DirectionalAxisBlockDef;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../config/offroad_config.dart';
import '../../../handlers/multi_mining.dart';
import '../../../host/offroad_hooks.dart';
import '../../../index/offroad_ids.dart';
import '../../contraptions/borehead_contraption.dart';
import '../rock_cutting_wheel/rock_cutting_wheel_block.dart' show rockCuttingWheelKey;
import 'borehead_bearing_logic.dart';

/// The block and block entity key (`offroad:borehead_bearing`).
const String boreheadBearingKey = OffroadIds.boreheadBearing;

/// `BoreheadBearingBlockEntity`.
final class BoreheadBearingBlockEntity extends MechanicalBearingBlockEntity
    implements BoreheadMiningController, MultiMiningSupplier {
  BoreheadBearingBlockEntity(super.worldId, super.pos);

  /// The pure state machine.
  final BoreheadBearingLogic logic = BoreheadBearingLogic();

  /// The contraption this bearing drives, for the rock cutting wheel actor
  /// pairing (`OffroadHooks.bind`).
  Object? _contraptionKey;

  /// The state of the block as plain data.
  BState get bState => BState(blockState.block, blockState.props);

  /// The position as the pure [Pos] (`getBlockPos()`); `pos` is the host
  /// `BlockPos`.
  Pos get blockPos => (this.pos.x, this.pos.y, this.pos.z);

  /// `getBlockState().getValue(FACING)`.
  Direction get facing => bState.dir('facing') ?? Direction.north;

  @override
  bool get isStalled => logic.isStalled;

  /// `getContraptionEntity() instanceof BoreheadContraptionEntity`.
  bool get hasContraption => movedContraption != null;

  // -- Lifecycle ----------------------------------------------------------------

  // TODO(parity): `addBehaviours` also *removes* the movement-mode scroll value
  // after pinning it to `ROTATE_PLACE` (`BoreheadBearingBlockEntity.java:105-109`).
  // The framework adds behaviours but has no `removeBehaviour`, and the borehead
  // overrides `assemble`/`attach`, so nothing in this port reads the mode.

  @override
  void tick() {
    logic.insideMainTick = true;
    final step = logic.updateSpeed(
      isVirtual: false,
      isClientSide: false,
      angularSpeed: super.getAngularSpeed(),
      speed: speed,
    );
    if (step == BoreheadSpeedStep.disassemble) {
      logic.insideMainTick = false;
      disassemble();
      return;
    }
    if (logic.isSlowingDown) angle = logic.slowdownAngle;
    super.tick();
    logic.insideMainTick = false;

    final contraption = movedContraption;
    if (contraption != null && !contraption.isAlive) {
      movedContraption = null;
    }

    logic.visitedPositions.clear();

    if (movedContraption == null) {
      angle = 0;
      logic.rotationSpeed = 0;
      logic.disassemblySlowdown = false;
      return;
    }

    if (logic.tickStallTimer()) sendData();
    _updateMiningBlocks();
  }

  /// `updateMiningBlocks` (`BoreheadBearingBlockEntity.java:162-219`).
  void _updateMiningBlocks() {
    final w = world;
    if (w == null) return;
    if (!logic.isActive(speed: speed, removed: removed) || speed.abs() <= 0.1) return;

    final runtime = OffroadHooks.of(w);
    for (final origin in logic.centerMiningPositions) {
      for (final centre in logic.candidatesFor(origin)) {
        if (!runtime.level.isBreakableAt(centre)) continue;
        runtime.manager.addOrRefreshPos(centre, this);
        logic.visitedPositions.add(centre);
      }
    }
  }

  /// `getAngularSpeed` (`BoreheadBearingBlockEntity.java:346`); the client's
  /// `clientAngleDiff` term is client-only and unused here.
  @override
  double getAngularSpeed() {
    if (logic.insideMainTick && logic.disassemblySlowdown) return logic.slowdown.speed(1);
    return logic.rotationSpeed;
  }

  @override
  double getInterpolatedAngle(double partialTicks) {
    if (logic.isSlowingDown) return logic.slowdown.angle(partialTicks);
    return super.getInterpolatedAngle(partialTicks);
  }

  /// `calculateStressApplied`: the bearing's own stress times the number of rock
  /// cutters, at least one (`BoreheadBearingBlockEntity.java:111-115`).
  @override
  double calculateStressApplied() => super.calculateStressApplied() * math.max(logic.rockCuttingAmount, 1);

  // -- The contraption ----------------------------------------------------------

  @override
  Future<void> assemble() async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    final w = world;
    if (level == null || factory == null || w == null) return;
    if (HostBlockGetter(w).stateAt(blockPos).key != boreheadBearingKey) return;

    final contraption = BoreheadBearingContraption(facing);
    try {
      if (!await contraption.assemble(level, blockPos)) return;
      lastException = null;
    } on AssemblyException catch (e) {
      lastException = e;
      sendData();
      return;
    }

    // TODO(parity): the contraption does not move its blocks out of the world yet
    // (`BoreheadBearingContraption` inherits `removeBlocksFromWorld` from the
    // Create port, which no ported bearing calls during assembly either).
    final entity = factory.createControlled(worldId, localPos, contraption);
    final anchor = blockPos.relative(facing);
    entity.setPos(anchor.toVec3());
    entity.setRotationAxis(facing.axis);
    factory.spawn(worldId, entity);
    movedContraption = entity;

    logic.rotationSpeed = 0;
    logic.disassemblySlowdown = false;
    running = true;
    angle = 0;
    initializeContraption();
    updateGeneratedRotation();
    sendData();
  }

  @override
  void attach(ControlledContraptionEntity contraption) {
    super.attach(contraption);
    initializeContraption();
  }

  /// `initializeContraption` (`BoreheadBearingBlockEntity.java:458-480`): one
  /// mining origin per rock cutting wheel block on the contraption, which the
  /// actors then fill in.
  void initializeContraption() {
    final moved = movedContraption;
    final contraption = moved?.contraption;
    final w = world;
    if (contraption == null || w == null) return;

    if (!identical(_contraptionKey, contraption)) {
      final previous = _contraptionKey;
      if (previous != null) OffroadHooks.unbind(w, previous);
      _contraptionKey = contraption;
      OffroadHooks.bind(w, contraption, this);
    }

    if (logic.initialized) return;

    var wheels = 0;
    for (final block in contraption.blocks.values) {
      if (block.state.key == rockCuttingWheelKey) wheels++;
    }
    logic.initializeFromBlocks(wheels);
    sendData();
  }

  @override
  void disassemble() {
    assembleNextTick = false;
    if (running && movedContraption != null) {
      angle = 0;
      applyRotation();
    }
    super.disassemble();

    logic.resetCenterMiningInfo();
    logic.initialized = false;
    logic.setStalled(false);

    final w = world;
    final previous = _contraptionKey;
    if (w != null && previous != null) OffroadHooks.unbind(w, previous);
    _contraptionKey = null;

    updateGeneratedRotation();
    sendData();
  }

  // -- Disassembly slowdown -----------------------------------------------------

  /// `startDisassemblySlowdown` (`BoreheadBearingBlockEntity.java:511-519`):
  /// starts the slowdown curve; the timer grows with the square of the cutter
  /// count.
  void startDisassemblySlowdown() {
    final contraption = movedContraption?.contraption;
    if (logic.isSlowingDown || contraption == null) return;
    logic.startDisassemblySlowdown(
      interpolatedAngle: getInterpolatedAngle(0),
      rotationSpeed: logic.rotationSpeed,
      facing: facing,
      contraptionBlocks: {for (final e in contraption.blocks.entries) e.key: e.value.state.key},
    );
    updateGeneratedRotation();
    sendData();
  }

  // -- MultiMiningSupplier ------------------------------------------------------

  @override
  double breakingSpeed(Pos pos, String blockKey) => logic.breakingSpeed(
    active: logic.isActive(speed: speed, removed: removed),
    superEffective: Tags.block(blockKey, 'offroad:borehead_super_effective'),
    effective: Tags.block(blockKey, 'offroad:borehead_effective'),
    maxRotationSpeed: runtime.settings.maxRotationSpeed.toDouble(),
    speed: speed,
  );

  @override
  bool get isActive => logic.isActive(speed: speed, removed: removed);

  @override
  Pos? get location => BoreheadBearingLogic.locationOf(active: isActive, pos: blockPos);

  /// `itemCallback(stack)` (`BoreheadBearingBlockEntity.java:261-278`): offer
  /// the drop to the contraption's storage; a full storage stalls the bearing.
  ///
  /// TODO(parity): Java inserts through the contraption-wide
  /// `InventoryLoaderWrapper` of `BoreheadAttachedStorage`, which flags the
  /// storage as accepting inserts while the callback runs
  /// (`getContraptionWrappedInventory`, `BoreheadAttachedStorage.java`). Neither
  /// is ported (`BoreheadBearingContraption.getSimWrappedStorage` is the same
  /// gap), so the drop goes to the contraption's mounted item storages directly.
  @override
  int acceptItem(String itemKey, int count) {
    final contraption = movedContraption?.contraption;
    if (contraption == null) return 0;

    var remaining = StoredStack(itemKey, count);
    for (final storage in contraption.storage.allItemStorages.values) {
      remaining = ItemSlotsHelper.insert(storage, remaining);
      if (remaining.isEmpty) break;
    }
    final inserted = count - remaining.count;

    if (BoreheadBearingLogic.shouldStall(
      inserted: inserted,
      stallingEnabled: OffroadConfig.server.blocks.boreheadBearingStallingEnabled,
    )) {
      logic.setStalled(true);
      sendData();
    }
    return inserted;
  }

  /// `startUnstalling` (`BoreheadBearingBlockEntity.java:362`).
  void startUnstalling() {
    final wasStalled = logic.stalled;
    logic.startUnstalling();
    if (wasStalled && !logic.stalled) sendData();
  }

  @override
  int requestNewIndexAndIncrement({required bool isRockCuttingWheel}) =>
      logic.requestNewIndex(isRockCuttingWheel: isRockCuttingWheel);

  @override
  void updatePosition(int index, Vec3 originPosition) => logic.updatePosition(index, originPosition);

  // -- Saved data ---------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    for (final entry in logic.write(clientPacket: clientPacket).entries) {
      final key = entry.key;
      switch (entry.value) {
        case final double d:
          tag.putDouble(key, d);
        case final int i:
          tag.putInt(key, i);
        case final bool b:
          tag.putBool(key, b);
        case final List<Map<String, Object?>> positions:
          tag.putList(key, [
            for (final p in positions)
              NbtCompound()
                ..putDouble('x', (p['x'] as num?)?.toDouble() ?? 0)
                ..putDouble('y', (p['y'] as num?)?.toDouble() ?? 0)
                ..putDouble('z', (p['z'] as num?)?.toDouble() ?? 0)
                ..putInt('indexPosition', (p['indexPosition'] as num?)?.toInt() ?? 0),
          ]);
      }
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (wasMoved) return;

    final positions = tag.getList('OriginPositions');
    logic.read({
      'RotationSpeed': tag.getDouble('RotationSpeed') ?? 0,
      'DisassemblySlowdown': tag.getBool('DisassemblySlowdown') ?? false,
      'ContraptionInitialized': tag.getBool('ContraptionInitialized') ?? false,
      'Stalled': tag.getBool('Stalled') ?? false,
      'StalledRecoveryTimer': tag.getInt('StalledRecoveryTimer') ?? 0,
      if (tag.containsKey('ClientRockCutterAmount')) 'ClientRockCutterAmount': tag.getInt('ClientRockCutterAmount'),
      if (tag.containsKey('OriginPositionSize')) 'OriginPositionSize': tag.getInt('OriginPositionSize'),
      if (tag.containsKey('NextAvailableIndex')) 'NextAvailableIndex': tag.getInt('NextAvailableIndex'),
      if (positions != null)
        'OriginPositions': [
          for (final entry in positions)
            if (entry is NbtCompound)
              {
                'x': entry.getDouble('x') ?? 0,
                'y': entry.getDouble('y') ?? 0,
                'z': entry.getDouble('z') ?? 0,
                'indexPosition': entry.getInt('indexPosition') ?? 0,
              },
        ],
    }, clientPacket: clientPacket);
  }
}

/// `BoreheadBearingBlock`: a `DirectionalAxisKineticBlock` whose contraption is
/// a borehead.
CreateBlock buildBoreheadBearingBlock() => CreateBlock(
  key: boreheadBearingKey,
  properties: [CreateProps.facing, BlockProperty.boolean('axis_along_first')],
  defaultState: {'facing': 'north'},
  // `SharedProperties.softMetal()`: `Blocks.GOLD_BLOCK`'s 3 / 6.
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'copper',
  canOcclude: false,
  blockEntityType: boreheadBearingKey,
  behavior: BlockBehavior(
    onUseWithoutItem: (server, e) async {
      // `BoreheadBearingBlock.useItemOn` with an empty hand (`:56-68`): start the
      // slowdown of a running bearing, or assemble it on the next tick.
      final be = OffroadHooks.store?.at(e.targetWorld.getId(), e.pos);
      if (be is! BoreheadBearingBlockEntity) return BlockUseResult.pass;
      if (be.isRunning) {
        be.startDisassemblySlowdown();
      } else {
        be.assembleNextTick = true;
      }
      return BlockUseResult.success;
    },
  ),
);

/// The kinetic rules: a `DirectionalAxisKineticBlock` (the same facing +
/// `axis_along_first` rotation axis as the gauges).
const DirectionalAxisBlockDef boreheadBearingKineticDef = DirectionalAxisBlockDef();

/// The empty mining origin, for the tests.
const Vec3 boreheadEmptyOrigin = vec3Zero;