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
// Host: this file uses `pumpkin_api`.
//
// Java: `dev.ryanhcode.sable.Sable`
import 'dart:async';
import 'dart:convert';

import 'package:create/create.dart' show CreateAddon, CreateRegistry, DeclaredPayload, createAddonNeoForgeDeclaration;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../sable_channels.dart';
import '../../sable_commands.dart' show sableCommandPermission, registerSableCommands;
import '../config/sable_synced_config.dart';
import '../sublevel/api/command/sable_command_state.dart';
import '../sublevel/api/event/sable_sub_level_container_ready_event.dart';
import '../sublevel/config/sable_config.dart';
import '../sublevel/host/sub_level_host.dart' show SableLevel;
import '../sublevel/model/server_sub_level_container.dart';
import '../sublevel/model/sub_level_container.dart';
import '../sublevel/storage/region/sub_level_storage_file.dart';
import '../sublevel/storage/serialization/sub_level_storage.dart';
import '../sublevel/system/sable_server_config.dart';
import 'pumpkin_level.dart';

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

/// One loaded level and everything the plugin owns for it.
final class _LoadedLevel {
  _LoadedLevel(this.level, this.chunks, this.container, this.storage);

  final PumpkinSableLevel level;
  final PumpkinPlotChunkHost chunks;
  final ServerSubLevelContainer container;
  final SubLevelStorage storage;

  /// Set when the container tick threw: the container is left alone instead of
  /// failing on every tick of the server.
  bool tickFailed = false;
}

/// The plugin of Sable.
final class SablePlugin extends Plugin {
  /// The server settings (`SableConfig`); the plugin reads them with the Java
  /// defaults, since the port has no loader config file yet.
  final SableConfig config = SableConfig();

  final Map<String, _LoadedLevel> _levels = {};

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

    // The host loads plugins on the first tick, after every world is loaded and
    // `worldLoad` has already fired, so the subscription below only sees worlds
    // created later. The worlds that exist now are opened here.
    _openLoadedWorlds(context);

    // `/sable`: the model's command tree, over the level resolver below. Without
    // it the whole tree exists but nothing registers it.
    context.command(
      'sable',
      description: 'Sable sub-level management',
      permission: sableCommandPermission,
      (c) => registerSableCommands(c, SableCommandState(levelOf: _levelOf)),
    );

    context.listen(Events.worldLoad, (server, event) {
      _openLevel(context, event.targetWorld.keep());
    });
    context.listen(Events.worldUnload, (server, event) {
      if (event.cancelled) return;
      _closeLevel(event.targetWorld.getDimension());
    });
    context.listen(Events.worldTick, (server, event) {
      final loaded = _levels[event.targetWorld.getDimension()];
      if (loaded == null || loaded.tickFailed) return;
      try {
        loaded.container.tick();
      } on Object catch (error, stack) {
        loaded.tickFailed = true;
        logger.error(
          'Sable: ticking the sub-level container of ${loaded.level.dimensionId} failed; '
          'the container is left un-ticked: $error\n$stack',
        );
      }
    });
  }

  @override
  void onUnload(Context context) {
    for (final dimension in _levels.keys.toList()) {
      _closeLevel(dimension);
    }
    SubLevelContainer.clearAll();
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
    if (_levels.containsKey(dimension)) {
      world.dispose();
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

    final folder = '${world.getId()}/sublevels';
    final store = PumpkinFileStore(context.files);
    store.createDirectory(folder);
    final storage = SubLevelStorage(store, folder, const JsonSubLevelCodec())
      ..pruneEmptyFiles = SableServerConfig().subLevelStoragePruning;

    container.initializeWithStorage(storage);
    SubLevelContainer.register(container);
    _levels[dimension] = _LoadedLevel(level, chunks, container, storage);

    fireSubLevelContainerReady(level, container);
    logger.info(
      'Sable: sub-level container of $dimension ready '
      '(${1 << container.getLogSideLength()}x${1 << container.getLogSideLength()} plots of '
      '${1 << container.getLogPlotSize()} chunks, origin ${container.getOrigin()}, '
      'storage $folder).',
    );
  }

  /// Closes and unregisters the container of [dimension].
  void _closeLevel(String dimension) {
    final loaded = _levels.remove(dimension);
    if (loaded == null) return;

    SubLevelContainer.unregister(loaded.level);
    loaded.container.close();
    loaded.storage.close();
    loaded.chunks.clear();
    loaded.level.world.dispose();
    logger.info('Sable: sub-level container of $dimension closed.');
  }
}
