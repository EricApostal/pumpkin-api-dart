// What the content of Simulated needs from the server, as one interface.
//
// In Java every block reads a `Level` and a `ServerLevel` directly. The port
// keeps the content free of the host API so the tests can run it, and asks this
// interface instead. The plugin installs one implementation
// (`host/pumpkin_host.dart`).
//
// Pure: no host imports.
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart';

import '../util/assembly/sim_assembly_contraption.dart';
import '../util/sim_assembly_helper.dart';

/// The host of Simulated.
abstract interface class SimulatedHost {
  /// The installed host, or `null` before the plugin loaded.
  static SimulatedHost? instance;

  /// The sable level of a world, or `null` when it is not loaded.
  ///
  /// [worldId] may be a world id (`World.getId()`, the folder name `world`) or a dimension key
  /// (`World.getDimension()`, `minecraft:overworld`); the host resolves both through its world
  /// table. The level itself is keyed by its dimension (`SableLevel.dimensionId`).
  SableLevel? levelOf(String worldId);

  /// The world of [worldId] as the assembly sees it.
  SimAssemblyWorld? assemblyWorldOf(String worldId);

  /// The entities of [worldId] as the disassembly sees them.
  SimAssemblyEntities entitiesOf(String worldId) => const NoSimAssemblyEntities();

  /// The sub-level containing the block at [pos], or `null`.
  SubLevel? containingSubLevel(String worldId, Pos pos);

  /// The sub-level with [uniqueId] in [worldId], or `null`.
  SubLevel? subLevelById(String worldId, String uniqueId);

  /// Plays a sound event at [pos].
  void playSound(String worldId, Pos pos, String soundKey, {double volume = 1, double pitch = 1});

  /// Spawns block break particles at [pos] for [blockKey].
  void blockBreakParticles(String worldId, Pos pos, String blockKey) {}

  /// The redstone signal the strongest neighbour of [pos] emits.
  int bestNeighbourSignal(String worldId, Pos pos);

  /// Whether the chunk of [pos] is loaded.
  bool isLoaded(String worldId, Pos pos);

  /// The block state key at [pos].
  String blockKeyAt(String worldId, Pos pos);

  /// Writes a block state key at [pos] and notifies the neighbours.
  void setBlock(String worldId, Pos pos, String blockKey);

  /// Removes the block at [pos] with drops.
  void destroyBlock(String worldId, Pos pos, {bool drop = true});

  /// The block entity of the plugin at [pos], if it is a `T`.
  T? blockEntityAt<T>(String worldId, Pos pos);

  /// The type key of the block entity at [pos] (`CreateBlockEntity.typeKey`),
  /// or `null` when there is none.
  ///
  /// The CC compat keys its registry by type, as Java's capability
  /// registration does.
  String? blockEntityTypeAt(String worldId, Pos pos) => null;

  /// Sends a status message to the player [playerId] (a clientbound payload).
  void sendStatusMessage(String playerId, String translationKey, List<Object?> args) {}

  /// The current game time of [worldId], in ticks.
  int gameTime(String worldId);
}

/// A host that does nothing: no level, no blocks, no entities.
final class NoSimulatedHost implements SimulatedHost {
  const NoSimulatedHost();

  @override
  SableLevel? levelOf(String worldId) => null;

  @override
  SimAssemblyWorld? assemblyWorldOf(String worldId) => null;

  @override
  SubLevel? containingSubLevel(String worldId, Pos pos) => null;

  @override
  SubLevel? subLevelById(String worldId, String uniqueId) => null;

  @override
  SimAssemblyEntities entitiesOf(String worldId) => const NoSimAssemblyEntities();

  @override
  void playSound(String worldId, Pos pos, String soundKey, {double volume = 1, double pitch = 1}) {}

  @override
  void blockBreakParticles(String worldId, Pos pos, String blockKey) {}

  @override
  void sendStatusMessage(String playerId, String translationKey, List<Object?> args) {}

  @override
  int bestNeighbourSignal(String worldId, Pos pos) => 0;

  @override
  bool isLoaded(String worldId, Pos pos) => false;

  @override
  String blockKeyAt(String worldId, Pos pos) => 'minecraft:air';

  @override
  void setBlock(String worldId, Pos pos, String blockKey) {}

  @override
  void destroyBlock(String worldId, Pos pos, {bool drop = true}) {}

  @override
  T? blockEntityAt<T>(String worldId, Pos pos) => null;

  @override
  String? blockEntityTypeAt(String worldId, Pos pos) => null;

  @override
  int gameTime(String worldId) => 0;
}

/// The installed host, or [NoSimulatedHost].
SimulatedHost get simulatedHost => SimulatedHost.instance ?? const NoSimulatedHost();
