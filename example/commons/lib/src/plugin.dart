import 'package:pumpkin_api/pumpkin_api.dart';

import 'core/clock.dart';
import 'core/module.dart';
import 'core/permissions.dart';
import 'core/players.dart';
import 'core/services.dart';
import 'core/storage.dart';
import 'core/storage_pumpkin.dart';
import 'load_order.dart';
import 'modules.dart';

/// How often changed documents are written to disk.
const autosaveInterval = Duration(seconds: 10);

final class CommonsPlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'commons',
    version: '1.0.0',
    description: 'Economy, shop, kits, mail, chat, moderation and rewards for a community server.',
    permissions: [Permissions.fsWriteData],
  );

  final _log = Logger('core');
  final _services = Services();
  final List<Module> _loaded = [];
  late Documents _docs;

  @override
  void onLoad(Context context) {
    const clock = SystemClock();
    _docs = Documents(
      DataFolderBackend(context.files),
      clock: clock,
      warn: _log.warn,
    );

    final players = PlayerDirectory(_docs, clock);
    _services.provide<PlayerDirectory>(players);
    context.listen(Events.playerJoin, (server, event) {
      final player = event.player;
      players.touch(player.asEntity().getUuid().asString, player.getName());
    });

    for (final module in loadOrder(
      allModules(),
      name: (m) => m.name,
      dependsOn: (m) => m.dependsOn,
    )) {
      try {
        _registerPermissions(context, module.permissions);
        module.onLoad(
          ModuleHost(
            moduleName: module.name,
            context: context,
            services: _services,
            docs: _docs,
            clock: clock,
          ),
        );
        _loaded.add(module);
      } catch (e, s) {
        // One broken module must not take the others down.
        _log.error(
          'Module ${module.name} failed to load',
          error: e,
          stackTrace: s,
        );
      }
    }

    context.every(autosaveInterval, (_) => _docs.saveDirty());
    _log.info('Loaded modules: ${_loaded.map((m) => m.name).join(', ')}');
  }

  @override
  void onUnload(Context context) {
    for (final module in _loaded.reversed) {
      try {
        module.onUnload();
      } catch (e, s) {
        _log.error(
          'Module ${module.name} failed to unload',
          error: e,
          stackTrace: s,
        );
      }
    }
    _docs.saveDirty();
  }

  void _registerPermissions(Context context, List<PermNode> nodes) {
    for (final node in nodes) {
      final result = context.registerPermission(
        permission: Permission(
          node: node.node,
          description: node.description,
          default_: switch (node.defaultFor) {
            PermDefault.everyone => const PermissionDefaultAllow(),
            PermDefault.op => const PermissionDefaultOp(PermissionLevel.two),
            PermDefault.nobody => const PermissionDefaultDeny(),
          },
          children: const [],
        ),
      );
      if (result case ErrorResult(:final value)) {
        _log.warn('Could not register ${node.node}: $value');
      }
    }
  }
}
