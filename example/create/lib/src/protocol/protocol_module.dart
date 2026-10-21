// The protocol module: registers all 119 Create payload channels with the
// foundation and provides the `PayloadBus` and `ItemIdResolver` services. Load it
// first in `modules.dart`. See `lib/src/api/payloads.dart` for the public API.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/registry/create_registries.dart';
import '../content/components.dart';
import '../core/module.dart';
import '../core/registry.dart';
import 'codec_compiler.dart';
import 'host_item_stack.dart';
import 'item_stack.dart';
import 'payload_bus.dart';
import 'payload_hub.dart';

final class ProtocolModule extends CreateModule {
  final PlayerRoster _roster = PlayerRoster();
  late final PayloadHub<Player> _hub;
  Logger? _log;

  @override
  String get name => 'protocol';

  @override
  void register(CreateRegistry registry) {
    _hub = PayloadHub<Player>(
      schemas: PayloadSchemas.manifest,
      sink: _write,
      describePlayer: (p) => p.getName(),
    );
    registerPayloadChannels<Player>(registry.payloads, _hub);
  }

  void _write(ProtocolLogLevel level, String message) {
    final log = _log ?? Logger('create.protocol');
    switch (level) {
      case ProtocolLogLevel.debug:
        log.debug(message);
      case ProtocolLogLevel.warn:
        log.warn(message);
      case ProtocolLogLevel.error:
        log.error(message);
    }
  }

  @override
  void onLoad(CreateContext ctx) {
    _log = ctx.log;
    // The host ids are assigned now; teach the wire layer every Create component
    // before any payload can carry one.
    registerComponentReaders(
      (key) => ctx.ids.of(RegistryKind.dataComponents, key),
      attributeTypeId: (key) {
        try {
          return ExtraRegistries.syncedEntryId(CreateRegistries.itemAttributeType, key);
        } on Object {
          // Fall back to the manifest order, which is what the host numbers the
          // entries by; a failed lookup must not cost the other components their reader.
          return null;
        }
      },
      warn: ctx.log.warn,
    );
    ctx.services.provide<PayloadBus>(PayloadBus(_hub, _roster));
    ctx.services.provide<ItemIdResolver>(HostItemStacks.resolverFor(() => ctx.ids));
    ctx.listen(Events.playerJoin, (server, e) {
      if (_roster.add(server, e.player)) return;
      _log?.warn(
        'Could not put ${e.player.getName()} in the player roster: the server does not know that '
        'player, so broadcasts and tracking sends will skip them',
      );
    });
    ctx.listen(Events.playerLeave, (server, e) => _roster.remove(e.player));
  }

  @override
  void onServerLoaded(CreateRuntime runtime) => _roster.refresh(runtime.server);

  @override
  void onUnload() => _roster.clear();
}
