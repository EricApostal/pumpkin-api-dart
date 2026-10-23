// The Pumpkin plugin of Sable: declares the mod and the payload channels its
// `VeilPacketManager` registers, through Create's generic addon hook, and owns
// the per-level sub-level containers.
//
// Sable's content (sub-levels, physics, storage) is registered by the modules of
// `package:sable`; this plugin is the component that announces them to the
// NeoForge handshake. The host merges this declaration with Create's and with
// every other plugin's into the one `neoforge:register` answer, so a client with
// Sable installed negotiates instead of being refused.
//
// The container wire-up is the half the model cannot do itself: Java attaches a
// `ServerSubLevelContainer` to the `ServerLevel` from a level-load mixin, so
// `SubLevelContainer.getContainer(level)` always finds one. Here the plugin
// creates one per loaded level on load (and on `worldLoad`), opens the level's
// `sublevels` folder as its storage, registers it, fires
// `SableSubLevelContainerReadyEvent` and ticks it; on `worldUnload` (and on
// plugin unload) it closes and unregisters it. Without this every
// `SubLevelContainer.of(level)` returns `null` and assembly throws "Level
// <dimension> has no sub-level container".
//
// Host: this file uses `pumpkin_api`; create's block helpers are imported from
// `src/` deliberately (they are not in its public barrel yet).
// ignore_for_file: implementation_imports
//
// Java: `dev.ryanhcode.sable.Sable`
import 'dart:async';
import 'dart:convert';

import 'package:create/create.dart' show CreateAddon, CreateRegistry, DeclaredPayload, createAddonNeoForgeDeclaration;
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show stateIdOf;
import 'package:create/src/common/host_bridge.dart' show BlockStates;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../sable_channels.dart';
import '../../sable_native.dart' show JoltPhysicsPipeline, createJoltPipeline;
import '../../sable_commands.dart' show sableCommandPermission, registerSableCommands;
import '../config/sable_synced_config.dart';
import '../sublevel/api/command/sable_command_state.dart';
import '../sublevel/api/event/sable_sub_level_container_ready_event.dart';
import '../sublevel/api/physics_pipeline.dart' show PhysicsPipeline;
import '../sublevel/api/physics_pipeline_provider.dart';
import '../sublevel/api/sub_level_observer.dart';
import '../sublevel/config/sable_config.dart';
import '../sublevel/host/sub_level_host.dart' show SableLevel;
import '../sublevel/model/server_sub_level.dart';
import '../sublevel/model/server_sub_level_container.dart';
import '../sublevel/model/server_level_plot.dart';
import '../sublevel/model/sub_level.dart';
import '../sublevel/model/sub_level_container.dart';
import '../sublevel/physics/impl/none/static_physics_pipeline.dart';
import '../sublevel/storage/region/nbt_sub_level_codec.dart';
import '../sublevel/storage/serialization/sub_level_storage.dart';
import '../sublevel/storage/sub_level_removal_reason.dart';
import '../sublevel/storage/sub_level_saved_data.dart';
import '../sublevel/storage/sub_level_saved_data_files.dart';
import '../data/datapack.g.dart' show sableDatapackBlobs;
import '../data/sable_data.dart';
import '../sublevel/math/vector.dart' show Vector3d;
import '../sublevel/model/mass_tracker.dart';
import '../sublevel/physics/dimension_physics.dart';
import '../sublevel/physics/floating_block_material.dart';
import '../sublevel/physics/physics_block_properties.dart';
import '../sublevel/system/physics_system.dart';
import '../sublevel/system/sable_server_config.dart';
import '../sublevel/system/tracking_system.dart';
import 'pumpkin_level.dart';
import 'pumpkin_sub_level_host.dart' show PumpkinSubLevelHost;
import 'pumpkin_tracking_sender.dart';
import 'jolt_collision.dart' show installJoltCollision;
import 'sable_jolt_diagnostics.dart' show registerJoltDiagnostics;
import 'sable_sub_level_api.dart';

/// Sable as an addon of Create's declaration model.
final class SableAddon extends CreateAddon {
  const SableAddon();

  @override
  String get modId => 'sable';

  @override
  String get version => '0.1.0';

  @override
  String get displayName => 'Sable';

  @override
  Iterable<DeclaredPayload> get channels => sableChannels;
}

/// The Jolt solver as a registered pipeline provider (the Java
/// `RapierPhysicsPipelineProvider`, with its package a hard dependency instead of
/// a classpath entry).
///
/// It carries the default priority (`1000`), so
/// `PhysicsPipelineProviders.resolve()` picks it over the `900` no-op fallback
/// that keeps a level with no solver static.
final class JoltPhysicsPipelineProvider implements PhysicsPipelineProvider {
  const JoltPhysicsPipelineProvider();

