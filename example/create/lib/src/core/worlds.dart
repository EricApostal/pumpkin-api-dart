// Kept `World` handles by id. Event worlds are only valid inside their callback
// (docs/lifetimes.md of pumpkin_api): the host takes the handle back when the
// event returns, so everything that outlives a callback stores a world id and
// looks the world up here.
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import 'perf.dart';

/// One world tick, shared by every `worldTick` handler of the plugin.
///
/// The plugin registers a single host listener per world tick (see
/// `CreateCore.worldTickHandlers`), so the world id is fetched at most once per
/// world and tick instead of once per listener. [worldId] and [playersInWorld]
/// call the host lazily: a handler that returns before touching them costs no
/// host call at all, which is what makes an idle server cheap.
final class WorldTick {
  final Server server;
  final WorldTickEventData event;
  final Worlds _worlds;
  String? _worldId;
  List<Player>? _players;

  WorldTick(this.server, this.event, this._worlds);

  /// The world that ticked; valid for the duration of the tick.
  World get world => event.targetWorld;

  /// The server tick (`Server.tickCount`).
  int get tick => event.tick;

  /// The world id (`World.getId()`), resolved on first use and reused.
  String get worldId => _worldId ??= _worlds.touch(event.targetWorld);

  /// The players in the world (`Server.getPlayersInWorld`), fetched on first
  /// use. Only ask for it when a handler actually needs a player.
  List<Player> get playersInWorld =>
      _players ??= server.getPlayersInWorld(worldRef: event.targetWorld);
}

final class Worlds {
  final Map<String, World> _worlds = {};
  Context? _host;

  /// The kept world with [id] (`World.getId()`), or `null` if it is unknown or
  /// unloaded. Re-acquires the handle from the host if the cached one was
  /// released.
  World? byId(String id) {
    final world = _worlds[id];
    if (world != null && world.isValid) return world;
    _worlds.remove(id)?.dispose();
    return _resolve(id);
  }

  /// The ids of all known worlds.
  Iterable<String> get ids => _worlds.keys;

  /// Makes sure the world of [world] is kept, and returns its id. Call it with
  /// the `targetWorld` of any event.
  ///
  /// [world] itself is not kept: the host owns it again once the event returns.
  String touch(World world) {
    // The one host call an idle world tick makes (`WorldTick.worldId`): the id
    // is a host import and every handler that checks its world asks for it, so
    // it is worth its own label in the per-tick attribution.
    final watch = Perf.enabled ? (Stopwatch()..start()) : null;
    final id = world.getId();
    if (watch != null) Perf.record('host.worldId', watch.elapsedMicroseconds);
    final kept = _worlds[id];
    if (kept == null || !kept.isValid) {
      _worlds.remove(id)?.dispose();
      _resolve(id);
    }
    return id;
  }

  /// Asks the host for a fresh handle of the world [id] and keeps it.
  World? _resolve(String id) {
    final host = _host;
    if (host == null) return null;
    // A kept handle that went invalid costs a host round trip here (the list of
    // worlds plus their ids): visible per tick when it happens every tick.
    final watch = Perf.enabled ? (Stopwatch()..start()) : null;
    final server = host.getServer();
    try {
      for (final world in server.getAllWorlds()) {
        if (world.getId() == id) {
          return _worlds[id] = world.keep();
        }
        world.dispose();
      }
    } finally {
      server.dispose();
      if (watch != null) {
        Perf.record('host.resolveWorld', watch.elapsedMicroseconds);
      }
    }
    return null;
  }

  /// Forgets and releases the world [id].
  void forget(String id) => _worlds.remove(id)?.dispose();

  /// Remembers every world of [server].
  void refresh(Server server) {
    for (final world in server.getAllWorlds()) {
      final id = world.getId();
      if (_worlds.containsKey(id)) {
        world.dispose();
      } else {
        _worlds[id] = world.keep();
      }
    }
  }

  /// Keeps the table up to date from the world load and unload events.
  void install(Context context) {
    _host = context;
    context.listen(Events.worldLoad, (server, e) => touch(e.targetWorld));
    context.listen(Events.worldUnload, (server, e) {
      if (!e.cancelled) forget(e.targetWorld.getId());
    });
  }

  void clear() {
    for (final world in _worlds.values) {
      world.dispose();
    }
    _worlds.clear();
    _host = null;
  }
}
