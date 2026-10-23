// The Pumpkin plugin: loads the service, installs the command, the network
// side and the optional NeoForge declaration, and drives the computers from the
// server tick.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart' show VanillaRegistries, vanillaBlockStateCount;

import '../protocol/datapack_registries.dart';
import '../protocol/registries.dart';
import 'block_install.dart';
import 'block_states.dart';
import 'cc_neoforge.dart';
import 'commands.dart';
import 'network.dart';
import 'registry_install.dart';
import 'service.dart';
import 'world_computers.dart';
import 'world_monitors.dart';
import 'world_peripherals.dart';
import 'world_turtles.dart';

/// How often the in-game clock is read from the world, in ticks.
const int _timeSyncInterval = 100;

/// The items that stack to 1 (`stacksTo(1)` in `ModRegistry.Items`).
const Set<String> _singleItems = {
  'pocket_computer_normal',
  'pocket_computer_advanced',
  'disk',
  'treasure_disk',
  'printed_page',
  'printed_pages',
  'printed_book',
};

final class CcTweakedPlugin extends Plugin {
  late CcService _service;
  CcWorldComputers? _world;
  CcWorldTurtles? _turtles;
  CcWorldPeripherals? _peripherals;
  CcWorldMonitors? _monitors;
  int _tick = 0;

  @override
  PluginInfo get info => const PluginInfo(
    name: 'cc_tweaked',
    version: '0.1.0',
    description: 'Server side of CC: Tweaked: CraftOS computers on a pure Dart Lua VM.',
    permissions: [
      Permissions.fsWriteData,
      Permissions.registryItems,
      Permissions.registryBlocks,
      Permissions.registryBlockEntities,
      Permissions.registryMenus,
      Permissions.registryComponents,
      Permissions.neoforge,
    ],
  );

  @override
  void onLoad(Context context) {
    _service = CcService.load(context.files);
    final network = CcNetwork()..install(context);
    registerCommands(context, _service, network);
    // The datapack registries of the mod (turtle and pocket upgrades) come from the
    // jar's data pack; the client's creative tab and the turtles' ids need them.
    final datapack = CcDatapackRegistries.load(_service.image.archive);
    for (final note in datapack.notes) {
      logger.warn('CC datapack registries: $note');
    }
    logger.info(
      'Datapack registries: ${datapack.turtleUpgrades.entries.length} turtle upgrades, '
      '${datapack.pocketUpgrades.entries.length} pocket upgrades.',
    );
    _declareNeoForge(context, datapack);
    if (_service.pluginConfig.neoForge) {
      network.canOpenGui = (player) => player.isNeoForge;
    }
    if (_service.pluginConfig.neoForge) {
      // Order matters, and is the order of the registry sync: the items first (a
      // block links to an existing item), then the blocks, then the block entity
      // types, menu types and data component types. Registration closes when
      // players can connect.
      _registerItems();
      final blocks = _registerBlocks();
      _registerRegistries();
      final states = CcBlockStates(blocks);
      final world = CcWorldComputers(_service, network, states)..install(context);
      _world = world;
      _turtles = CcWorldTurtles(_service, network, states, datapack)..install(context);
      // The peripheral blocks (`disk_drive`, `printer`, `speaker`,
      // `redstone_relay`, the cables and wired modems, and a computer or turtle
      // seen by its neighbours) and the monitors.
      _peripherals = CcWorldPeripherals(_service, network, states)..install(context);
      _monitors = CcWorldMonitors(_service, network, states, network.monitor)..install(context);
    }

    context.runRepeating(1, (server) {
      if (_tick++ % _timeSyncInterval == 0) _syncWorldTime(server);
      _service.tick();
      // These ticks wait for the host and skip a tick that comes while one still
      // runs, so they are not awaited here: the rest of the tick goes on.
      unawaited(_world?.tick(server));
      unawaited(_turtles?.tick(server));
      unawaited(_peripherals?.tick(server));
      unawaited(_monitors?.tick(server));
      unawaited(network.tick(server));
    });
    context.onUnload(_service.shutdown);
    logger.info('CC: Tweaked server side loaded.');
  }

  /// Makes the in-game clock of the computers follow the overworld.
  ///
  /// The name is the overworld's dimension key; the host's `getWorldByName` accepts a world id or
  /// a dimension key (`find(|w| w.get_world_name() == name || w.dimension.minecraft_name == name)`),
  /// so this resolves without a world-id lookup.
  void _syncWorldTime(Server server) {
    final world = server.getWorldByName(name: 'minecraft:overworld');
    if (world == null) return;
    try {
      _service.syncWorldTime(world.timeOfDay, world.worldAge);
    } finally {
      world.dispose();
    }
  }

