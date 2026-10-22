import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge.dart'
    show VanillaRegistries, vanillaBlockStateCount;

import 'block_install.dart';
import 'declared_registries.dart';
import 'host_adapter.dart';
import 'item_install.dart';
import 'manifest.dart';
import 'manifest.g.dart';
import 'neoforge.dart';
import 'omnitool.dart';
import 'validation.dart';

/// The server side of the Lonsdaleite Tools NeoForge mod: registers its items
/// and item tags, declares the mod to the host's NeoForge handshake (so a client
/// with the mod knows the ids of the entries and joins), and runs the behaviour
/// that the mod's Java code executes on the server.
///
/// Needs the `registry.items`, `registry.blocks` and `neoforge` permissions and a
/// Pumpkin build with the `item-registry` and `block-registry` interfaces (see
/// README.md).
final class LonsdaleitePlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'lonsdaleite',
    version: '0.1.0',
    description: 'Server side of the Lonsdaleite Tools mod.',
    permissions: [
      Permissions.registryItems,
      Permissions.registryBlocks,
      Permissions.neoforge,
    ],
  );

  late final Manifest manifest = Manifest.parse(lonsdaleiteManifestJson);

  @override
  void onLoad(Context context) {
    final issues = validateManifest(manifest);
    if (issues.isNotEmpty) {
      throw StateError(
        'The embedded manifest is inconsistent:\n${issues.join('\n')}',
      );
    }

    // Order matters. Registration closes when players can connect, so all of
    // it happens here, and in this order:
    //   1. the items (the wardframe item first: it keeps the id the client
    //      expects, and the block links to an existing item),
    //   2. the wardframe block, its tags and the link to its item,
    //   3. the NeoForge sync, which announces the ids the host assigned.
    final installation = installManifestItems(
      manifest,
      HostItemRegistrar(),
      expectedVanillaItems: VanillaRegistries.require('minecraft:item'),
    );
    logger.info(
      '${manifest.mod.name} ${manifest.mod.version}: registered ${installation.items.length} '
      'items (ids ${installation.vanillaCount} to '
      '${installation.vanillaCount + installation.items.length - 1}) and '
      '${installation.itemTags.length} item tags.',
    );
    for (final line in installation.skippedComponents.describe()) {
      logger.info('Skipped component, $line');
    }
    final blocks = installManifestBlock(
      manifest,
      BlockRegistries.host,
      items: installation,
      expectedVanillaBlocks: VanillaRegistries.require('minecraft:block')
          .length,
      expectedVanillaStates: vanillaBlockStateCount,
    );
    logger.info(
      'Registered block ${blocks.block.key}: id ${blocks.block.id}, '
      '${blocks.block.stateCount} states from state id ${blocks.block.baseStateId} '
      '(default state ${blocks.defaultStateId}), item id ${blocks.block.itemId}, '
      '${blocks.blockTags.length} block tags (${blocks.blockTags.join(', ')}).',
    );

    _declareNeoForge(context, installation, blocks);
    _command(context);
    _omnitool(context);
  }

  /// Declares the mod to the host's NeoForge handshake (`Context.declareNeoForge`,
  /// `neoforge.dart`): the mod, and the two registries the plugin registered content
  /// in (`minecraft:item`, `minecraft:block`). Naming a registry is the vouch that
  /// lets the host send the mod's entries in it; without it the host drops the
  /// registry from the sync for every plugin, not just for this one.
  ///
  /// Called **after** the items and the block: the host numbers the entries in
  /// registration order, and the declaration claims exactly what was registered.
  void _declareNeoForge(
    Context context,
    ItemInstallation installation,
    BlockInstallation blocks,
  ) {
    try {
      context.declareNeoForge(lonsdaleiteDeclaration(manifest));
    } on HostException catch (e) {
      logger.error('Could not declare the mod to the NeoForge handshake: ${e.message}');
      rethrow;
    }
    logger.info(
      'Declared ${manifest.mod.name} ${manifest.mod.version} to the NeoForge handshake: '
      '${lonsdaleiteDeclaredRegistries.join(', ')} with '
      '${installation.items.length} items (ids ${installation.vanillaCount} to '
      '${installation.vanillaCount + installation.items.length - 1}) and block '
      '${blocks.block.key} (id ${blocks.block.id}, ${blocks.block.stateCount} states from '
      'state id ${blocks.block.baseStateId}); clients without the mod are refused.',
    );
  }

  /// `/lonsdaleite`: which online players joined with the NeoForge handshake.
  void _command(Context context) {
    context.command(
      'lonsdaleite',
      description: 'Which players joined with the NeoForge handshake',
      permission: 'lonsdaleite:command.lonsdaleite',
      (c) => c.runs((ctx) {
        final lines = [
          for (final player in ctx.server.allPlayers)
            '${player.getName()}: ${player.isNeoForge ? 'NeoForge' : 'not NeoForge'}',
        ];
        ctx.replyLines(['Online players: ${lines.length}', ...lines]);
      }),
    );
  }

  /// Right click on a block with an omnitool strips, tills or flattens it.
  ///
  /// Needs a host call that does not exist yet (`blockTransformersFor`): until
  /// then the handler leaves every click alone (it does not crash).
  void _omnitool(Context context) {
    final omnitools = {
      for (final item in manifest.itemsOfKind(ItemKind.omnitool)) item.id,
    };
    context.intercept(Events.playerInteract, (server, event) async {
      if (event.action != InteractAction.rightClickBlock) return event;
      final held = event.player.getItemInHand(hand: Hand.right);
      if (held == null ||
          !omnitools.contains(_qualified(await held.getRegistryKey()))) {
        return event;
      }
      try {
        final used = useOmnitool(
          blockTransformersFor(event),
          sneaking: event.player.asEntity().isSneaking(),
        );
        return used == null ? event : event.cancel();
      } on HostApiMissing {
        return event;
      }
    });
  }

  /// Registry keys of vanilla items come without a namespace.
  static String _qualified(String key) =>
      key.contains(':') ? key : 'minecraft:$key';
}
