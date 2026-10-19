// Shared host-side state of the fluids module: the live fluids config, the block
// entity store, the item fluid rules, the filling/emptying recipes of the
// processing module and the per-world [HostFluidWorld]. Block entities find it
// through [FluidsRuntime.instance]; it is created in the module's `onLoad`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart' show CreateAdvancements;
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/worlds.dart';
import 'fluid_host.dart';
import 'fluid_world.dart';
import 'generic_item_fluid.dart';

final class FluidsRuntime {
  static FluidsRuntime? _instance;

  /// The runtime; available after the module's `onLoad`.
  static FluidsRuntime get instance =>
      _instance ?? (throw StateError('The fluids module is not loaded'));

  static bool get isLoaded => _instance != null;

  final FluidsConfig config;
  final BlockEntityStore store;
  final Worlds worlds;
  final Logger log;

  /// The item fluid rules (`FluidRegistries.fromBucket` / `bucketFor`).
  ItemFluidRules rules;

  /// The filling / emptying recipes of the processing module; none when it is not loaded.
  FluidItemRecipes recipes;

  /// The advancement service of the content module, when it is loaded.
  CreateAdvancements? advancements;

  /// Resolves the server for the advancement awards; may return `null` when it is gone.
  Server? Function()? serverProvider;

  /// The random of the module (`Level.getRandom()` for the fluid effects).
  final math.Random random = math.Random();

  final Map<String, HostFluidWorld> _levels = {};

  FluidsRuntime({
    required this.config,
    required this.store,
    required this.worlds,
    required this.log,
    ItemFluidRules? rules,
    FluidItemRecipes? recipes,
    this.advancements,
    this.serverProvider,
  }) : rules = rules ?? ItemFluidRules(),
       recipes = recipes ?? const NoFluidItemRecipes() {
    _instance = this;
  }

  /// The [FluidWorld] of [worldId], `null` while the world is not loaded.
  HostFluidWorld? levelOf(String worldId) {
    final cached = _levels[worldId];
    if (cached != null) return cached;
    final world = worlds.byId(worldId);
    if (world == null) return null;
    return _levels[worldId] = HostFluidWorld(
      world,
      worldId,
      store,
      config,
      onAward: (pos, advancement) => award(worldId, pos, advancement),
      serverProvider: () => serverProvider?.call(),
    );
  }

  /// Forgets the level of a world (world unload).
  void forgetWorld(String worldId) => _levels.remove(worldId);

  /// `AdvancementBehaviour.tryAward(level, pos, advancement)`: awards the
  /// advancement to the players within ten blocks.
  void award(String worldId, Pos pos, String advancement) {
    final adv = advancements;
    final server = serverProvider?.call();
    final world = worlds.byId(worldId);
    if (adv == null || server == null || world == null) return;
    final min = (pos.x - 10.0, pos.y - 10.0, pos.z - 10.0);
    final max = (pos.x + 11.0, pos.y + 11.0, pos.z + 11.0);
    final players = world.getEntitiesInBox(
      min: min,
      max: max,
      filter: const EntityFilterPlayers(),
    );
    for (final snapshot in players) {
      final player = server.getPlayerByUuid(id: snapshot.uuid);
      if (player == null) continue;
      unawaited(
        adv.award(player, advancement).catchError((Object e, StackTrace s) {
          log.debug('Could not award $advancement: $e');
          return false;
        }),
      );
    }
  }

  void dispose() {
    _levels.clear();
    if (identical(_instance, this)) _instance = null;
  }
}
