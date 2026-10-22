// The balloon model's view of a Pumpkin world, and the tag that makes a block
// airtight.
//
// Java reads `Level` directly; the port keeps the model pure and hands it this
// adapter instead.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/host_bridge.dart' show PosToHost;
import 'package:create/src/core/worlds.dart' show WorldRef;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show SableLevel;

import '../../aeronautics_plugin.dart';
import '../hot_air/balloon_world.dart';

/// The tags and keys Aeronautics adds.
abstract final class AeroTags {
  /// `aeronautics:airtight`: a block that closes a balloon.
  static const String airtight = 'aeronautics:airtight';

  /// The mod id.
  static const String modId = 'aeronautics';
}

/// `SableLevel` over a host world.
final class WorldSableLevel implements SableLevel {
  WorldSableLevel(this._world);

  final WorldRef _world;

  /// A handle that is valid right now: the one the current callback passed in,
  /// or the kept one [WorldRef.worlds] resolves.
  World get world => _world.world;

  /// `Level.dimension().identifier().toString()`: the dimension key (`minecraft:overworld`).
  /// Not the world id (`World.getId()`, the folder name `world`) — Sable puts this value on the
  /// wire (`sable:dimension_physics`) and into `/execute in <dimension>` suggestions.
  @override
  String get dimensionId => world.getDimension();

  @override
  bool get isClientSide => false;

  // The host does not expose the build height; these are the vanilla overworld
  // limits, which every dimension of a server with sub-levels uses today.
  @override
  int get minY => -64;

  @override
  int get maxY => 319;

  @override
  int get gameTime => 0;

  @override
  int get sectionsCount => (maxY - minY) >> 4;

  @override
  String? biomeAt(int x, int y, int z) => null;
}

/// `BalloonWorld` over a host world.
final class WorldBalloonWorld implements BalloonWorld {
  WorldBalloonWorld(this._world) : sableLevel = WorldSableLevel(_world);

  /// The world id and a handle that survives its callback (see [WorldRef]).
  final WorldRef _world;

  /// The level view handed to the sub-level model.
  final WorldSableLevel sableLevel;

  /// A handle that is valid right now.
  World get world => _world.world;

  /// Points the adapter at the live handle of the callback that is using it.
  void bind(World world) => _world.bind(world);

  @override
  String get id => _world.id;

  @override
  SableLevel get level => sableLevel;

  @override
  int get minY => sableLevel.minY;

  @override
  int get maxY => sableLevel.maxY;

  @override
  bool get isServerSide => true;

  @override
  BState stateAt(int x, int y, int z) =>
      HostBlockGetter.stateOfId(world.getBlockStateId(pos: BlockPos(x: x, y: y, z: z)));

  @override
  bool isAirtight(BState state) => Tags.block(state.key, AeroTags.airtight);


  /// The host position of a block position.
  static BlockPos blockPosOf((int, int, int) pos) => pos.toBlockPos();
}

/// The world adapters, by world id (the balloon map is keyed by the same id).
final Map<String, WorldBalloonWorld> _worlds = {};

/// The balloon world of [world].
///
/// The adapter is created once per world id and never keeps the handle it was
/// created with: an event's world is released when the callback that received
/// it returns, so a stored handle is dead from then on. Every call binds the
/// live handle it was given, and [WorldBalloonWorld.world] falls back to the
/// plugin's kept table ([AeronauticsHooks.worlds]) once that handle is gone.
WorldBalloonWorld balloonWorldOf(World world) {
  final id = world.getId();
  final existing = _worlds[id];
  if (existing != null) {
    existing.bind(world);
    return existing;
  }
  final created = WorldBalloonWorld(WorldRef(AeronauticsHooks.worlds, id, world));
  _worlds[id] = created;
  return created;
}

/// Forgets the cached adapters (plugin unload).
void clearBalloonWorlds() => _worlds.clear();
