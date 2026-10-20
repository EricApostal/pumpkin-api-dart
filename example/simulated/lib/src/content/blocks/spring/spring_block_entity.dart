// The block entity of the spring: it pairs with the spring block it was placed
// against, and once per physics tick hands the two ends' state to
// [SpringLogic] and applies the impulses.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.content.blocks.spring.SpringBlockEntity
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/core/block_entity.dart';
import 'package:create/src/core/pos.dart' show packPos, unpackPos;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show BlockEntitySubLevelActor, RigidBodyHandle, ServerSubLevel, SubLevel, Vector3d;

import '../../../host/simulated_host.dart';
import '../../../util/sim_level_util.dart';
import 'spring_logic.dart';

/// `SpringBlockEntity`.
final class SpringBlockEntity extends CreateBlockEntity implements BlockEntitySubLevelActor {
  /// The block entity type key.
  static const String type = 'simulated:spring';

  /// The block key.
  static const String block = 'simulated:spring';

  SpringBlockEntity(super.worldId, super.pos);

  /// The spring state.
  final SpringLogic logic = SpringLogic();

  BState state = BState(block);

  /// The position of the partner spring.
  (int, int, int)? partnerPos;

  /// The sub-level the partner is on, if any.
  String? partnerSubLevelId;

  /// `getCenter()`: half a block behind the block's centre, towards its facing.
  Vector3d get center {
    final facing = _facing(state);
    const scale = 0.5 - 4.0 / 16.0;
    return Vector3d(
      pos.x + 0.5 - facing.stepX * scale,
      pos.y + 0.5 - facing.stepY * scale,
      pos.z + 0.5 - facing.stepZ * scale,
    );
  }

  /// `getPairedSpring()`.
  SpringBlockEntity? get pairedSpring {
    final partner = partnerPos;
    if (partner == null) return null;
    return simulatedHost.blockEntityAt<SpringBlockEntity>(worldId, partner);
  }

  /// `tryChangeLengthOrError(delta)`: the reason it cannot change, or `null`.
  String? tryChangeLength(double delta) {
    final partner = pairedSpring;
    final centerPos = (pos.x, pos.y, pos.z);
    final distance = partner == null
        ? 0.0
        : _distanceTo(centerPos, partner.pos.toPos());
    final error = logic.tryChangeLength(delta, currentLength: distance);
    if (error == null) {
      partner?.logic.desiredLength = logic.desiredLength;
      partner?.sendData();
      sendData();
    }
    return error;
  }

  double _distanceTo((int, int, int) a, (int, int, int) b) {
    final dx = a.$1 - b.$1, dy = a.$2 - b.$2, dz = a.$3 - b.$3;
    return (dx * dx + dy * dy + dz * dz).toDouble();
  }

  /// `setPartnerPos(pos, subLevel)`.
  void setPartnerPos((int, int, int) pos, String? subLevelId) {
    partnerPos = pos;
    partnerSubLevelId = subLevelId;
    sendData();
  }

  @override
  void tick() {
    final w = world;
    if (w != null && !removed) {
      state = HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
    }

    final partner = partnerPos;
    if (partner == null) {
      // A spring without a partner is broken.
      simulatedHost.destroyBlock(worldId, pos.toPos());
      return;
    }

    final level = simulatedHost.levelOf(worldId);
    if (level != null && SimLevelUtil.isAreaActuallyLoaded(level, partner, 1)) {
      if (pairedSpring == null) {
        logic.ticksWithoutPartner++;
        if (logic.ticksWithoutPartner > 20) {
          simulatedHost.destroyBlock(worldId, pos.toPos());
        }
      } else {
        logic.ticksWithoutPartner = 0;
      }
    }

    if (logic.snappingTime > SpringLogic.timeToSnap) {
      simulatedHost.destroyBlock(worldId, pos.toPos());
    }

    super.tick();
  }

