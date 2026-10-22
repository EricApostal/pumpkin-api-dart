// The block entities of the swivel bearing and its plate.
//
// The bearing assembles the structure in front of it into a sub-level and holds
// it with a hinge; the plate is the block inside the sub-level that the hinge
// attaches to. Each end saves the other's position and sub-level, so a reload
// reconnects them.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.content.blocks.swivel_bearing.SwivelBearingBlockEntity
//       and link_block.SwivelBearingPlateBlockEntity
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter, setBlockState;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/core/block_entity.dart';
import 'package:create/src/core/pos.dart' show packPos, unpackPos;
import 'package:create/src/kinetics/kinetic_block_entity.dart' show KineticBlockEntity;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' as sable
    show
        BlockEntitySubLevelActor,
        PhysicsConstraintHandle,
        Quaterniond,
        RigidBodyHandle,
        Rotation,
        ServerSubLevel,
        SubLevel,
        Vector3d;

import '../../../compat/computercraft/peripherals/swivel_bearing_peripheral.dart';
import '../../../config/sim_config_service.dart';
import '../../../host/simulated_host.dart';
import '../../../util/assembly/sim_assembly_exception.dart';
import '../../../util/sim_assembly_events.dart';
import '../../../util/sim_assembly_helper.dart';
import '../../../util/host_calls.dart' show ignoredCall;
import '../../../util/physics_constraints.dart';
import '../../../util/sim_level_util.dart';
import 'swivel_bearing_logic.dart';

