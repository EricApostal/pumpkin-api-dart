/// Vanilla-integration parity: the server-side half of Sable's mixins,
/// re-expressed as plugin hooks, ported algorithms and a host-gap list.
///
/// * `mixin_inventory.dart` -- every server-side Java patch and its bucket,
/// * `host_gap.dart` -- the host features that do not exist yet,
/// * `entity_tracking_rules.dart` -- which sub-level an entity is on,
/// * `entity_collision_effects.dart` -- standing on / running into a ship,
/// * `projectile_handlers.dart` -- shots and arrows,
/// * `explosion_handlers.dart` -- blast rays and impulses,
/// * `block_event_handlers.dart` -- drops, spawns, fluids, growth, lightning,
/// * `player_handlers.dart` -- teleport, death message, respawn, freeze,
/// * `impact_callbacks.dart` -- the fragile/beehive/bell/TNT block callbacks.
///
/// Everything here is pure, so the VM tests cover it.
library;

export 'block_event_handlers.dart';
export 'entity_collision_effects.dart';
export 'entity_tracking_rules.dart';
export 'explosion_handlers.dart';
export 'host_gap.dart';
export 'impact_callbacks.dart';
export 'mixin_inventory.dart';
export 'player_handlers.dart';
export 'projectile_handlers.dart';
