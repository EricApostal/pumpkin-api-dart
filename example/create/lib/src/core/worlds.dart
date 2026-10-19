// Kept `World` handles by id. Event worlds are only valid inside their callback
// (docs/lifetimes.md of pumpkin_api): the host takes the handle back when the
// event returns, so everything that outlives a callback stores a world id and
// looks the world up here.
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

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
    final id = world.getId();
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
