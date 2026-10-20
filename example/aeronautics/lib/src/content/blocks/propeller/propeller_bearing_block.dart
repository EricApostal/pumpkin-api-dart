// The propeller bearing: a mechanical bearing whose contraption is a propeller.
//
// Java: `content/blocks/propeller/bearing/propeller_bearing/{PropellerBearingBlock,PropellerBearingBlockEntity}`.
//
// The bearing turns its contraption like a mechanical bearing does; the sails
// captured in that contraption become the propeller's discs, and the bearing's
// rotation speed turns them into thrust along the facing. The thrust goes into
// the `sable:propulsion` force group from `sable$physicsTick`.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/contraptions/core/nbt_map.dart' show NbtMap;
import 'package:create/src/contraptions/bearing/bearing_blocks.dart' show bearingBehavior;
import 'package:create/src/contraptions/bearing/bearing_placement.dart' show bearingPlacementRules;
import 'package:create/src/contraptions/bearing/bearing_block_entities.dart' show MechanicalBearingBlockEntity;
import 'package:create/src/kinetics/behaviours.dart' show ScrollValueBehaviour;
import 'package:create/src/kinetics/block_data.dart' show facingShaftTag;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart';

import '../../../config/aero_config.dart';
import '../../../host/world_balloon_world.dart';
import '../../../propeller/propeller_actor_behaviour.dart';
import '../../../propeller/propeller_bearing.dart';
import 'propeller_block_entity_mixin.dart';

/// The block and block entity key.
const String propellerBearingKey = 'aeronautics:propeller_bearing';

