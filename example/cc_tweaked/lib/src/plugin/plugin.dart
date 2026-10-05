// The Pumpkin plugin: loads the service, installs the command, the network
// side and the optional NeoForge handshake, and drives the computers from the
// server tick.
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge.dart';

import '../protocol/registries.dart';
import 'block_install.dart';
import 'block_states.dart';
import 'commands.dart';
import 'network.dart';
import 'registry_install.dart';
import 'service.dart';
import 'world_computers.dart';

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
  NeoForgeServer? _neoForge;
  CcWorldComputers? _world;
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
    ],
  );

  @override
  void onLoad(Context context) {
    _service = CcService.load(context.files);
    final network = CcNetwork()..install(context);
    registerCommands(context, _service, network);
    _installNeoForge(context);
    final neoForge = _neoForge;
    if (neoForge != null) {
      network.canOpenGui = (player) {
        final client = neoForge.clientOf(player.getId().asString);
        return client != null && client.isAccepted && client.isNeoForge;
      };
    }
    if (_service.pluginConfig.neoForge) {
      // Order matters, and is the order of the registry sync: the items first (a
      // block links to an existing item), then the blocks, then the block entity
      // types, menu types and data component types. Registration closes when
      // players can connect.
      _registerItems();
      final blocks = _registerBlocks();
      _registerRegistries();
      final world = CcWorldComputers(_service, network, CcBlockStates(blocks))..install(context);
      _world = world;
    }

    context.runRepeating(1, (server) {
      if (_tick++ % _timeSyncInterval == 0) _syncWorldTime(server);
      _service.tick();
      _world?.tick(server);
      network.tick(server);
    });
    context.onUnload(_service.shutdown);
    logger.info('CC: Tweaked server side loaded.');
  }

  /// Makes the in-game clock of the computers follow the overworld.
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
  /// registry sync, so their ids (vanilla count + position) are the ones the
  /// client is told. They are plain items (no default components): the block items
  /// are linked to their blocks by [_registerBlocks]; the data components they
  /// carry are set on stacks (`CcComponents`), see docs/host-requirements.md.
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
        if (id != first + i) {
          logger.warn('$key got id $id, the registry sync expects ${first + i}: another plugin registered items first.');
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

  /// Installs the NeoForge handshake and registry synchronisation for the real
  /// CC: Tweaked client. Off by default (`"neoforge": true` in the config). It
  /// uses the library's full negotiation: the host holds the connection before
  /// the brand (`Context.onConfiguration(onPreBrand:)`), the plugin sends the
  /// `neoforge:register` query and marks the connection as NeoForge in the host
  /// (`ConfigurationConnection.setFlavour`), see docs/host-requirements.md.
  ///
  /// Only one plugin per server may do this: a server that also runs another
  /// NeoForge mod's plugin (Lonsdaleite) needs one plugin that owns the spec
  /// of both (README.md, "Combining with other NeoForge plugins").
  void _installNeoForge(Context context) {
    if (!_service.pluginConfig.neoForge) return;
    final version = _service.image.modVersion;
    if (version == null) {
      logger.warn(
        'neoforge is enabled but no CC: Tweaked jar was found: the mod version '
        '(the version string of its network channels) is unknown, using 1.120.3.',
      );
    }
    final server = NeoForgeServer(
      CcRegistries.serverSpec(version ?? '1.120.3'),
      options: const NeoForgeServerOptions(
        negotiation: NeoForgeNegotiation.full,
        nonNeoForge: NonNeoForgePolicy.allow,
      ),
    );
    server.install(context);
    _neoForge = server;
    // A NeoForge client expects the elytra attribute and the (empty) recipe
    // content from the server; only connections the handshake marked are
    // touched.
    server.installPlay(context);
    server.onClient((client) {
      logger.info('${client.username}: NeoForge handshake ${client.outcome.name}');
    });
  }
}
