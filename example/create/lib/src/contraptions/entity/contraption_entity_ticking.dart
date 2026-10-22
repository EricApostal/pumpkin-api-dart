// Ticking of the contraption entity types.
//
// `AbstractContraptionEntity.tick()` is the entity's own tick, and the host only fires
// `Events.entityTick` for a plugin type that opted in (`entity_tick_interval` is 0 otherwise,
// `crates/pumpkin-core/src/world/mod.rs:1708-1734`). The base module opts the core kinds in; a
// module that registers its own contraption entity type
// (`aeronautics:propeller_bearing_contraption`, `offroad:borehead_contraption_entity`) opts the
// ones it adds in with the same call, or its contraptions exist, are sent to the client and never
// move.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/module.dart' show CreateContext;
import '../core/entity_type_keys.dart' show reportedEntityTypeKey;
import 'host_contraption_entities.dart' show ContraptionHost;

/// Opts contraption entity types in on the running contraption host.
extension ContraptionEntityTicking on CreateContext {
  /// Ticks the contraption entities of [keys] on every server tick.
  ///
  /// The host ticks the type (`tickPluginEntities`) and `Events.entityTick` routes the tick to
  /// `ContraptionHost.onEntityTick`. It reports a plugin type with a `minecraft:` prefix
  /// (`minecraft:create:contraption`), so the key is normalized before it is matched
  /// ([reportedEntityTypeKey]).
  void tickContraptionEntityTypes(Iterable<String> keys) {
    final contraptions = services.find<ContraptionHost>();
    if (contraptions == null) {
      log.warn(
        'No contraption host: the contraptions of ${keys.join(', ')} will not tick.',
      );
      return;
    }
    final types = keys.toSet();
    listen(Events.entityTick, (server, e) async {
      if (!types.contains(reportedEntityTypeKey(e.entityType))) return;
      await contraptions.onEntityTick(e.entityId);
    });
    for (final key in types) {
      try {
        host.tickPluginEntities(key, interval: 1);
      } on Object catch (error) {
        log.warn('contraptions of $key are not ticked: $error');
      }
    }
  }
}