  /// The Java default, so this provider wins over the `900` no-op fallback.
  @override
  int get loadPriority => 1000;

  @override
  PhysicsPipeline createPipeline(SableLevel level) => createJoltPipeline();
}

/// One loaded level and everything the plugin owns for it.
final class _LoadedLevel {
  _LoadedLevel(this.level, this.chunks, this.container, this.storage, this.host);

  final PumpkinSableLevel level;
  final PumpkinPlotChunkHost chunks;
  final ServerSubLevelContainer container;
  final SubLevelStorage storage;

  /// The model's host bridge of this level (saved data, players, sub-level
  /// lookup), installed as `container.hostOrNull`.
  final PumpkinSubLevelHost host;

  /// The physics system of the level (attached before the container is
  /// registered, so the first allocated sub-level gets its mass tracker).
  SubLevelPhysicsSystem? physics;

  /// The tracking system of the level.
  SubLevelTrackingSystem? tracking;

  /// The live sender of the tracking system (payloads and chunks).
  PumpkinTrackingSender? sender;

  /// Set when the container tick threw: the container is left alone instead of
  /// failing on every tick of the server.
  bool tickFailed = false;
}

/// The plugin of Sable: the whole server half, in one component.
///
/// **Ownership.** This plugin owns the sub-level containers *and* the physics
/// pipeline they run on, because they cannot live apart: a `PhysicsPipeline` is
/// a Dart object with no cross-component identity, so a container in one wasm
/// component and a solver in another cannot be connected. Sable used to be split
/// across two plugins (`sable` declared the mod, a `sable_jolt` plugin owned the levels)
/// with an ownership probe deciding between them; load order is not fixed, so
/// the deciding was itself a bug (two containers for one world). The solver now
/// lives in this package (`src/physics/jolt/`) and the plugin links it, so
/// there is nothing to discover: this component declares the mod *and* runs the
/// levels.
///
/// Everything a caller outside this component needs is reachable through the
/// operation channel (`sable_sub_level_api.dart`); this plugin is the only one
/// that touches the containers, and commands and physics queries go through the
/// same surface. See "Cross-plugin ownership" in `docs/sable-core-port.md`.
final class SablePlugin extends Plugin {
  SablePlugin();

  /// Whether the server half has started in this instance.
  bool _started = false;

  /// The pipeline the `/sablejolt` diagnostics report on and step bodies with.
  ///
  /// One per level is created by `_start` (see `_openLevel`); this second
  /// instance exists so the diagnostic commands can read the engine (ABI
  /// version, collider registry) without a level, and so `/sablejolt drop` can
  /// step its own body. The module's collider registry is process-wide
  /// (`JoltPhysicsPipeline._colliders`), so the count it reports is the live
  /// one.
  late final JoltPhysicsPipeline diagnostics = createJoltPipeline();

  /// The server settings (`SableConfig`); the plugin reads them with the Java
  /// defaults, since the port has no loader config file yet.
  final SableConfig config = SableConfig();

  /// The server-only settings (`SableServerConfig`), read by the physics system.
  final SableServerConfig serverConfig = SableServerConfig();

  final Map<String, _LoadedLevel> _levels = {};

  /// The mod's data pack (`data/sable/**`).
  final SableData _data = SableData();

  /// The operations other plugin components call (see `sable_sub_level_api.dart`).
  late final SableSubLevelApi _api = SableSubLevelApi(_containerFor, log: logger);

  @override
  PluginInfo get info => const PluginInfo(
    name: 'sable',
    version: '0.1.0',
    description: 'Server side of Sable for Pumpkin: sub-levels, their plots and their physics.',
    permissions: [Permissions.neoforge, Permissions.fsWriteData],
  );

  @override
  Future<void> onLoad(Context context) async {
    // The mod's SYNCED server config goes with the declaration: a NeoForge client
    // with Sable parses it into the mod's `ModConfigSpec`, and its values are read
    // on the client as well (`PhysicsConfigData.updateFromConfig`). The Java
    // server sends it with the handshake, so a client that never received it
    // would throw "Cannot get config value before config is loaded" where the
    // Java arm works.
    final registry = CreateRegistry();
    registry.neoForgeConfigFile(
      sableSyncedConfigFile,
      utf8.encode(sableSyncedToml(SableServerConfig())),
    );
    context.declareNeoForge(createAddonNeoForgeDeclaration(const SableAddon(), registry: registry));
    logger.info('Sable declared ${sableChannels.length} payload channels.');

    // One component, one owner: the containers and the solver they run on are
    // both in this wasm module (see the class comment), so there is nothing to
    // negotiate with another plugin and no load-order window to lose.
    await _start(context);
  }