/// `SwivelBearingBlockEntity`.
final class SwivelBearingBlockEntity extends KineticBlockEntity
    implements sable.BlockEntitySubLevelActor, SimSwivelBearingSource {
  /// The block entity type key.
  static const String type = 'simulated:swivel_bearing';

  /// The block key.
  static const String block = 'simulated:swivel_bearing';

  SwivelBearingBlockEntity(super.worldId, super.pos);

  /// The bearing state.
  final SwivelBearingLogic logic = SwivelBearingLogic();

  BState state = BState(block);

  /// If the bearing should assemble next tick.
  bool assembleNextTick = false;

  /// The last assembly failure.
  SimAssemblyException? lastException;

  /// The sub-level the bearing holds.
  String? subLevelId;

  /// The position of the plate inside that sub-level.
  (int, int, int)? platePos;

  /// Whether the bearing is being destroyed as part of an assembly.
  bool assembling = false;

  /// The hinge between the bearing's sub-level and its plate's.
  sable.PhysicsConstraintHandle? hinge;

  /// Whether a hinge handle exists.
  bool get hasHandle => hinge?.isValid ?? false;

  @override
  void tick() {
    final w = world;
    if (w != null && !removed) {
      state = HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
      logic.assembled = state.flag('assembled');
      logic.locking = state.flag('powered');
    }

    // `checkedInitialAssembly` (`SwivelBearingBlockEntity.java:177-186`): a bearing that arrives
    // already turning (a saved chunk, a schematic) never *changes* speed, and `onSpeedChanged` --
    // the only thing that ever asks for assembly -- never runs. Assemble on the first tick then.
    if (!_checkedInitialAssembly) {
      _checkedInitialAssembly = true;
      if (!logic.assembled && speed != 0) assembleNextTick = true;
    }

    if (assembleNextTick && !_assembling) {
      assembleNextTick = false;
      if (!logic.assembled) {
        // A tick cannot await; the assembly runs in the Sable component, so the
        // request is started here and the bearing updates when it lands.
        _assembling = true;
        unawaited(assemble().whenComplete(() => _assembling = false));
      } else {
        disassemble();
      }
    }

    // Lock/unlock from the redstone signal.
    final host = simulatedHost;
    final bestSignal = host.bestNeighbourSignal(worldId, pos.toPos());
    final shouldLock = logic.lockingSetting.shouldLock(bestSignal);
    if (shouldLock != logic.locking) {
      logic.locking = shouldLock;
      setBlockFlag('powered', shouldLock);
    }

    // Keep the sub-level after a reload.
    if (subLevelId != null) checkPersistence();

    final config = SimConfigService.instance.server;
    logic.tick(
      cogSpeed: speed,
      facing: blockState.dirOf('facing')?.name ?? 'up',
      physicsPaused: false,
      sequenced: logic.sequencedAngleLimit >= 0,
      maxSwivelRpm: config.blocks.maxSwivelBearingSpeed,
    );

    // Hold the hinge at the target angle while the bearing is assembled.
    _driveServo();

    super.tick();
  }

  /// Whether an assembly request is in flight.
  bool _assembling = false;

  /// Whether the first-tick assembly check (`checkedInitialAssembly`) already ran.
  bool _checkedInitialAssembly = false;

  /// `SwivelBearingCogwheelBlockEntity.onSpeedChanged` (`SwivelBearingBlockEntity.java:920-926`):
  /// the cogwheel asks the bearing to assemble as soon as it turns, which is what makes a
  /// shaft-driven bearing assemble without a click.
  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    if (speed != 0 && !logic.assembled) assembleNextTick = true;
  }

  /// `assemble()`.
  Future<void> assemble() async {
    final host = simulatedHost;
    final level = host.levelOf(worldId);
    final world = host.assemblyWorldOf(worldId);
    if (level == null || world == null) return;

    final facing = state.dir('facing')?.name ?? 'up';
    final target = _relative(pos.toPos(), facing);

    SimAssemblyResult? result;
    try {
      result = await SimAssemblyHelper.assembleFromSingleBlock(
        world,
        level,
        pos.toPos(),
        target,
        includeStart: false,
        includeEncasingGlue: false,
      );
      lastException = null;
    } on SimAssemblyException catch (e) {
      lastException = e;
      sendData();
      return;
    }

    // `SwivelBearingBlockEntity.java:430-500`: Java sets `ASSEMBLED` only once it has a
    // sub-level. With the block in front empty `assembleFromSingleBlock` returns `null` and Java
    // allocates an empty plot, writes the plate into it and hinges the bearing to it
    // (`:445-495`); the port has no empty-plot allocation yet, so it leaves the bearing
    // unassembled instead of claiming `assembled` with no sub-level id, no plate and no hinge.
    final subLevel = result?.subLevel;
    if (subLevel == null) return;

    setBlockFlag('assembled', true);
    sendData();

    subLevelId = subLevel.id;

    final offset = result!.offset;
    final platePosition = (pos.x + offset.$1, pos.y + offset.$2, pos.z + offset.$3);
    host.setBlock(worldId, platePosition, 'simulated:swivel_bearing_link_block');
    platePos = platePosition;

    final plate = host.blockEntityAt<SwivelBearingPlateBlockEntity>(worldId, platePosition);
    plate?.setParent(this);

    _attachHinge();

    host.playSound(worldId, pos.toPos(), 'simulated:block.physics_assembler.assemble');
    SimAssemblyEvents.notifyAssembled(worldId, pos.toPos(), result);
  }

  /// `disassemble()`.
  void disassemble() {
    if (removed) return;
    _removeHinge();

    final host = simulatedHost;
    final level = host.levelOf(worldId);
    final world = host.assemblyWorldOf(worldId);
    final id = subLevelId;
    if (level == null || world == null) return;

    final subLevel = id == null ? null : host.subLevelById(worldId, id);
    final plate = platePos;

    if (plate != null) {
      destroyPlate();
      if (subLevel is sable.ServerSubLevel) {
        SimAssemblyHelper.disassembleSubLevel(
          world,
          level,
          subLevel,
          plate,
          pos.toPos(),
          sable.Rotation.none,
          entities: host.entitiesOf(worldId),
          playSound: true,
        );
        SimAssemblyEvents.notifyDisassembled(worldId, pos.toPos(), subLevel);
      }
    }

    setBlockFlag('assembled', false);
    subLevelId = null;
    platePos = null;
    logic.targetAngleDegrees = 0;
    logic.lastTargetAngleDegrees = 0;
    sendData();
  }

  /// `updateServoCoefficients()`: the hinge motor.
  ///
  /// HOST GAP: sable's `PhysicsConstraintHandle` has no `setMotor` yet, so the
  /// gains are computed (and testable) but cannot be applied. The bearing still
  /// assembles, disassembles and tracks its target angle.
  SwivelMotorSettings? servoMotor(double partialTick) {
    final config = SimConfigService.instance.server.physics;
    return logic.motorFor(
      hasHandle: hasHandle,
      partialTick: partialTick,
      inertiaA: null,
      inertiaB: null,
      stiffness: config.swivelBearingStiffness,
      damping: config.swivelBearingDamping,
      friction: config.swivelBearingFriction,
    );
  }

  /// `attachConstraints`: the hinge to the plate's sub-level.
  ///
  /// HOST GAP when `constraintPipelineOf` is `null`: the level has no
  /// joint-capable physics, so the bearing assembles and tracks its angle but
  /// cannot hold the sub-level physically.
  void _attachHinge() {
    final plate = platePos;
    final level = simulatedHost.levelOf(worldId);
    if (plate == null || level == null) return;

    final pipeline = constraintPipelineOf(level);
    if (pipeline == null) return;

    final plateSubLevel = simulatedHost.containingSubLevel(worldId, plate);
    if (plateSubLevel == null || identical(plateSubLevel, simulatedHost.containingSubLevel(worldId, pos.toPos()))) {
      // Java refuses to hinge a sub-level to itself (`sameSubLevel`).
      return;
    }

    _removeHinge();

    final facing = state.dir('facing')?.name ?? 'up';
    // The plate sits inside the plot, whose blocks the host cannot read back;
    // it is placed with the bearing's facing (see `assemble`), so that is the
    // hinge direction on both sides.
    final plateFacing = facing;

    hinge = SwivelHinge.attach(
      pipeline,
      containingSubLevel: simulatedHost.containingSubLevel(worldId, pos.toPos()),
      plateSubLevel: plateSubLevel,
      anchor: _centerOf(_relative(pos.toPos(), facing)),
      attachPos: _centerOf(plate),
      axis: _unit(facing),
      plateAxis: _unit(plateFacing),
    );
  }

  /// Attaches the hinge if the bearing is assembled and has none (a reload, or
  /// a plate that arrived after the bearing).
  void _attachHingeIfMissing() {
    if (!logic.assembled || hinge != null) return;
    _attachHinge();
  }

  /// `updateServoCoefficients()`: the motor for this tick.
  void _driveServo() {
    final handle = hinge;
    if (handle == null) return;
    if (!handle.isValid) {
      hinge = null;
      return;
    }

    final config = SimConfigService.instance.server.physics;
    final plate = platePos;
    final plateSubLevel = plate == null ? null : simulatedHost.containingSubLevel(worldId, plate);
    final containing = simulatedHost.containingSubLevel(worldId, pos.toPos());

    SwivelHinge.drive(
      handle,
      logic: logic,
      partialTick: 1,
      containingMass: containing is sable.ServerSubLevel ? containing.massTracker : null,
      plateMass: plateSubLevel is sable.ServerSubLevel ? plateSubLevel.massTracker : null,
      axis: _unit(facingOf(state)),
      stiffness: config.swivelBearingStiffness,
      damping: config.swivelBearingDamping,
      friction: config.swivelBearingFriction,
    );
  }

  void _removeHinge() {
    final handle = hinge;
    if (handle != null && handle.isValid) handle.remove();
    hinge = null;
  }

  /// The facing of a bearing state, as the direction name.
  static String facingOf(BState state) => state.dir('facing')?.name ?? 'up';

  static sable.Vector3d _centerOf((int, int, int) pos) =>
      sable.Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);

  static sable.Vector3d _unit(String facing) => switch (facing) {
    'down' => sable.Vector3d(0, -1, 0),
    'up' => sable.Vector3d(0, 1, 0),
    'north' => sable.Vector3d(0, 0, -1),
    'south' => sable.Vector3d(0, 0, 1),
    'west' => sable.Vector3d(-1, 0, 0),
    'east' => sable.Vector3d(1, 0, 0),
    _ => sable.Vector3d(0, 1, 0),
  };

  /// `checkPersistence()`: reattach the plate after a reload.
  void checkPersistence() {
    final id = subLevelId;
    final plate = platePos;
    if (id == null) return;

    if (plate != null && SimLevelUtil.isAreaActuallyLoaded(simulatedHost.levelOf(worldId)!, plate, 1)) {
      if (simulatedHost.blockKeyAt(worldId, plate) != 'simulated:swivel_bearing_link_block') {
        return;
      }
    }
    if (!hasHandle) _attachHinge();
  }

  /// `setPlatePos(pos)`.
  void setPlatePos((int, int, int)? pos) => platePos = pos;

  /// `setSubLevelID(id)`.
  void setSubLevelID(String? id) => subLevelId = id;

  /// `destroyPlate()`: the plate goes away with the bearing.
  void destroyPlate() {
    final plate = platePos;
    if (plate == null) return;
    final host = simulatedHost;
    if (host.blockKeyAt(worldId, plate) == 'simulated:swivel_bearing_link_block') {
      host.blockEntityAt<SwivelBearingPlateBlockEntity>(worldId, plate)?.beforeAssembly();
      host.setBlock(worldId, plate, 'minecraft:air');
    }
    platePos = null;
  }

  /// `beforeAssembly()`: the bearing is moved into a sub-level.
  void beforeAssembly() => assembling = true;

  /// `associatePlateWithParent()`: the plate learns about the bearing.
  void associatePlateWithParent() {
    final plate = platePos;
    if (plate == null) return;
    if (simulatedHost.blockKeyAt(worldId, plate) != 'simulated:swivel_bearing_link_block') return;
    simulatedHost.blockEntityAt<SwivelBearingPlateBlockEntity>(worldId, plate)?.setParent(this);
  }

  @override
  void sable$physicsTick(sable.ServerSubLevel subLevel, sable.RigidBodyHandle handle, double timeStep) {
    // `SwivelBearingBlockEntity.physicsTick`: the hinge motor is re-driven every
    // step, because the target angle is interpolated and the servo's coefficients
    // depend on the masses the bodies have *now*. `hasHandle` is derived from
    // `hinge`, so there is nothing to record here.
    _driveServo();
  }

  @override
  void sable$tick(sable.ServerSubLevel subLevel) {}

  @override
  Iterable<sable.SubLevel>? sable$getLoadingDependencies() => sable$getConnectionDependencies();

  @override
  Iterable<sable.SubLevel>? sable$getConnectionDependencies() {
    final id = subLevelId;
    if (id == null) return null;
    final subLevel = simulatedHost.subLevelById(worldId, id);
    return subLevel == null ? null : [subLevel];
  }

  @override
  void onRemoved() {
    _removeHinge();
    if (!assembling) destroyPlate();
    super.onRemoved();
  }

  /// `setTargetAngleFromCurrentOrientation()`: keep the current angle on lock.
  ///
  /// The caller supplies the four orientations, because reading a sub-level's
  /// pose needs the sable container.
  void setTargetAngleFromCurrentOrientation({
    required sable.Quaterniond orientationA,
    required sable.Quaterniond blockOrientationA,
    required sable.Quaterniond orientationB,
    required sable.Quaterniond blockOrientationB,
  }) => logic.setTargetAngleFromCurrentOrientation(
    orientationA: orientationA,
    blockOrientationA: blockOrientationA,
    orientationB: orientationB,
    blockOrientationB: blockOrientationB,
  );

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    logic.read(
      targetAngle: tag.getDouble('TargetAngle') ?? 0,
      assembled: state.flag('assembled'),
    );
    logic.sequencedAngleLimit = tag.getDouble('SequencedAngleLimit') ?? -1;
    subLevelId = tag.getString('SubLevelID');
    final plate = tag.getInt('SwivelPlate');
    if (plate != null) platePos = unpackPos(plate);
    // `AssemblyException.read`.
    final message = tag.getCompound('LastException')?.getString('Component');
    lastException = message == null ? null : SimAssemblyException.fromComponentJson(message);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putDouble('TargetAngle', logic.targetAngleDegrees);
    final id = subLevelId;
    if (id != null) tag.putString('SubLevelID', id);
    final plate = platePos;
    if (plate != null) tag.putLong('SwivelPlate', packPos(plate.$1, plate.$2, plate.$3));
    if (logic.sequencedAngleLimit >= 0) {
      tag.putDouble('SequencedAngleLimit', logic.sequencedAngleLimit);
    }
    // `AssemblyException.write`: the message's component JSON, which the client reads.
    final exception = lastException;
    if (exception != null) {
      tag.putCompound('LastException', NbtCompound()..putString('Component', exception.toComponentJson()));
    }
  }

  /// `getTargetAngleDegrees()`.
  @override
  double get targetAngleDegrees => logic.targetAngleDegrees;

  void setBlockFlag(String property, bool value) {
    final w = world;
    if (w == null) return;
    final current = HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
    final next = current.setFlag(property, value);
    if (next == current) return;
    ignoredCall(setBlockState(w, pos.toPos(), next));
  }

  static (int, int, int) _relative((int, int, int) pos, String facing) => switch (facing) {
    'down' => (pos.$1, pos.$2 - 1, pos.$3),
    'up' => (pos.$1, pos.$2 + 1, pos.$3),
    'north' => (pos.$1, pos.$2, pos.$3 - 1),
    'south' => (pos.$1, pos.$2, pos.$3 + 1),
    'west' => (pos.$1 - 1, pos.$2, pos.$3),
    'east' => (pos.$1 + 1, pos.$2, pos.$3),
    _ => pos,
  };
}

