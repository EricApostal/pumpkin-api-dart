import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge.dart'
    show NeoForgeServer, VanillaRegistries, vanillaBlockStateCount;

import 'block_install.dart';
import 'host_adapter.dart';
import 'item_install.dart';
import 'manifest.dart';
import 'manifest.g.dart';
import 'neoforge.dart';
import 'omnitool.dart';
import 'validation.dart';

/// The server side of the Lonsdaleite Tools NeoForge mod: registers its items
/// and item tags, answers NeoForge's registry sync so clients with the mod can
/// join, and runs the behaviour that the mod's Java code executes on the
/// server.
///
/// Needs the `registry.items` and `registry.blocks` permissions and a Pumpkin
/// build with the `item-registry` and `block-registry` interfaces (see
/// README.md).
final class LonsdaleitePlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'lonsdaleite',
    version: '0.1.0',
    description: 'Server side of the Lonsdaleite Tools mod.',
    permissions: [Permissions.registryItems, Permissions.registryBlocks],
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

    final neoforge = installNeoForge(context, manifest, installation, blocks);
    _command(context, neoforge);
    _omnitool(context);
  }

  /// `/lonsdaleite`: which players joined with the NeoForge handshake.
  void _command(Context context, NeoForgeServer neoforge) {
    context.command(
      'lonsdaleite',
      description: 'Which players joined with the NeoForge handshake',
      permission: 'lonsdaleite:command.lonsdaleite',
      (c) => c.runs((ctx) {
        final lines = [
          for (final client in neoforge.clients)
            '${client.username}: ${client.outcome.name}'
                ' brand=${client.brand} synced=${client.syncedRegistries.length}',
        ];
        ctx.replyLines(['NeoForge clients: ${lines.length}', ...lines]);
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
    context.intercept(Events.playerInteract, (server, event) {
      if (event.action != InteractAction.rightClickBlock) return event;
      final held = event.player.getItemInHand(hand: Hand.right);
      if (held == null || !omnitools.contains(_qualified(held.registryKey))) {
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