  /// Starts the server half: the containers, the commands, the operation channel
  /// and the Jolt diagnostics.
  Future<void> _start(Context context) async {
    if (_started) return;
    _started = true;

    // Java's loader finds the physics providers on the classpath (`ServiceLoader`);
    // a plugin component has no classpath, so the providers register themselves
    // here: the Jolt solver this component links (the Java default priority
    // `1000`) and the no-op fallback (`StaticPhysicsPipelineProvider`, priority
    // `900`). Without a registered provider `PhysicsPipelineProviders.resolve()`
    // throws and a level would have no physics system at all -- which is what a
    // sub-level assembled without a mass tracker came from.
    PhysicsPipelineProviders.register(const JoltPhysicsPipelineProvider());
    PhysicsPipelineProviders.register(const StaticPhysicsPipelineProvider());

    // The Jolt module's reactor start (`_initialize`) and the diagnostic world.
    // The ADR requires that no module call happens before the Dart program is
    // instantiated, so this is done here and not in a top-level initializer.
    diagnostics.init(Vector3d(0.0, -9.81, 0.0), 0.0);
    logger.info(
      'Jolt module: ABI ${diagnostics.moduleAbiVersion}, version id '
      '${diagnostics.moduleVersion}.',
    );
    registerJoltDiagnostics(context, logger, pipeline: diagnostics, containerOf: _containerFor);

    // The mod's data pack (`data/sable/**`: the block tags, the 19
    // `physics_block_properties` and the floating materials). Written next to this plugin's data
    // folder; enabled in the host at `serverLoad`, when the pack manager exists.
    _data.onLoad(context, logger);
    context.listen(Events.serverLoad, (server, event) async {
      if (event.loadType != ServerLoadType.startup) return;
      await _data.onServerLoaded(server, logger);
    });

    // The block properties of Sable's datapack (`data/sable/physics_block_properties/**`):
    // the mass, inertia, volume, friction and floating-material values every
    // block gets. Java loads them through its resource-reload listener; this
    // component cannot read datapack files, so it reads the embedded copy
    // (`sableDatapackBlobs`) — the same bytes the pack writes — and installs the
    // table the mass tracker and the pipeline read.
    _installBlockProperties(logger);

    // Other components cannot see this one's containers (a static map is per
    // wasm instance), so they ask over IPC instead. See the class comment in
    // `sable_sub_level_api.dart`.
    _api.install();

    // The host loads plugins on the first tick, after every world is loaded and
    // `worldLoad` has already fired, so the subscription below only sees worlds
    // created later. The worlds that exist now are opened here.
    _openLoadedWorlds(context);

    // `/sable`: the model's command tree, over the level resolver below. Without
    // it the whole tree exists but nothing registers it.
    context.command(
      'sable',
      description: 'Sable sub-level management',
      permission: sableCommandPermission(),
      (c) => registerSableCommands(c, SableCommandState(levelOf: _levelOf)),
    );

    // The sender queues per player, and a handle a send holds belongs to the
    // plugin; a player that left has no handle left to dispose and a queue
    // that must not grow. Every level's queue is dropped so a reconnect starts
    // clean (the rejoining player gets a fresh full sync from the tracking
    // system instead of a stale chain).
    context.listen(Events.playerLeave, (server, event) {
      final uuid = event.player.getId().asString;
      for (final loaded in _levels.values) {
        loaded.sender?.forgetPlayer(uuid);
        loaded.tracking?.forgetPlayer(uuid);
      }
    });

    context.listen(Events.worldLoad, (server, event) {
      _openLevel(context, event.targetWorld.keep());
    });
    context.listen(Events.worldUnload, (server, event) {
      if (event.cancelled) return;
      _closeLevel(event.targetWorld.getDimension());
    });
    // `ServerLevelMixin.java:77-86`: `SubLevelHoldingChunkMap.saveAll` runs on
    // the level save, before the level data is written. Without this the region
    // files (the holding chunks' pointers) are never written and a restart
    // loses everything that was not loaded.
    context.listen(Events.worldSave, (server, event) {
      final named = _levelForWorldName(event.worldName);
      if (named != null) {
        _saveLevel(named);
        return;
      }
      // The event carries the host's `Debug` of the dimension, which the port
      // cannot match for sure; a save that cannot be attributed must not lose
      // another level's data, so everything is saved.
      logger.info(
        'Sable: a world save for "${event.worldName}" did not match a loaded level; '
        'saving every open level.',
      );
      for (final loaded in _levels.values.toList()) {
        _saveLevel(loaded);
      }
    });
    // `ChunkMapMixin.java:56-58`: the chunk map demotes a sub-level to its
    // holding chunk when the chunk under it unloads and restores it when the
    // chunk loads. The host's chunk-unload event carries no world (and
    // `World::unload_chunk` has no caller in the host), so only the load half is
    // wired; `PhysicsChunkTicketManager` drives the unload half.
    context.listen(Events.chunkLoad, (server, event) {
      final loaded = _levels[event.targetWorld.getDimension()];
      loaded?.container.holdingChunkMapOrNull?.updateChunkStatus(event.chunkX, event.chunkZ, true);
    });
context.listen(Events.worldTick, (server, event) async {
      final loaded = _levels[event.targetWorld.getDimension()];
      if (loaded == null || loaded.tickFailed) return;
      try {
        final watch = Stopwatch()..start();
        loaded.container.tick();
        // A plot chunk the host has not generated yet is sent on the tick it
        // arrives (the sync that announced the sub-level cannot wait for it
        // without holding the server's tick open; see the sender).
        loaded.sender?.flushQueuedChunks();
        // A container tick that takes a second is not normal: the model is
        // arithmetic plus a few host calls, so a slow one is the *sync* (a
        // payload send or a plot chunk's mirror) or an assembly, and either is
        // worth naming rather than reading as "the server is overloaded".
        final elapsed = watch.elapsedMilliseconds;
        if (elapsed > 250) {
          logger.warn(
            'Sable: the sub-level container tick of ${loaded.level.dimensionId} took ${elapsed}ms '
            '(sender: ${loaded.sender})',
          );
        }
      } on Object catch (error, stack) {
        loaded.tickFailed = true;
        logger.error(
          'Sable: ticking the sub-level container of ${loaded.level.dimensionId} failed; '
          'the container is left un-ticked: $error\n$stack',
        );
        return;
      }
      // `SavedDataStorage` writes the dirty saved data at the end of the tick.
      try {
        loaded.host.flushSavedData();
      } on Object catch (error, stack) {
        logger.error('Sable: flushing the saved data of ${loaded.level.dimensionId} failed: $error\n$stack');
      }
    });
  }

