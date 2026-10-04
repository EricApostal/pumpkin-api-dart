import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/module.dart';
import '../core/permissions.dart';
import 'commands.dart';
import 'defaults.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// A chest-menu shop with `/buy`, `/sell` and `/worth`, paid in the
/// [Economy]. See `docs/shop.md`.
final class ShopModule extends Module {
  @override
  String get name => 'shop';

  @override
  List<String> get dependsOn => const ['economy'];

  @override
  List<PermNode> get permissions => ShopPerms.all;

  @override
  void onLoad(ModuleHost host) {
    final docs = host.docs;
    final service = ShopService(
      economy: host.services.require<Economy>(),
      clock: host.clock,
      catalog: docs.open(
        catalogPath,
        decode: ShopCatalogMapper.fromJson,
        encode: (v) => v.toJson(),
        create: defaultCatalog,
      ),
      config: docs.open(
        configPath,
        decode: ShopConfigMapper.fromJson,
        encode: (v) => v.toJson(),
        create: ShopConfig.new,
      ),
      ledger: docs.open(
        ledgerPath,
        decode: LedgerMapper.fromJson,
        encode: (v) => v.toJson(),
        create: Ledger.new,
      ),
      isKnownItem: _isKnownItem,
      warn: host.log.warn,
    );
    for (final problem in service.problems) {
      host.log.warn(problem);
    }
    _registerEntryPermissions(host.context, service);

    host.context.installMenus();
    final texts = ShopTexts(
      host.messages(shopMessageDefaults, prefix: ''),
      host.services.require<Economy>(),
      () => service.config.prefix,
    );
    registerShopCommands(
      host.context,
      shop: service,
      ui: ShopUi(service, texts, host.log),
      texts: texts,
      backend: docs.backend,
      confirmations: ConfirmationManager(
        now: host.clock.now,
        defaultTtl: const Duration(seconds: 20),
      ),
      onReloaded: () => _registerEntryPermissions(host.context, service),
      log: host.log,
    );
    host.log.info(
      'Shop ready: ${service.catalog.categories.length} categories, '
      '${service.catalog.entryCount} items.',
    );
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

  /// Entries can name their own permission; those nodes are registered here
  /// (operators have them, everybody else needs them granted).
  void _registerEntryPermissions(Context context, ShopService service) {
    final nodes = {
      for (final category in service.catalog.categories)
        for (final entry in category.entries)
          if (entry.permission != null) entry.permission!,
    };
    context.registerPermissions([
      for (final node in nodes)
        PermissionNode(
          node,
          description: 'Trade items restricted in the shop',
          defaultValue: const PermissionDefaultKind.op(PermissionLevel.two),
        ),
    ]);
  }
}