/// `PropellerBearingBlockEntity`.
class PropellerBearingBlockEntity extends MechanicalBearingBlockEntity
    with SubLevelPropellerActorMixin, PropellerBlockEntityMixin
    implements BlockEntitySubLevelPropellerActor, BlockEntityPropeller, PropellerActorView {
  PropellerBearingBlockEntity(super.worldId, super.pos);

  /// The sail scan, thrust and rotation maths.
  final PropellerBearingLogic logic = PropellerBearingLogic();

  /// The thrust direction, in the sub-level's frame.
  @override
  final Vector3d thrustDirection = Vector3d();

  /// The push behaviour of the sails.
  late final PropellerActorBehaviour prop = _createProp();

  late final PropellerPushWorld _pushWorld = _HostPushWorld(this);

  /// The contraption the discs were scanned from; the scan is redone when the
  /// bearing picks up a different one.
  Object? _scannedContraption;

  /// The direction option of the scroll value.
  ThrustDirection get thrustDirectionOption =>
      ThrustDirection.fromIndex(getBehaviour<ScrollValueBehaviour>()?.value ?? 0);

  /// The state of the block as plain data.
  BState get bState => BState(blockState.block, blockState.props);

  PropellerActorBehaviour _createProp() {
    final behaviour = PropellerActorBehaviour(this);
    behaviour.maxParticleAmount = 50;
    behaviour.particleSmoothing = 10;
    return behaviour;
  }

  // -- BlockEntityPropeller ------------------------------------------------------

  @override
  Direction getBlockDirection() => blockDirection;

  @override
  double getAirflow() => airflow;

  @override
  double getThrust() => thrust;

  @override
  bool isActive() => logic.isActive(hasContraption: movedContraption != null);

  @override
  SableLevel getLevel() {
    final w = world;
    if (w == null) throw StateError('$this: the world is not loaded');
    return balloonWorldOf(w).level;
  }

  @override
  Pos getBlockPos() => blockPos;

  @override
  BlockEntityPropeller getPropeller() => this;

  // -- PropellerActorView ---------------------------------------------------------

  @override
  Direction get blockDirection => bState.dir('facing') ?? Direction.north;

  @override
  Pos get blockPos => (pos.x, pos.y, pos.z);

  @override
  double get thrust => logic.thrust(AeroConfig.server.physics.propellerBearingThrust);

  @override
  double get airflow => logic.airflow(AeroConfig.server.physics.propellerBearingAirflowMult);

  @override
  double get airPressure {
    final level = getLevel();
    final center = Vector3d(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5);
    return DimensionPhysicsData.getAirPressure(level, SubLevelHelper.projectOutOfSubLevel(level, center));
  }

  // -- Lifecycle -----------------------------------------------------------------

  @override
  void onLoad() {
    logic.facing = blockDirection;
    super.onLoad();
  }

  @override
  void tick() {
    logic.facing = blockDirection;
    logic.thrustDirectionOption = thrustDirectionOption;

    if (logic.disassemblySlowdown) {
      final angleAfterStep = logic.tickSlowdown();
      if (angleAfterStep == null) {
        disassemble();
      } else {
        angle = angleAfterStep;
      }
    } else {
      logic.updateRotationSpeed(speed);
    }

    thrustDirection.set(
      logic.facing.stepX.toDouble(),
      logic.facing.stepY.toDouble(),
      logic.facing.stepZ.toDouble(),
    );

    super.tick();

    if (movedContraption != null) {
      if (!identical(_scannedContraption, movedContraption?.contraption)) {
        _scannedContraption = movedContraption?.contraption;
        findSails();
      }
      if (isActive()) prop.pushEntities(_pushWorld);
    }
  }

  /// `findSails`: scans the contraption for windmill sails and rebuilds the
  /// propeller's discs.
  void findSails() {
    final contraption = movedContraption?.contraption;
    if (contraption == null) {
      logic.totalSailPower = 0;
      logic.sailPositions.clear();
      logic.layers.clear();
      prop.layers.clear();
      prop.radius = 0;
      return;
    }

    final states = <Pos, BState>{};
    for (final entry in contraption.blocks.entries) {
      states[entry.key] = _sailMaterial(entry.value.state, entry.value.nbt);
    }

    logic.findSails(states, _isSail);

    prop.layers
      ..clear()
      ..addAll(logic.layers);
    prop.radius = prop.layers.isEmpty
        ? 0
        : prop.layers.map((layer) => layer.outerRadius).reduce((a, b) => a > b ? a : b);
  }

  /// `getSailPower`'s material resolution: a copycat panel counts as the block
  /// its `Material` tag names.
  BState _sailMaterial(BState state, NbtMap? nbt) {
    if (state.key != 'create:copycat_panel' || nbt == null) return state;
    final material = nbt.getCompoundOrNull('Material');
    final name = material?.getString('Name');
    if (name == null || name.isEmpty) return state;
    return BState(name.contains(':') ? name : 'minecraft:$name');
  }

  /// `getSailPower`: whether a block is a windmill sail.
  bool _isSail(BState state) {
    return Tags.block(state.key, 'create:windmill_sails');
  }

  /// The thrust of the bearing applied for one physics tick.
  @override
  void applyForces(ServerSubLevel subLevel, Vector3d direction, double timeStep) {
    final thrustVector = Vector3d.copy(direction).mul(getScaledThrust() * timeStep);
    final group = subLevel.getOrCreateQueuedForceGroup(ForceGroup.propulsion);
    group.applyAndRecordPointForce(
      Vector3d(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5),
      thrustVector,
    );
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putDouble('RotationSpeed', logic.rotationSpeed);
    tag.putBool('DisassemblySlowdown', logic.disassemblySlowdown);
    if (logic.disassemblySlowdown) {
      for (final entry in logic.slowdownController.write().entries) {
        final value = entry.value;
        if (value is double) tag.putDouble(entry.key, value);
        if (value is int) tag.putInt(entry.key, value);
      }
    }
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (wasMoved) return;
    logic.rotationSpeed = tag.getDouble('RotationSpeed') ?? 0;
    logic.disassemblySlowdown = tag.getBool('DisassemblySlowdown') ?? false;
    if (logic.disassemblySlowdown) {
      logic.slowdownController.read({
        for (final key in const [
          'CurrentTime',
          'DisassemblyTimerTotal',
          'Symmetry',
          'InitialSlowdownAngle',
          'InitialSlowdownVelocity',
        ])
          key: tag.getDouble(key),
      });
    }
  }

  /// `startDisassemblySlowdown`: wind down to a symmetry angle before the
  /// contraption comes off.
  void startDisassemblySlowdown() {
    final contraption = movedContraption?.contraption;
    if (contraption == null || logic.disassemblySlowdown) return;

    logic.startDisassemblySlowdown(
      currentAngle: getInterpolatedAngle(0),
      blocks: {for (final entry in contraption.blocks.entries) entry.key: entry.value.state.key},
    );
    updateGeneratedRotation();
    sendData();
  }

  @override
  void disassemble() {
    if (running && movedContraption != null) {
      angle = 0;
      prop.layers.clear();
      applyRotation();
    }
    super.disassemble();
  }
}

/// The push world of one propeller bearing.
final class _HostPushWorld implements PropellerPushWorld {
  final PropellerBearingBlockEntity owner;

  _HostPushWorld(this.owner);

  @override
  Pose3dc? get propellerSubLevelPose {
    final w = owner.world;
    if (w == null) return null;
    return SubLevelHelper.getContaining(balloonWorldOf(w).level, owner.blockPos)?.logicalPose;
  }

  @override
  Iterable<PropellerPushTarget> entitiesIn(BoundingBox3d box) => const [];

  @override
  bool segmentBlocked(Vector3d from, Vector3d to) => false;
}

/// `PropellerBearingBlock`.
CreateBlock buildPropellerBearingBlock() => CreateBlock(
  key: propellerBearingKey,
  properties: [CreateProps.facing],
  defaultState: {'facing': 'north'},
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'wood',
  canOcclude: false,
  tags: [facingShaftTag],
  placement: bearingPlacementRules,
  blockEntityType: propellerBearingKey,
  behavior: bearingBehavior(propellerBearingKey),
);