  /// The tickets saved data, with the pointer of a loaded sub-level preferred
  /// over the one stored with the ticket (it may have moved since).
  ///
  /// A ticket without a pointer is a ticket that cannot be loaded back on the
  /// next start (`SubLevelHoldingChunkMap.snatchAndLoad` needs one), so the
  /// count that is written is logged: losing force-loaded sub-levels across a
  /// restart is otherwise silent.
  Map<String, Object?> _ticketsTag(ServerSubLevelContainer container) {
    final tickets = container.getAllTickets();
    var withPointer = 0;
    final tag = TicketsSavedData.save(
      tickets,
      pointerOf: (uuid) {
        final subLevel = container.getSubLevelById(uuid);
        final pointer = subLevel is ServerSubLevel ? subLevel.getLastSerializationPointer() : null;
        if (pointer != null) withPointer++;
        return pointer;
      },
    );
    if (tickets.isNotEmpty) {
      logger.info(
        'Sable: saving ${tickets.length} force-load ticket(s) in '
        '${container.level.dimensionId}, $withPointer with a save pointer.',
      );
    }
    return tag;
  }

  /// Saves one level the way the Java save hook does: every holding chunk and
  /// sub-level payload, then the saved data.
  void _saveLevel(_LoadedLevel loaded) {
    try {
      loaded.container.holdingChunkMapOrNull?.saveAll();
    } on Object catch (error, stack) {
      logger.error('Sable: saving the sub-levels of ${loaded.level.dimensionId} failed: $error\n$stack');
      return;
    }
    loaded.host.flushSavedData();
    logger.info('Sable: saved the sub-levels of ${loaded.level.dimensionId}.');
  }

  /// The loaded level a `worldSave` event is about.
  ///
  /// The host sends `format!("{:?}", dimension)`, the whole `Dimension` struct,
  /// so the dimension key and the world id are matched as substrings.
  _LoadedLevel? _levelForWorldName(String worldName) {
    final direct = _levels[worldName];
    if (direct != null) return direct;
    for (final loaded in _levels.values) {
      if (worldName.contains(loaded.level.dimensionId)) return loaded;
    }
    for (final loaded in _levels.values) {
      if (worldName.contains(loaded.level.world.getId())) return loaded;
    }
    return null;
  }

  /// The tag of a saved-data name the container owns (the Java codecs).
  Map<String, Object?>? _savedDataTag(SubLevelContainer container, String name) {
    if (container is! ServerSubLevelContainer) return null;
    return switch (name) {
      occupancySavedDataName => OccupancySavedData.save(container.getOccupancy()),
      // Java prefers the pointer of a loaded sub-level over the one stored with
      // the ticket, since the sub-level may have moved since the last save.
      ticketsSavedDataName => _ticketsTag(container),
      _ => null,
    };
  }

  @override
  void onUnload(Context context) {
    _stop();
    diagnostics.dispose();
  }

  /// Closes every level and forgets the containers.
  void _stop() {
    for (final dimension in _levels.keys.toList()) {
      _closeLevel(dimension);
    }
    SubLevelContainer.clearAll();
    _started = false;
  }

