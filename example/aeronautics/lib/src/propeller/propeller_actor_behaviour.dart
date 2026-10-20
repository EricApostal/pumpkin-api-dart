// The behaviour shared by every propeller: its layers, the airflow it pushes
// entities with, and the numbers the particles are spawned from.
//
// Java: `content/blocks/propeller/behaviour/PropellerActorBehaviour`.
//
// The Java behaviour holds a `SmartBlockEntity` and reads the world; the port
// takes a [PropellerActorView] (the propeller itself) and a [PropellerPushWorld]
// (the entities and the raycast), so the force model runs on the VM.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart' show BoundingBox3d, Pose3dc, Vector3d;

import 'geometry.dart';

/// `PropellerAirParticle` constants the force model reads.
abstract final class PropellerAirParticle {
  /// How quickly the air slows down, per block travelled.
  static const double frictionScale = 0.2;

  /// The life time of one particle, in ticks.
  static const int lifeTime = 20;
}

/// `PropellerActorBehaviour.PropellerLayer`: one disc of the propeller.
final class PropellerLayer {
  /// Distance along the thrust axis.
  final double offset;
  final double innerRadius;
  final double outerRadius;

  const PropellerLayer(this.offset, this.innerRadius, this.outerRadius);

  double get innerRadiusSquared => innerRadius * innerRadius;

  double get outerRadiusSquared => outerRadius * outerRadius;

  @override
  String toString() => 'PropellerLayer(offset: $offset, r: $innerRadius..$outerRadius)';
}

/// What the behaviour needs from the propeller.
abstract interface class PropellerActorView {
  /// `getThrust()`, in pixel-newtons.
  double get thrust;

  /// `getBlockDirection()`.
  Direction get blockDirection;

  /// `getAirflow()`, in m/s.
  double get airflow;

  /// `getCurrentAirPressure()`.
  double get airPressure;

  /// The block position of the propeller.
  Pos get blockPos;

  /// The direction the push acts along; the gyroscopic bearing tilts it.
  Vector3d get thrustDirection;
}

/// One entity the propeller may push.
abstract interface class PropellerPushTarget {
  /// `entity.getBoundingBox().getCenter()`.
  Vector3d get center;

  /// `entity.getDeltaMovement()`.
  Vector3d get deltaMovement;

  /// Contraptions, creative flight and diving boots are not pushed.
  bool get isIgnored;

  bool get isShiftKeyDown;

  /// `entity.setDeltaMovement`.
  void setDeltaMovement(Vector3d motion);

  /// `entity.fallDistance = 0`.
  void resetFallDistance();
}

/// The world queries the push needs.
abstract interface class PropellerPushWorld {
  /// The pose of the sub-level the propeller is on, or `null`.
  Pose3dc? get propellerSubLevelPose;

  /// The entities whose bounding box intersects [box].
  Iterable<PropellerPushTarget> entitiesIn(BoundingBox3d box);

  /// `Level.clip(...)` of the collider shape: whether the segment hits a block.
  bool segmentBlocked(Vector3d from, Vector3d to);
}

/// `PropellerActorBehaviour`, server side.
final class PropellerActorBehaviour {
  /// The most an entity's motion is corrected by, per tick.
  static const int maxAcceleration = 5;

  final PropellerActorView propeller;

  /// The discs of the propeller, sorted by offset.
  final List<PropellerLayer> layers = [];

  /// The largest outer radius of the layers.
  double radius = 0;

  /// The smoothed particle amount (client).
  double updatedParticleAmount = 0;

  /// The most particles one tick may spawn.
  int maxParticleAmount = 20;

  /// The smoothing of the particle amount.
  double particleSmoothing = 10;

  // Scratch vectors, reused so the tick allocates nothing.
  final Vector3d _storedMutPos = Vector3d();
  final Vector3d _transformedThrust = Vector3d();
  final Vector3d _clipStart = Vector3d();
  final Vector3d _clipEnd = Vector3d();
  final Vector3d _origin = Vector3d();

  PropellerActorBehaviour(this.propeller);

  /// Adds a disc, keeping [layers] sorted by offset.
  void addLayer(PropellerLayer layer) {
    radius = math.max(radius, layer.outerRadius);
    layers.add(layer);
    layers.sort((a, b) => a.offset.compareTo(b.offset));
  }

  /// Adds a disc with no hole.
  void addSimpleLayer(double offset, double radius) => addLayer(PropellerLayer(offset, 0, radius));

  /// `getAirflowTickSpeed`: the airflow in metres per tick.
  double get airflowTickSpeed => propeller.airflow / 20.0;

  /// `getParticleRange`: how far the air reaches, from the decay curve.
  double get particleRange {
    final speed = airflowTickSpeed;
    final magnitude = speed.abs() * PropellerAirParticle.frictionScale * PropellerAirParticle.lifeTime + 1;
    return speed.sign * math.log(magnitude) / PropellerAirParticle.frictionScale;
  }

  /// `getParticleSpeed`: the airflow clamped to five blocks per tick.
  double get particleSpeed => airflowTickSpeed.clamp(-5.0, 5.0);

  /// `getParticleCount`: the smoothed, clamped number of particles to spawn.
  int particleCount(double randomUnit) {
    var count = updatedParticleAmount * propeller.airPressure;
    if (particleSmoothing > 0) {
      count = math.log(count / particleSmoothing + 1) * particleSmoothing;
    }
    return math.min((count + randomUnit).floor(), maxParticleAmount);
  }