/// `SwivelBearingPlateBlockEntity`: the block inside the sub-level.
final class SwivelBearingPlateBlockEntity extends CreateBlockEntity
    implements sable.BlockEntitySubLevelActor {
  /// The block entity type key.
  static const String type = 'simulated:swivel_bearing_link_block';

  /// The block key.
  static const String block = 'simulated:swivel_bearing_link_block';

  SwivelBearingPlateBlockEntity(super.worldId, super.pos);

  /// The bearing this plate belongs to.
  (int, int, int)? parent;

  /// The sub-level the bearing is on.
  String? parentSubLevelId;

  bool assembling = false;

  /// `setParent(bearing)`.
  void setParent(SwivelBearingBlockEntity bearing) {
    parent = bearing.pos.toPos();
    parentSubLevelId = simulatedHost.containingSubLevel(worldId, parent!)?.uniqueIdOrNull;
  }

  /// `beforeAssembly()`.
  void beforeAssembly() => assembling = true;

  /// `setParentAssembleNextTick()`.
  void setParentAssembleNextTick() {
    final parentPos = parent;
    if (parentPos == null) return;
    simulatedHost.blockEntityAt<SwivelBearingBlockEntity>(worldId, parentPos)?.assembleNextTick = true;
  }

  /// `fixParentLinkingWhenMoved()`.
  void fixParentLinkingWhenMoved() {
    final parentPos = parent;
    if (parentPos == null) return;
    final bearing = simulatedHost.blockEntityAt<SwivelBearingBlockEntity>(worldId, parentPos);
    if (bearing == null) return;

    bearing.setPlatePos(pos.toPos());
    final containing = simulatedHost.containingSubLevel(worldId, pos.toPos());
    final newId = containing?.uniqueIdOrNull;
    if (newId != bearing.subLevelId) {
      bearing.setSubLevelID(newId);
    }
  }

  @override
  void sable$physicsTick(sable.ServerSubLevel subLevel, sable.RigidBodyHandle handle, double timeStep) {
    final parentPos = parent;
    if (parentPos == null) return;
    // The plate's physics tick is what tells the bearing its hinge is live.
    simulatedHost.blockEntityAt<SwivelBearingBlockEntity>(worldId, parentPos)?._attachHingeIfMissing();
  }

  @override
  void sable$tick(sable.ServerSubLevel subLevel) {}

  @override
  Iterable<sable.SubLevel>? sable$getLoadingDependencies() => sable$getConnectionDependencies();

  @override
  Iterable<sable.SubLevel>? sable$getConnectionDependencies() {
    final id = parentSubLevelId;
    if (id == null) return null;
    final subLevel = simulatedHost.subLevelById(worldId, id);
    return subLevel == null ? null : [subLevel];
  }

  @override
  void onRemoved() {
    if (!assembling) {
      final parentPos = parent;
      if (parentPos != null &&
          simulatedHost.blockKeyAt(worldId, parentPos) == 'simulated:swivel_bearing') {
        simulatedHost.destroyBlock(worldId, parentPos, drop: false);
      }
    }
    super.onRemoved();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    final parentPacked = tag.getInt('ParentPos');
    if (parentPacked != null) parent = unpackPos(parentPacked);
    parentSubLevelId = tag.getString('ParentSubLevelId');
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final parentPos = parent;
    if (parentPos != null) tag.putLong('ParentPos', packPos(parentPos.$1, parentPos.$2, parentPos.$3));
    final id = parentSubLevelId;
    if (id != null) tag.putString('ParentSubLevelId', id);
  }
}