  /// The model's view of the world a command runs in (`SableCommandState`).
  ///
  /// The host hands a command a `World`; the model keys everything by the
  /// dimension key, so that is what is looked up.
  SableLevel _levelOf(Object? world) {
    final dimension = world is World ? world.getDimension() : '$world';
    final loaded = _levels[dimension];
    if (loaded == null) {
      throw StateError('No sub-level container for $dimension (the level is not loaded).');
    }
    return loaded.level;
  }

  /// The block-property table of this component, once [installBlockProperties]
  /// has run.
  static PhysicsBlockPropertiesTable? blockProperties;

  /// Loads `physics_block_properties/**` and `floating_materials/**` from the
  /// embedded pack and points the model's block hooks at it.
  ///
  /// This is what makes a stone block weigh Sable's 2.0 kg rather than the
  /// model's 1.0: `normal.json` sets `sable:mass` 1.0 with a `type=double`
  /// override of 2.0, and the override only applies once the state is resolved
  /// through the table.
  ///
  /// The floating materials are loaded here too. Java fills them with a second
  /// reload listener (`FloatingBlockMaterialDataHandler.ReloadListener`) over
  /// the same pack; without them a block whose `sable:floating_material` names
  /// one resolves to `null` and simply does not float, so `sable:end_stone`
  /// (lift 2) would sit exactly like a normal block.
  void _installBlockProperties(Logger log) {
    final table = PhysicsBlockPropertiesTable();
    var loaded = 0;
    var materials = 0;

    for (final blob in sableDatapackBlobs) {
      for (final file in blob.unpack()) {
        if (!file.path.endsWith('.json')) continue;
        final isProperty = file.path.contains('physics_block_properties/');
        final isMaterial = file.path.contains('floating_materials/');
        if (!isProperty && !isMaterial) continue;
        try {
          final json = jsonDecode(utf8.decode(file.bytes));
          if (json is! Map) continue;
          if (isProperty) {
            final definition = PhysicsBlockPropertiesDefinition.tryFromJson(json);
            if (definition == null) continue;
            table.addDefinition(definition);
            loaded++;
          } else {
            final id = _registryIdOf(file.path, 'floating_materials');
            if (id == null) continue;
            // `FloatingBlockMaterialDataHandler.addMaterial(entry.getKey(), entry.getValue())`.
            FloatingBlockMaterialDataHandler.addMaterial(id, FloatingBlockMaterial.fromJson(json));
            materials++;
          }
        } on Object catch (error) {
          log.warn('Sable: skipping ${file.path}: $error');
        }
      }
    }

    // `#sable:*` selectors need tag membership. The pack that defines them is
    // not necessarily enabled in the host (`<world>/datapacks/sable` is a manual
    // link), so the membership is resolved from the same embedded blobs the
    // definitions came from, with the host consulted for a tag the pack does not
    // define (`#c:stones` and the other conventional tags come from the host).
    final tags = _readBlockTags();
    table.blockInTag = (blockId, tagId) => _blockInTag(tags, blockId, tagId, <String>{});

    blockProperties = table;
    // `PhysicsBlockPropertyHelper` is a global registry in Java; here the model
    // reads this component's table through it, so a sub-level created in this
    // component does not depend on the per-level field being set. Installing it
    // also applies the definitions another component pushed before this read.
    PhysicsBlockPropertyHelper.install(table);
    MassTracker.blockMass = (subLevel, state) => table.resolveStateString(state).mass;
    MassTracker.blockInertia = (subLevel, state) => table.resolveStateString(state).inertia;
    MassTracker.isSolid = (subLevel, state) => !BState(state).isAir;
    // `SubLevelPhysicsSystem.java:168-170` reads the dimension's gravity and
    // universal drag from `DimensionPhysicsData`, which the port has as a static
    // lookup over the level's `SableLevel`.
    SubLevelPhysicsSystem.dimensionGravity = (level, dest) {
      if (level is SableLevel) {
        DimensionPhysicsData.getGravity(level, dest);
      } else {
        dest.set(0.0, -11.0, 0.0);
      }
    };
    SubLevelPhysicsSystem.dimensionDrag = (level) =>
        level is SableLevel ? DimensionPhysicsData.getUniversalDrag(level) : 0.09;

    log.info(
      'Sable: $loaded physics block propert${loaded == 1 ? 'y' : 'ies'} and '
      '$materials floating material${materials == 1 ? '' : 's'} loaded from the '
      'embedded pack.',
    );
  }

  /// `data/<namespace>/<directory>/<path>.json` → `<namespace>:<path>`.
  ///
  /// The datapack registry id of one embedded file (`FileToIdConverter.json(dir)`
  /// builds the same id from the resource path).
  static String? _registryIdOf(String path, String directory) {
    final match = RegExp('data/([^/]+)/$directory/(.+)\\.json\$').firstMatch(path);
    return match == null ? null : '${match.group(1)}:${match.group(2)}';
  }

