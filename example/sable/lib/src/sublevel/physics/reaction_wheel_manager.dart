// `dev.ryanhcode.sable.physics.ReactionWheelManager`: turns the reaction wheels
// mounted on a sub-level into angular impulse.
//
// Each wheel contributes angular momentum `ω · inertia · mass` in the
// sub-level's local space (the block's `sable:inertia` property, or the default
// 1/6 when unset). The manager keeps the **previous** total momentum and, every
// physics tick, applies the difference as an angular impulse — a wheel that
// spins up therefore spins the ship the other way, and a wheel at constant speed
// applies nothing.
//
// Pure: no host imports.
import '../api/block/block_entity_sub_level_reaction_wheel.dart';
import '../api/physics.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import 'physics_block_properties.dart';

/// `ReactionWheelManager`.
final class ReactionWheelManager {
  final ServerSubLevel subLevel;

  /// The block properties used for mass and inertia.
  final PhysicsBlockPropertiesTable properties;

  /// The total local angular momentum of the last tick.
  final Vector3d previousAngularMomentum = Vector3d();

  final Vector3d _totalLocalAngularMomentum = Vector3d();
  final Vector3d _temp = Vector3d();
  final Vector3d _impulse = Vector3d();

  ReactionWheelManager(this.subLevel, this.properties);

  /// `physicsTick(handle)`.
  void physicsTick(RigidBodyHandle handle) {
    if (!needsTicking()) return;

    _totalLocalAngularMomentum.zero();
    for (final entry in subLevel.getPlot().blockEntityReactionWheels.entries) {
      _addWheelMomentum(entry.key, entry.value, _totalLocalAngularMomentum);
    }
    subLevel.logicalPose.orientation().transform(_totalLocalAngularMomentum, _totalLocalAngularMomentum);

    _totalLocalAngularMomentum.subInto(previousAngularMomentum, _impulse);
    subLevel.logicalPose.orientation().transformInverse(_impulse, _impulse);

    handle.applyLinearAndAngularImpulse(Vector3d(), _impulse, true);
    previousAngularMomentum.setFrom(_totalLocalAngularMomentum);
  }

  /// `needsTicking()`.
  bool needsTicking() =>
      previousAngularMomentum.lengthSquared > 0 ||
      subLevel.getPlot().blockEntityReactionWheels.isNotEmpty;

  /// `wheelChanged(pos, wheel, add)`: keeps the running total consistent when a
  /// wheel appears or disappears.
  void wheelChanged((int, int, int) pos, BlockEntitySubLevelReactionWheel wheel, bool add) {
    _addWheelMomentum(pos, wheel, _totalLocalAngularMomentum.zero());
    subLevel.logicalPose.orientation().transform(_totalLocalAngularMomentum, _totalLocalAngularMomentum);
    if (add) {
      previousAngularMomentum.add(_totalLocalAngularMomentum);
    } else {
      previousAngularMomentum.sub(_totalLocalAngularMomentum);
    }
  }

  void _addWheelMomentum(
    (int, int, int) pos,
    BlockEntitySubLevelReactionWheel wheel,
    Vector3d dest,
  ) {
    wheel.sable$getAngularVelocity(_temp.zero());

    final state = wheel.getBlockState().toString();
    final inertia = properties.inertiaOf(state, true);
    if (inertia == null) {
      _temp.mul(1 / 6.0); // Default block inertia.
    } else {
      _temp
        ..x *= inertia.$1
        ..y *= inertia.$2
        ..z *= inertia.$3;
    }

    dest.fma(properties.massOf(state, true), _temp);
  }

  @override
  String toString() =>
      'ReactionWheelManager[${subLevel.uniqueId}, '
      '${subLevel.getPlot().blockEntityReactionWheels.length} wheels]';
}
