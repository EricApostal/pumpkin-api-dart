import 'bindings.g.dart';
import 'geometry.dart';

/// Thrown when a [Location] names a world that is not loaded.
final class WorldNotLoadedException implements Exception {
  /// The world name that could not be found.
  final String world;

  /// Creates the exception.
  WorldNotLoadedException(this.world);

  @override
  String toString() => 'World "$world" is not loaded.';
}

/// Conversions from [Vec3] to generated types.
extension Vec3Conversions on (double, double, double) {
  /// The block containing this point.
  BlockPos toBlockPos() {
    final c = blockCoords;
    return BlockPos(x: c.$1, y: c.$2, z: c.$3);
  }

  /// This vector as a (single precision) [Vector3f].
  Vector3f toVector3f() => Vector3f(x: $1, y: $2, z: $3);
}

/// Math on block positions.
extension BlockPosMath on BlockPos {
  /// The center of the block.
  Vec3 get center => (x + 0.5, y + 0.5, z + 0.5);

  /// The minimum corner of the block as a [Vec3].
  Vec3 toVec3() => (x.toDouble(), y.toDouble(), z.toDouble());

  /// A copy moved by ([dx], [dy], [dz]).
  BlockPos offset(int dx, int dy, int dz) =>
      BlockPos(x: x + dx, y: y + dy, z: z + dz);

  /// Component-wise sum.
  BlockPos operator +(BlockPos o) => BlockPos(x: x + o.x, y: y + o.y, z: z + o.z);

  /// Component-wise difference.
  BlockPos operator -(BlockPos o) => BlockPos(x: x - o.x, y: y - o.y, z: z - o.z);

  /// The block above.
  BlockPos get above => offset(0, 1, 0);

  /// The block below.
  BlockPos get below => offset(0, -1, 0);

  /// The six face-adjacent blocks (down, up, north, south, west, east).
  List<BlockPos> get neighbours => [
    offset(0, -1, 0),
    offset(0, 1, 0),
    offset(0, 0, -1),
    offset(0, 0, 1),
    offset(-1, 0, 0),
    offset(1, 0, 0),
  ];

  /// Euclidean distance between block centers.
  double distanceTo(BlockPos o) => center.distanceTo(o.center);

  /// Squared distance between block centers.
  double distanceSquaredTo(BlockPos o) => center.distanceSquaredTo(o.center);

  /// Whether this has the same coordinates as [o].
  bool sameAs(BlockPos o) => x == o.x && y == o.y && z == o.z;
}

/// Conversions for [Vector3f].
extension Vector3fMath on Vector3f {
  /// This vector as a [Vec3].
  Vec3 toVec3() => (x, y, z);
}

/// Bindings-aware helpers for [Location].
extension LocationBindings on Location {
  /// The block containing the position.
  BlockPos get blockPos {
    final c = blockCoords;
    return BlockPos(x: c.$1, y: c.$2, z: c.$3);
  }

  /// The loaded world this location is in, or null. The result is an owned
  /// handle, valid for the current callback.
  World? worldIn(Server server) => server.getWorldByName(name: this.world);
}

/// World helpers.
extension WorldLocations on World {
  /// The shared spawn as a [Location] (block position centered in x and z,
  /// y as given). Named `spawnPoint` because `spawnLocation` is the raw
  /// record.
  Location get spawnPoint {
    final s = getSpawnLocation();
    return Location(
      world: getName(),
      x: s.pos.x + 0.5,
      y: s.pos.y.toDouble(),
      z: s.pos.z + 0.5,
      yaw: s.yaw,
      pitch: s.pitch,
    );
  }
}

/// Location helpers for entities.
extension EntityLocations on Entity {
  /// Current position, rotation and world name.
  Location get location => Location(
    world: getWorld().getName(),
    x: getPosition().$1,
    y: getPosition().$2,
    z: getPosition().$3,
    yaw: getYaw(),
    pitch: getPitch(),
  );

  /// Teleports to [target], looking the world up on [server].
  /// Throws [WorldNotLoadedException] if it isn't loaded.
  void teleportTo(Server server, Location target) {
    final w = server.getWorldByName(name: target.world);
    if (w == null) throw WorldNotLoadedException(target.world);
    // `teleport` consumes the world handle.
    teleport(pos: target.position, worldRef: w);
    setRotation(yaw: target.yaw, pitch: target.pitch);
  }
}

/// Location helpers for players.
extension PlayerLocations on Player {
  /// Current position, rotation and world name.
  Location get location {
    final p = getPosition();
    return Location(
      world: getWorld().getName(),
      x: p.$1,
      y: p.$2,
      z: p.$3,
      yaw: getYaw(),
      pitch: getPitch(),
    );
  }

  /// Teleports to [target], looking the world up on [server].
  /// Throws [WorldNotLoadedException] if it isn't loaded.
  void teleportTo(Server server, Location target) {
    final w = server.getWorldByName(name: target.world);
    if (w == null) throw WorldNotLoadedException(target.world);
    // `teleport` consumes the world handle.
    teleport(
      position: target.position,
      yaw: target.yaw,
      pitch: target.pitch,
      world: w,
    );
  }

  /// Moves within the current world, optionally changing the rotation.
  void moveTo(Vec3 position, {double? yaw, double? pitch}) {
    teleport(position: position, yaw: yaw, pitch: pitch, world: getWorld());
  }
}