  /// The pack's block tags, by id (`sable:heavy` → its entries).
  static Map<String, List<Object?>> _readBlockTags() {
    final tags = <String, List<Object?>>{};
    for (final blob in sableDatapackBlobs) {
      for (final file in blob.unpack()) {
        // `data/<namespace>/tags/block/<path>.json`
        final match = RegExp(r'data/([^/]+)/tags/block/(.+)\.json$').firstMatch(file.path);
        if (match == null) continue;
        try {
          final json = jsonDecode(utf8.decode(file.bytes));
          if (json is! Map) continue;
          final values = json['values'];
          if (values is! List) continue;
          tags['${match.group(1)}:${match.group(2)}'] = values;
        } on Object {
          // A tag this component cannot read is a tag it cannot use; the host
          // lookup below still answers for it.
        }
      }
    }
    return tags;
  }

  /// Whether [blockId] is in [tagId], resolving nested tags.
  ///
  /// [seen] breaks a tag cycle (a datapack may not have one, but a hand-written
  /// pack can).
  static bool _blockInTag(
    Map<String, List<Object?>> tags,
    String blockId,
    String tagId,
    Set<String> seen,
  ) {
    if (!seen.add(tagId)) return false;

    final entries = tags[tagId];
    if (entries == null) {
      // Not in the pack: the host may know it (`#c:stones`, a vanilla tag).
      final stateId = stateIdOf(BState(blockId));
      return stateId != null && BlockStates.isTag(stateId, tagId);
    }

    for (final entry in entries) {
      // An entry is a block id, `#tag`, or `{"id": ..., "required": false}`.
      final value = entry is Map ? entry['id'] : entry;
      if (value is! String) continue;
      if (value.startsWith('#')) {
        if (_blockInTag(tags, blockId, value.substring(1), seen)) return true;
      } else if (value == blockId) {
        return true;
      }
    }
    return false;
  }

  /// The container named by [world]: a dimension key (`minecraft:overworld`) or
  /// a world id (`world`), as the IPC callers may hold either.
  SubLevelContainer? _containerFor(String world) {
    final direct = _levels[world];
    if (direct != null) return direct.container;
    for (final loaded in _levels.values) {
      if (loaded.level.world.getId() == world) return loaded.container;
    }
    return null;
  }

  /// Opens a container for every world the server already has.
  void _openLoadedWorlds(Context context) {
    final server = context.getServer();
    try {
      for (final world in server.getAllWorlds()) {
        _openLevel(context, world.keep());
      }
    } finally {
      server.dispose();
    }
  }

