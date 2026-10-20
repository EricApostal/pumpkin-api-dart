// The balloon model's view of a Pumpkin world, and the tag that makes a block
// airtight.
//
// Java reads `Level` directly; the port keeps the model pure and hands it this
// adapter instead.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/host_bridge.dart' show PosToHost;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show SableLevel;

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
  final World world;

  WorldSableLevel(this.world);

  @override
  String get dimensionId => world.getId();

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
  final World world;

  /// The level view handed to the sub-level model.
  final WorldSableLevel sableLevel;

  WorldBalloonWorld(this.world) : sableLevel = WorldSableLevel(world);

  @override
  String get id => world.getId();

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

/// The world adapter of [world], cached per world id (the balloon map is keyed
/// by the same id).
final Map<String, WorldBalloonWorld> _worlds = {};

/// The balloon world of [world].
WorldBalloonWorld balloonWorldOf(World world) =>
    _worlds.putIfAbsent(world.getId(), () => WorldBalloonWorld(world));

/// Forgets the cached adapters (plugin unload).
void clearBalloonWorlds() => _worlds.clear();
