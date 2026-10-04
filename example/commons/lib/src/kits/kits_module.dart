import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/module.dart';
import '../core/permissions.dart';
import '../core/players.dart';
import 'commands.dart';
import 'defaults.dart';
import 'inventory.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// How long after joining a player still counts as new. The core records the
/// player on join, so "first seen a moment ago" means "first time here".
const _newPlayerWindow = Duration(minutes: 1);

/// Time to let a new player finish joining before the starter kit is given.
const _starterDelay = Duration(seconds: 2);

/// Kits players can claim from a menu or with `/kit <name>`, with cooldowns,
/// one-time kits, prices and a starter kit. See `docs/kits.md`.
final class KitsModule extends Module {
  @override
  String get name => 'kits';

  @override
  List<String> get dependsOn => const ['economy'];

  @override
  List<PermNode> get permissions => KitPerms.all;

  @override
  void onLoad(ModuleHost host) {
    final docs = host.docs;
    final economy = host.services.require<Economy>();
    final service = KitService(
      economy: economy,
      clock: host.clock,
      catalog: docs.open(
        kitsPath,
        decode: KitCatalogMapper.fromJson,
        encode: (v) => v.toJson(),
        create: defaultKits,
      ),
      config: docs.open(
        configPath,
        decode: KitsConfigMapper.fromJson,
        encode: (v) => v.toJson(),
        create: KitsConfig.new,
      ),
      claims: docs.open(
        claimsPath,
        decode: KitClaimsMapper.fromJson,
        encode: (v) => v.toJson(),
        create: KitClaims.new,
      ),
      isKnownItem: _isKnownItem,
      isKnownEnchantment: (key) => EnchantmentKey.fromKey(key) != null,
      warn: host.log.warn,
    );
    for (final problem in service.problems) {
      host.log.warn(problem);
    }

    void registerKitPermissions() => host.context.registerPermissions([
      for (final kit in service.kits)
        PermissionNode(
          kit.permission,
          description: 'Claim the ${kit.name} kit',
          defaultValue: kit.restricted
              ? const PermissionDefaultKind.op(PermissionLevel.two)
              : PermissionDefaultKind.allow,
        ),
    ]);
    registerKitPermissions();

    host.context.installMenus();
    final texts = KitTexts(
      host.messages(kitMessageDefaults, prefix: ''),
      economy,
      () => service.config.prefix,
    );
    registerKitCommands(
      host.context,
      kits: service,
      ui: KitsUi(service, texts, host.log),
      texts: texts,
      backend: docs.backend,
      onKitsChanged: registerKitPermissions,
      log: host.log,
    );
    _giveStarterKitOnJoin(host, service, texts);
    host.log.info('Kits ready: ${service.kits.map((k) => k.name).join(', ')}.');
  }

  /// Whether the server knows an item called [key]. The host has no registry
  /// lookup: asking for an unknown item gives air, so the key that comes back
  /// tells.
  bool _isKnownItem(String key) {
    try {
      final stack = ItemStack.create(registryKey: key, count: 1);
      final actual = stack.getRegistryKey();
      stack.dispose();
      return registryKeysMatch(actual, key);
    } catch (_) {
      return false;
    }
  }

  void _giveStarterKitOnJoin(
    ModuleHost host,
    KitService service,
    KitTexts texts,
  ) {
    final players = host.services.require<PlayerDirectory>();
    host.context.listen(Events.playerJoin, (server, event) {
      if (!service.config.giveStarterKit) return;
      final uuid = event.player.asEntity().getUuid().asString;
      // Wait until the player has finished joining (and the core has
      // recorded them), then look the player up again: the handle of the
      // event is gone by then.
      server.after(_starterDelay, (server) {
        final id = Uuids.tryParse(uuid);
        final player = id == null ? null : server.getPlayerByUuid(id: id);
        if (player == null) return;
        try {
          final record = players.byUuid(uuid);
          final isNew =
              record != null &&
              host.clock.now().difference(record.firstSeen) < _newPlayerWindow;
          final result = service.grantStarterKit(
            PlayerKitRecipient(player),
            isNewPlayer: isNew,
          );
          if (result == null) return;
          if (result.isOk) {
            player.title(
              texts.plain('starter.title', {'player': player.getName()}),
              subtitle: texts.plain('starter.subtitle'),
              stay: const Duration(seconds: 3),
            );
          } else if (result.failure == ClaimFailure.noSpace) {
            player.send(texts.line('starter.no_room'));
          }
        } catch (e, s) {
          host.log.error(
            'Could not give the starter kit',
            error: e,
            stackTrace: s,
          );
        }
      });
    });
  }
}