  /// Creates, initializes and registers the container of [world].
  void _openLevel(Context context, World world) {
    final dimension = world.getDimension();
    // The host loads the plugins after every world is already loaded, then fires
    // `worldLoad` for them again on subscribe: opening the same dimension twice
    // would close the first container — and its registration — while the second
    // one is what survives. Keep the first: it is the one that saw the world.
    if (_levels.containsKey(dimension)) {
      world.dispose();
      logger.info('Sable: the sub-level container of $dimension is already open; '
          'ignoring a duplicate level open.');
      return;
    }

    final level = PumpkinSableLevel(world);
    final chunks = PumpkinPlotChunkHost(level);

    // The geometry is the Java static (`SubLevelContainer.DEFAULT_LOG_SIZE_LENGTH`,
    // `DEFAULT_LOG_PLOT_SIZE`, `DEFAULT_ORIGIN`): the Sable config has no keys
    // for it, so these are read from the model's constants (7, 7 and 10000).
    final container = ServerSubLevelContainer(
      level,
      chunks,
      SubLevelContainer.defaultLogSizeLength,
      SubLevelContainer.defaultLogPlotSize,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
      config: config,
    );
    chunks.container = container;

    // One folder per dimension, named after the **dimension id**.
    //
    // `World.getId()` is the same folder name (`world`) for every dimension in
    // Pumpkin, so keying the storage by it made all three dimensions share one
    // store: the nether's and the end's empty save wrote `{tickets: []}` over the
    // overworld's saved data, and their region files would have collided too.
    // Java roots one shared `<world>/sublevels` for the whole server (a quirk of
    // the mod); the plugin's sandbox has no world path, so the port keeps the
    // per-dimension split that the containers already assume.
    final folder = 'sublevels/${dimension.replaceAll(':', '_')}';
    final store = PumpkinFileStore(context.files);
    store.createDirectory(folder);

    // The payload codec is Sable's own: gzip NBT, the only format the Java mod
    // can read back (`SubLevelStorageFile.COMPRESS_DATA` + `NbtIo`). The JSON
    // codec is for tests; a world saved with it is not what Java reads.
    final storage = SubLevelStorage(store, folder, NbtSubLevelCodec())
      ..pruneEmptyFiles = SableServerConfig().subLevelStoragePruning;

    // A payload that does not decode must be loud. Java logs at error level and
    // keeps going; without a sink the storage throws instead, which is what
    // stops a codec mismatch from looking like "this world has no sub-levels".
    storage.onError = (message, error, stack) {
      logger.error('Sable: $message: $error\n$stack');
    };

    // `ServerLevelPlot.load` must not drop a chunk it cannot address.
    ServerLevelPlot.onChunkKeyError = (key) {
      logger.error('Sable: a saved plot has an unreadable chunk key "$key"; that chunk is skipped.');
    };

    // The plot-chunk bridge's cost, per phase and per chunk: the mirror runs
    // inside the tick that first sends a plot chunk, so when a client stalls
    // while a sub-level appears, this says which phase paid for it.
    PumpkinPlotChunkHost.onMirrorEvent = (message) => logger.info('Sable: $message');

    // The saved data of the level (`SubLevelOccupancySavedData`,
    // `SubLevelTicketsSavedData`, the tracking points). The plugin API has no
    // `SavedDataStorage`, so these are gzip NBT files next to the storage files.
    final savedData = SavedDataFiles(
      store: store,
      folder: '$folder/data',
      codec: NbtSubLevelCodec(),
    );
    final host = PumpkinSubLevelHost(
      context: context,
      level: level,
      chunks: chunks,
      container: container,
      savedData: savedData,
      logger: (message, error) => logger.error('Sable: $message: $error'),
    )
      ..savedDataProvider = (name) => _savedDataTag(container, name);
    container.hostOrNull = host;

    // Warm the plot yard's centre chunk **now**, not when a ship is assembled.
    //
    // The host generates a chunk on demand, and the yard sits ~20 million blocks from spawn, so
    // that generation is worldgen from nothing: measured at 3 s in one run and 72 s in another.
    // A sub-level can only be sent once the chunk exists (`send-chunk-at` serializes the chunk
    // that is *loaded in the world* at that position), so requesting it at assembly time makes
    // the assembled ship invisible for as long as the generation takes -- which is exactly what
    // "it assembles but I can't see it" was. Marking it here pays the same cost while nobody is
    // waiting for it. `forceload` marks the chunk and returns at once; the plugin's own
    // `force-load-chunk` would block the tick loop for 60 s instead.
    final yardChunk = (SubLevelContainer.defaultOrigin << SubLevelContainer.defaultLogPlotSize) +
        (1 << (SubLevelContainer.defaultLogPlotSize - 1));
    unawaited(
      host
          .requestYardChunkKeep(level.dimensionId, yardChunk, yardChunk)
          .catchError((Object error) => logger.warn('Sable: cannot warm the yard chunk: $error')),
    );

    // The plot's world copy is kept loaded through the *server's* `forceload`
    // rather than the plugin's `force-load-chunk`: the latter waits for the
    // chunk to be generated and answers at its 60 s timeout, which blocks the
    // server's tick loop and kills a watching client's keep-alive (measured
    // both with the call awaited and without — the host's subtask has to finish
    // before the guest's tick can return). `forceload` marks the chunk and
    // returns at once; the sender ships the chunk when the world has it.
    PumpkinPlotChunkHost.onYardChunkKeep = host.requestYardChunkKeep;
    PumpkinPlotChunkHost.onYardChunkRelease = host.releaseYardChunkKeep;


    // The physics system is what builds a sub-level's mass tracker
    // (`SubLevelPhysicsSystem.onSubLevelAdded` -> `buildMassTracker` +
    // `pipeline.addSubLevel`), and the tracking system is what syncs a
    // sub-level to the players near it. Java attaches both when the level's
    // container is created; they are attached here, before any sub-level is
    // loaded, so a force-loaded sub-level finds a pipeline and a tracker
    // instead of `null`.
    final loaded = _LoadedLevel(level, chunks, container, storage, host);
    final physics = SubLevelPhysicsSystem(
      container: container,
      // The registry resolves to the Jolt provider this component registers
      // (priority 1000), which is the solver whose module it links.
      pipeline: PhysicsPipelineProviders.createPipeline(level),
      config: config,
      serverConfig: serverConfig,
    )..initialize();
    loaded.physics = physics;
    // The section packer and the collider bakery; without them no section
    // reaches the engine (see `installJoltCollision`).
    installJoltCollision(physics, properties: blockProperties);
    // The sync needs a live implementation, not the model seam: payloads go
    // over the host's `sendCustomPayload` on the payload channel, and the
    // plot's chunks go through `chunk-streaming` after a mirror into the
    // level's world chunk (see `PumpkinPlotChunkHost.mirrorPlotChunk`). The
    // sender is attached to the container *before* the force-load below, so a
    // sub-level that loads back from disk syncs to its tracking players; the
    // tracking tick sends in the Java order (`start_tracking_sub_level`, the
    // chunk sends, `finalize_sub_level`).
    final sender = PumpkinTrackingSender(
      host: host,
      chunks: chunks,
      logger: (message) => logger.info(message),
    );
    loaded.sender = sender;
    loaded.tracking = SubLevelTrackingSystem(
      container: container,
      config: config,
      sink: sender,
      chunkView: sender,
      log: (message) => logger.info('Sable tracking: $message'),
    );

    // Registered before the force-load below: `fullyLoad` builds a sub-level
    // whose plot and helpers resolve the container through
    // `SubLevelContainer.of(level)`, and an unregistered container answers
    // `null` there.
    SubLevelContainer.register(container);
    _levels[dimension] = loaded;

    // Java loads the occupancy and the tickets in the `ServerLevel` constructor
    // (`ServerLevelMixin.java:62-63`), *before* the container is initialized,
    // because `initialize` is what force-loads the ticketed sub-levels from the
    // pointers they carry.
    final ticketsTag = host.readSavedData(ticketsSavedDataName);
    if (ticketsTag != null) {
      final tickets = TicketsSavedData.load(ticketsTag);
      container.loadTickets(tickets);
      final withPointer = tickets.values.where((info) => info.pointer != null).length;
      if (tickets.isNotEmpty) {
        logger.info(
          'Sable: loaded ${tickets.length} force-load ticket(s) for $dimension, '
          '$withPointer with a save pointer.',
        );
      }
    }
    final occupancyTag = host.readSavedData(occupancySavedDataName);
    if (occupancyTag != null) OccupancySavedData.load(occupancyTag, container.getOccupancy());

    // A sub-level that cannot be loaded back is the worst failure this system
    // has: it was on disk, the player expects it, and nothing says it is gone.
    // Java logs and toasts it (`SubLevelHoldingChunkMap.java:570-584`). The sink
    // goes in with the initialization, because the force-load runs inside it.
    container.initializeWithStorage(
      storage,
      onLoadFailure: (message, error) {
        logger.error('Sable: $message${error == null ? '' : ': $error'}');
      },
    );
    // The ticket load is reported here rather than up front, because theft of
    // the folder's contents (another level's close, a world-sandbox reset) is
    // otherwise invisible: `initialize` saw zero, and now everyone agrees why.
    final withPointer = container
        .getAllTickets()
        .values
        .where((info) => info.pointer != null && info.tickets.isNotEmpty)
        .length;
    if (withPointer == 0 && container.getAllTickets().isNotEmpty) {
      logger.error('Sable: ${container.getAllTickets().length} ticket(s) of $dimension '
          'have no usable save pointer (the holding chunks were lost or never written).');
    } else if (withPointer > 0) {
      logger.info('Sable: $withPointer loaded sub-level(s) of $dimension are force-loading '
          'back (${container.getAllTickets().length} ticket(s) total); snatched '
          '${container.snatchLog} from disk.');
    }
    container.addObserver(_Announcer(_api));

    fireSubLevelContainerReady(level, container);
    logger.info(
      'Sable: sub-level container of $dimension ready '
      '(${1 << container.getLogSideLength()}x${1 << container.getLogSideLength()} plots of '
      '${1 << container.getLogPlotSize()} chunks, origin ${container.getOrigin()}, '
      'storage $folder, pipeline ${loaded.physics!.pipeline.runtimeType}).',
    );
  }

