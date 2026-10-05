import 'bindings.g.dart' hide BlockRegistry;
import 'blocks.dart';
import 'geometry.dart';

/// Iteration over the blocks of a [Cuboid].
extension CuboidBlocks on Cuboid {
  /// Lazily iterates every block position.
  Iterable<BlockPos> get blocks sync* {
    for (final (x, y, z) in blockCoords) {
      yield BlockPos(x: x, y: y, z: z);
    }
  }

  /// Whether [pos] is inside.
  bool containsBlock(BlockPos pos) => containsBlockXYZ(pos.x, pos.y, pos.z);

  /// The cuboid spanned by two block positions.
  static Cuboid between(BlockPos a, BlockPos b) =>
      Cuboid.corners((a.x, a.y, a.z), (b.x, b.y, b.z));
}

/// Bulk block changes over a [Cuboid]. The WIT has no bulk call for arbitrary
/// regions, so these loop over the blocks synchronously: keep regions modest.
extension WorldFill on World {
  /// Sets every block of [region] to the block state [stateId]. Returns the
  /// number of blocks set. [flags] default to notifying clients.
  int fill(
    Cuboid region,
    int stateId, {
    Set<BlockFlagsFlag> flags = const {BlockFlagsFlag.notifyListeners},
  }) {
    var n = 0;
    for (final pos in region.blocks) {
      setBlockState(pos: pos, state: stateId, updateFlags: flags);
      n++;
    }
    return n;
  }

  /// Fills [region] with the block [key] (`stone`, `minecraft:stone`) using
  /// its default state. Returns false (and changes nothing) if unknown.
  bool fillBlock(
    Cuboid region,
    String key, {
    Set<BlockFlagsFlag> flags = const {BlockFlagsFlag.notifyListeners},
  }) {
    final id = BlockRegistry.resolveState(key);
    if (id == null) return false;
    fill(region, id, flags: flags);
    return true;
  }

  /// Replaces blocks in state [from] by [to] inside [region]. Returns the
  /// number replaced.
  int replace(
    Cuboid region,
    int from,
    int to, {
    Set<BlockFlagsFlag> flags = const {BlockFlagsFlag.notifyListeners},
  }) {
    var n = 0;
    for (final pos in region.blocks) {
      if (getBlockStateId(pos: pos) == from) {
        setBlockState(pos: pos, state: to, updateFlags: flags);
        n++;
      }
    }
    return n;
  }

  /// Counts blocks of state [stateId] in [region].
  int countState(Cuboid region, int stateId) {
    var n = 0;
    for (final pos in region.blocks) {
      if (getBlockStateId(pos: pos) == stateId) n++;
    }
    return n;
  }

  /// Entities of this world within [radius] of [center], nearest first.
  /// Optionally only those of [type]. Handles are valid for this callback.
  List<Entity> entitiesNear(Vec3 center, double radius, {EntityType? type}) {
    final r2 = radius * radius;
    final found = <(double, Entity)>[];
    for (final e in getEntities()) {
      if (type != null && e.getType() != type) continue;
      final d = e.getPosition().distanceSquaredTo(center);
      if (d <= r2) found.add((d, e));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }

  /// The entity nearest to [center] within [radius], or null.
  Entity? nearestEntity(Vec3 center, double radius, {EntityType? type}) {
    final l = entitiesNear(center, radius, type: type);
    return l.isEmpty ? null : l.first;
  }
}

/// Player queries on the server.
extension ServerSpatial on Server {
  /// Players within [radius] of [center], nearest first. With [worldName]
  /// only players in that world count (otherwise every world, comparing
  /// coordinates only). Handles are valid for this callback.
  List<Player> playersNear(Vec3 center, double radius, {String? worldName}) {
    final r2 = radius * radius;
    final found = <(double, Player)>[];
    for (final p in getAllPlayers()) {
      if (worldName != null && p.getWorld().getName() != worldName) continue;
      final d = p.getPosition().distanceSquaredTo(center);
      if (d <= r2) found.add((d, p));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }

  /// The player nearest to [center] within [radius], or null.
  Player? nearestPlayer(Vec3 center, double radius, {String? worldName}) {
    final l = playersNear(center, radius, worldName: worldName);
    return l.isEmpty ? null : l.first;
  }

  /// Players whose position lies inside [box].
  List<Player> playersIn(Cuboid box, {String? worldName}) => [
    for (final p in getAllPlayers())
      if (box.contains(p.getPosition()) &&
          (worldName == null || p.getWorld().getName() == worldName))
        p,
  ];

  /// Players in the world called [name] (empty if it isn't loaded).
  List<Player> playersInWorldNamed(String name) {
    final w = getWorldByName(name: name);
    // `getPlayersInWorld` consumes the world handle.
    return w == null ? const [] : getPlayersInWorld(worldRef: w);
  }
}

/// Entity queries around an entity.
extension EntitySpatial on Entity {
  /// Other entities within [radius] (a sphere), nearest first. Uses the
  /// host's box lookup, which excludes this entity.
  List<Entity> entitiesWithin(double radius) {
    final me = getPosition();
    final r2 = radius * radius;
    final found = <(double, Entity)>[];
    for (final e in getNearbyEntities(x: radius, y: radius, z: radius)) {
      final d = e.getPosition().distanceSquaredTo(me);
      if (d <= r2) found.add((d, e));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }
}
