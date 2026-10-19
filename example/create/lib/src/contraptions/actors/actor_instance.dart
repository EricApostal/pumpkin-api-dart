// `ActorInstance`: the data a client visual of an actor is placed with (position, light, rotation
// axis and centre, speed). The Flywheel instance itself is client-only; this keeps the values the
// visual computes from the movement context so the actor code and the client agree.
import '../../common/common.dart';

/// `ActorInstance`.
class ActorInstance {
  double x = 0;
  double y = 0;
  double z = 0;
  int blockLight = 0;
  int skyLight = 0;
  double rotationOffset = 0;
  int rotationAxisX = 0;
  int rotationAxisY = 0;
  int rotationAxisZ = 0;

  /// The local rotation as a quaternion `(x, y, z, w)`.
  (double, double, double, double) rotation = (0, 0, 0, 1);

  int rotationCenterX = 64;
  int rotationCenterY = 64;
  int rotationCenterZ = 64;
  double speed = 0;

  ActorInstance setPosition(Pos pos) {
    x = pos.$1.toDouble();
    y = pos.$2.toDouble();
    z = pos.$3.toDouble();
    return this;
  }

  ActorInstance setBlockLight(int light) {
    blockLight = light;
    return this;
  }

  ActorInstance setSkyLight(int light) {
    skyLight = light;
    return this;
  }

  ActorInstance setRotationOffset(double offset) {
    rotationOffset = offset;
    return this;
  }

  ActorInstance setSpeed(double speed) {
    this.speed = speed;
    return this;
  }

  ActorInstance setRotationAxis(Vec3 axis) =>
      setRotationAxisXYZ(axis.$1, axis.$2, axis.$3);

  ActorInstance setRotationAxisXYZ(double x, double y, double z) {
    rotationAxisX = (x * 127).toInt();
    rotationAxisY = (y * 127).toInt();
    rotationAxisZ = (z * 127).toInt();
    return this;
  }

  ActorInstance setRotationCenter(Vec3 center) =>
      setRotationCenterXYZ(center.$1, center.$2, center.$3);

  ActorInstance setRotationCenterXYZ(double x, double y, double z) {
    rotationCenterX = (x * 127).toInt();
    rotationCenterY = (y * 127).toInt();
    rotationCenterZ = (z * 127).toInt();
    return this;
  }

  ActorInstance setLocalRotation((double, double, double, double) q) {
    rotation = q;
    return this;
  }
}