  /// Closes and unregisters the container of [dimension].
  void _closeLevel(String dimension) {
    final loaded = _levels.remove(dimension);
    if (loaded == null) return;

    SubLevelContainer.unregister(loaded.level);

    // Shutdown path: the finals are written here as well, so a server that stops
    // without a level save (or an exception during it) still has its sub-levels
    // on disk. `ServerLevel.save` covers the periodic saves.
    _saveLevel(loaded);

    loaded.tracking?.close();
    loaded.sender = null;
    loaded.container.close();
    loaded.storage.close();
    loaded.chunks.clear();
    loaded.host.dispose();
    loaded.level.world.dispose();
    logger.info('Sable: sub-level container of $dimension closed.');
  }
}

/// Tells the IPC subscribers when a sub-level appears or disappears.
///
/// A component that keeps a mirror (it needs synchronous answers from a
/// synchronous callback) refreshes it from these pushes instead of polling.
final class _Announcer with SubLevelObserver {
  _Announcer(this._api);

  final SableSubLevelApi _api;

  @override
  void onSubLevelAdded(SubLevel subLevel) => _api.announce(subLevel.container);

  @override
  void onSubLevelRemoved(SubLevel subLevel, SubLevelRemovalReason reason) =>
      _api.announce(subLevel.container);
}