  /// Pushes every entity the propeller reaches, once per tick.
  void pushEntities(PropellerPushWorld world) {
    if (layers.isEmpty) return;

    final thrust = propeller.thrust;
    final thrustFlowMult = thrust.sign;
    final subLevelPose = world.propellerSubLevelPose;

    final distance = particleRange;
    var boxRadius = 0.0;
    var offsetMax = -double.maxFinite;
    var offsetMin = double.maxFinite;
    final d1 = math.max(distance, 0.0);
    final d0 = math.min(distance, 0.0);

    for (final layer in layers) {
      boxRadius = math.max(boxRadius, layer.outerRadius);
      offsetMax = math.max(offsetMax, layer.offset + d1);
      offsetMin = math.min(offsetMin, layer.offset + d0);
    }

    final rotation = directionRotation(propeller.blockDirection);
    final max = rotation.transform(Vector3d(boxRadius, offsetMax, boxRadius), Vector3d());
    final min = rotation.transform(Vector3d(-boxRadius, offsetMin, -boxRadius), Vector3d());

    final blockCenter = Vector3d(
      propeller.blockPos.$1 + 0.5,
      propeller.blockPos.$2 + 0.5,
      propeller.blockPos.$3 + 0.5,
    );
    min.add(blockCenter);
    max.add(blockCenter);

    var box = BoundingBox3d.full(
      math.min(min.x, max.x),
      math.min(min.y, max.y),
      math.min(min.z, max.z),
      math.max(min.x, max.x),
      math.max(min.y, max.y),
      math.max(min.z, max.z),
    );

    _transformedThrust.setFrom(propeller.thrustDirection);
    if (subLevelPose != null) {
      box = box.transform(subLevelPose, BoundingBox3d());
      subLevelPose.orientation().transform(_transformedThrust, _transformedThrust);
    }

    _origin.setFrom(blockCenter);
    if (subLevelPose != null) subLevelPose.transformPosition(_origin, _origin);

    for (final target in world.entitiesIn(box)) {
      if (target.isIgnored) continue;

      final center = target.center;
      _storedMutPos.setFrom(center).sub(_origin);

      final entityDistance = _transformedThrust.dot(_storedMutPos);
      _storedMutPos.fma(-entityDistance, _transformedThrust);
      final radialDistanceSq = _storedMutPos.lengthSquared;

      var layerForceScale = 0.0;
      var minLayerDistance = 100.0;

      for (final layer in layers) {
        var layerDistance = entityDistance - layer.offset;
        layerDistance *= thrustFlowMult;

        if (layerDistance > 0 && radialDistanceSq < layer.outerRadiusSquared) {
          final distanceScale = layerDistance * PropellerAirParticle.frictionScale;
          var innerRadiusScale = 0.0;
          if (layer.innerRadius > 0 && radialDistanceSq < layer.innerRadiusSquared) {
            innerRadiusScale =
                (layer.innerRadiusSquared - radialDistanceSq) / (layer.innerRadius * layer.outerRadius);
            innerRadiusScale *= innerRadiusScale * 12;
          }
          minLayerDistance = layerDistance;
          layerForceScale = math.max(layerForceScale, math.exp(-distanceScale - innerRadiusScale));
        }
      }

      if (layerForceScale <= 0) continue;

      _clipStart.setFrom(center).fma(thrustFlowMult * -minLayerDistance, _transformedThrust);
      _clipEnd.setFrom(center);

      if (world.segmentBlocked(_clipStart, _clipEnd)) continue;

      final modifier = target.isShiftKeyDown ? 0.125 : 1.0;

      // 0.55 is the acceleration that keeps a living entity aloft; the scaling
      // makes entities float at the edge of the particle range at high airflow.
      final forceScale = PropellerAirParticle.frictionScale * PropellerAirParticle.lifeTime * 0.55;
      final acceleration =
          forceScale *
          airflowTickSpeed *
          modifier *
          layerForceScale *
          math.min(propeller.airPressure, 1.0);

      final previous = target.deltaMovement;
      final motion = Vector3d(
        previous.x +
            (math.min(math.max(_transformedThrust.x * acceleration - previous.x, -maxAcceleration.toDouble()), maxAcceleration.toDouble()) / 8),
        previous.y +
            (math.min(math.max(_transformedThrust.y * acceleration - previous.y, -maxAcceleration.toDouble()), maxAcceleration.toDouble()) / 8),
        previous.z +
            (math.min(math.max(_transformedThrust.z * acceleration - previous.z, -maxAcceleration.toDouble()), maxAcceleration.toDouble()) / 8),
      );

      target.setDeltaMovement(motion);
      target.resetFallDistance();
    }
  }

  /// The particle origin of one spawn, for the client renderer: a random point
  /// on a random disc.
  Vector3d randomLayerPosition(math.Random random, Vector3d dest) {
    final layer = layers[random.nextInt(layers.length)];
    final r = math.sqrt(layer.innerRadiusSquared + (layer.outerRadiusSquared - layer.innerRadiusSquared) * random.nextDouble());
    final angle = math.pi * 2.0 * random.nextDouble();
    return dest.set(math.cos(angle) * r, layer.offset, math.sin(angle) * r);
  }

  @override
  String toString() => 'PropellerActorBehaviour(layers: ${layers.length}, radius: $radius)';
}