  /// Adds CC: Tweaked's items to the host's item registry, in the order of the
  /// registry sync, so the ids the host gives them are the ones the registry
  /// sync sends (the client adopts them by name, not by re-numbering). They are
  /// plain items (no default components): the block items are linked to their
  /// blocks by [_registerBlocks]; the data components they carry are set on
  /// stacks (`CcComponents`), see docs/host-requirements.md.
  void _registerItems() {
    final registry = ItemRegistries.host;
    final first = registry.vanillaCount;
    for (var i = 0; i < CcRegistries.items.length; i++) {
      final key = CcRegistries.items[i];
      final path = key.substring(key.indexOf(':') + 1);
      try {
        final id = registry.register(
          ItemRegistration(key: key, maxStackSize: _singleItems.contains(path) ? 1 : null),
        );
        // Not `first + i` when another plugin registered items first: the host numbers every
        // plugin's entries in load order. The client takes the id from the snapshot, so this is
        // only worth a debug line.
        if (id != first + i) {
          logger.debug(
            '$key got host id $id, not ${first + i}: another plugin registered items first '
            '(the client takes the id from the registry sync, so it still matches).',
          );
        }
      } on ItemRegistryException catch (e) {
        logger.warn('Could not register $key: $e');
      }
    }
  }

  /// Adds CC: Tweaked's blocks to the host's block registry, in the order of the
  /// registry sync (`CcRegistries.blocks`), links each block item to its block
  /// and joins the block tags, and sets the placement rules (facing, orientation,
  /// waterlogging). Only the computers have behaviour (`CcWorldComputers`); the
  /// other blocks can be placed, stay, are broken and drop their item
  /// (docs/host-requirements.md).
  ///
  /// Every id the host reports is checked against what the registry sync tells
  /// the client; a mismatch stops the plugin from loading, because the client
  /// would otherwise draw other blocks than the server placed.
  CcBlockInstallation _registerBlocks() {
    final CcBlockInstallation installation;
    try {
      installation = installCcBlocks(
        BlockRegistries.host,
        expectedVanillaBlocks: VanillaRegistries.require('minecraft:block').length,
        expectedVanillaStates: vanillaBlockStateCount,
        firstItemId: ItemRegistries.host.vanillaCount,
        placement: BlockPlacements.host,
      );
    } on BlockRegistryException catch (e) {
      logger.error('CC: Tweaked blocks: ${e.message}');
      rethrow;
    }
    final first = installation.blocks.first;
    final last = installation.blocks.last;
    logger.info(
      'Registered ${installation.blocks.length} CC: Tweaked blocks (ids ${first.id} to ${last.id}), '
      '${installation.hostStates} block states from state id ${first.baseStateId}, '
      '${installation.tags.length} block tags.',
    );
    for (final plan in installation.incomplete) {
      logger.warn(
        '${plan.spec.key} has ${plan.hostStates} of the ${plan.clientStates} states the client has: '
        '${plan.spec.note}',
      );
    }
    for (final line in installation.skipped) {
      logger.warn('Not registered, $line.');
    }
    return installation;
  }

  /// Adds CC: Tweaked's block entity types, menu types and data component types
  /// to the host's registries, in the order of the registry sync and after the
  /// items and blocks, and verifies every id (`registry_install.dart`). A
  /// mismatch stops the plugin from loading with a message that says what to fix.
  void _registerRegistries() {
    try {
      final installation = installCcRegistries(
        blockEntityTypes: BlockEntityRegistries.host,
        menus: MenuRegistries.host,
        componentTypes: ComponentTypeRegistries.host,
        expectedBlockEntityVanillaCount: VanillaRegistries.require('minecraft:block_entity_type').length,
        expectedMenuVanillaCount: VanillaRegistries.require('minecraft:menu').length,
        expectedComponentVanillaCount: VanillaRegistries.require('minecraft:data_component_type').length,
      );
      logger.info(
        'Registered ${installation.blockEntityTypes.length} block entity types, '
        '${installation.menus.length} menu types and ${installation.componentTypes.length} data component types.',
      );
    } on PluginRegistryException catch (e) {
      logger.error('CC: Tweaked registries: ${e.message}');
      rethrow;
    }
  }

  /// Declares the mod to the host's NeoForge handshake for the real CC: Tweaked
  /// client. Off by default (`"neoforge": true` in the config). The host runs the
  /// handshake (channel negotiation before the brand, registry sync, channels,
  /// config file, the datapack registry entries); this plugin no longer does
  /// (docs/host-requirements.md, pumpkin_api `docs/neoforge-host.md`).
  ///
  /// Several plugins may declare: the host merges the declarations.
  void _declareNeoForge(Context context, CcDatapackRegistries datapack) {
    if (!_service.pluginConfig.neoForge) return;
    final version = _service.image.modVersion;
    if (version == null) {
      logger.warn(
        'neoforge is enabled but no CC: Tweaked jar was found: the mod version '
        '(the version string of its network channels) is unknown, using $fallbackModVersion.',
      );
    }
    try {
      context.declareNeoForge(ccNeoForgeDeclaration(datapack, modVersion: version));
    } on HostException catch (e) {
      logger.error('CC: Tweaked could not declare itself to the NeoForge handshake: ${e.message}');
      rethrow;
    }
  }
}