  @override
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) {
    final partner = pairedSpring;
    final partnerPosValue = partnerPos;
    if (partner == null || partnerPosValue == null || logic.ticksWithoutPartner != 0) return;
    if (!logic.isController) return;
    if (partnerSubLevelId != null && partnerSubLevelId == subLevel.uniqueIdOrNull) return;

    final partnerSubLevel = partnerSubLevelId == null
        ? null
        : simulatedHost.subLevelById(worldId, partnerSubLevelId!) as ServerSubLevel?;

    final pose = subLevel.logicalPose;
    final partnerPose = partnerSubLevel?.logicalPose;

    final centerA = center;
    final centerB = partner.center;

    final positionA = pose.transformPosition(Vector3d.copy(centerA));
    final positionB = partnerPose == null
        ? Vector3d(partner.pos.x + 0.5, partner.pos.y + 0.5, partner.pos.z + 0.5)
        : partnerPose.transformPosition(
            Vector3d(partner.pos.x + 0.5, partner.pos.y + 0.5, partner.pos.z + 0.5),
          );

    final velocityA = handle.getLinearVelocity();
    final velocityB = partnerSubLevel?.physicsBody?.getLinearVelocity() ?? Vector3d();
    final angularA = handle.getAngularVelocity();
    final angularB = partnerSubLevel?.physicsBody?.getAngularVelocity() ?? Vector3d();

    final normalA = Vector3d(_facing(state).stepX.toDouble(), _facing(state).stepY.toDouble(), _facing(state).stepZ.toDouble());
    final normalB = Vector3d(
      _facing(partner.state).stepX.toDouble(),
      _facing(partner.state).stepY.toDouble(),
      _facing(partner.state).stepZ.toDouble(),
    );
    pose.transformNormal(normalA);
    partnerPose?.transformNormal(normalB);

    final massTracker = subLevel.massTracker;
    final context = SpringPhysicsContext(
      center: centerA,
      partnerCenter: centerB,
      positionA: positionA,
      positionB: positionB,
      velocity: velocityA,
      partnerVelocity: velocityB,
      normalA: normalA,
      normalB: normalB,
      angularVelocity: angularA,
      partnerAngularVelocity: angularB,
      inverseMass: massTracker?.getInverseMass() ?? 0,
      // HOST GAP: sable's `MassData` does not expose the inertia tensor yet, so
      // the angular damping uses the inverse mass as a scalar approximation.
      inverseInertia: (v) => Vector3d.copy(v)..mul(massTracker?.getInverseMass() ?? 0),
      centerOfMass: massTracker?.getCenterOfMass() ?? Vector3d(),
      size: SpringSize.byName(state['size']),
      timeStep: timeStep,
    );

    final impulse = logic.physicsTick(context);
    if (impulse == null) return;

    handle.applyLinearAndAngularImpulse(impulse.linear, impulse.angular, true);

    final partnerHandle = partnerSubLevel?.physicsBody;
    if (partnerHandle != null) {
      partnerHandle.applyLinearAndAngularImpulse(
        Vector3d.copy(impulse.linear)..negate(),
        Vector3d.copy(impulse.angular)..negate(),
        true,
      );
    }
  }

  @override
  void sable$tick(ServerSubLevel subLevel) {}

  @override
  Iterable<SubLevel>? sable$getLoadingDependencies() => sable$getConnectionDependencies();

  @override
  Iterable<SubLevel>? sable$getConnectionDependencies() {
    final id = partnerSubLevelId;
    if (id == null) return null;
    final subLevel = simulatedHost.subLevelById(worldId, id);
    return subLevel == null ? null : [subLevel];
  }

  @override
  void onRemoved() {
    final partner = partnerPos;
    if (partner != null && !logic.assembling) {
      simulatedHost.destroyBlock(worldId, partner, drop: false);
    }
    partnerPos = null;
    super.onRemoved();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    logic.read(
      isController: tag.getBool('Controller') ?? false,
      desiredLength: tag.getDouble('DesiredLength') ?? 0,
    );
    final goal = tag.getInt('Goal');
    if (goal != null) partnerPos = unpackPos(goal);
    partnerSubLevelId = tag.getString('GoalSubLevel');
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putBool('Controller', logic.isController);
    tag.putDouble('DesiredLength', logic.desiredLength);
    final partner = partnerPos;
    if (partner != null) tag.putLong('Goal', packPos(partner.$1, partner.$2, partner.$3));
    final id = partnerSubLevelId;
    if (id != null) tag.putString('GoalSubLevel', id);
  }

  static Direction _facing(BState state) => state.dir('facing') ?? Direction.up;
}
