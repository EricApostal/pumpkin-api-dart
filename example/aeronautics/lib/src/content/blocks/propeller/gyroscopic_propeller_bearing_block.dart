// The gyroscopic propeller bearing: a propeller bearing whose propeller hangs
// like a pendulum and tilts towards gravity.
//
// Java: `content/blocks/propeller/bearing/gyroscopic_propeller_bearing/{GyroscopicPropellerBearingBlock,GyroscopicPropellerBearingBlockEntity}`.
//
// The tilt is clamped to 12 degrees around the bearing's facing and drives the
// thrust direction; a redstone signal locks it to the mount. The tilt is
// updated once per game tick and once per physics substep, the latter with a
// larger step so the pendulum does not lag behind a fast-moving ship.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/create.dart';
import 'package:create/src/contraptions/bearing/bearing_blocks.dart' show bearingBehavior;
import 'package:create/src/contraptions/bearing/bearing_placement.dart' show bearingPlacementRules;
import 'package:create/src/kinetics/block_data.dart' show facingShaftTag;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart';

import '../../../propeller/gyroscopic_tilt.dart';
import 'propeller_bearing_block.dart';

/// The block key.
const String gyroscopicPropellerBearingKey = 'aeronautics:gyroscopic_propeller_bearing';

/// `GyroscopicPropellerBearingBlockEntity`.
final class GyroscopicPropellerBearingBlockEntity extends PropellerBearingBlockEntity {
  GyroscopicPropellerBearingBlockEntity(super.worldId, super.pos);

  /// The pendulum state.
  final GyroscopicTilt tilt = GyroscopicTilt();

  bool _powered = false;

  /// Whether a redstone signal locks the tilt to the mount.
  bool get powered => _powered;

  @override
  void onLoad() {
    super.onLoad();
    tilt.setFacing(blockDirection);
    tilt.initializeIfNeeded(blockDirection);
  }

  @override
  void tick() {
    tilt.initializeIfNeeded(blockDirection);
    tilt.previousTiltQuat.setFrom(tilt.tiltQuat);

    unawaited(_refreshSignal());

    final level = getLevel();
    final subLevel = SubLevelHelper.getContaining(level, blockPos);
    final gravity = DimensionPhysicsData.getGravity(level, Vector3d(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5));
    tilt.updateTilt(tilt.tiltVector, subLevel?.logicalPose.orientation(), gravity, 1);
    tilt.applyTilt();

    // The bearing pushes along the tilt, not along its facing.
    thrustDirection.setFrom(tilt.thrustDirection);
    super.tick();
  }

  Future<void> _refreshSignal() async {
    final w = world;
    if (w == null) return;
    final powered = await w.hasNeighborSignal(pos: pos);
    if (powered == _powered) return;
    _powered = powered;
    tilt.powered = powered;
    sendData();
  }

  @override
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) {
    tilt.physicsTimer += timeStep * 20;

    final level = getLevel();
    final gravity = DimensionPhysicsData.getGravity(level, Vector3d(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5));
    tilt.updateTilt(tilt.tiltVector, subLevel.logicalPose.orientation(), gravity, tilt.physicsTimer);
    tilt.applyTilt();

    thrustDirection.setFrom(tilt.thrustDirection);
    if (isActive()) applyForces(subLevel, thrustDirection, timeStep);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('IsPowered', _powered);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    _powered = tag.getBool('IsPowered') ?? false;
    tilt.powered = _powered;
  }

  /// `forceTilt`: snaps the pendulum back to the mount (used after a wrench).
  void forceTilt() => tilt.forceTilt(blockDirection);
}

/// `GyroscopicPropellerBearingBlock`.
CreateBlock buildGyroscopicPropellerBearingBlock() => CreateBlock(
  key: gyroscopicPropellerBearingKey,
  properties: [CreateProps.facing],
  defaultState: {'facing': 'north'},
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'copper',
  canOcclude: false,
  tags: [facingShaftTag],
  placement: bearingPlacementRules,
  blockEntityType: gyroscopicPropellerBearingKey,
  behavior: bearingBehavior(gyroscopicPropellerBearingKey),
);
