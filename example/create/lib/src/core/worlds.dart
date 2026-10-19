// Kept `World` handles by id. Event worlds are only valid inside their callback
// (docs/lifetimes.md of pumpkin_api); everything that outlives a callback stores
// a world id and looks the world up here.
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

final class Worlds {
  final Map<String, World> _worlds = {};

  /// The kept world with [id] (`World.getId()`), or `null` if it is unknown or unloaded.
  World? byId(String id) => _worlds[id];

  /// The ids of all known worlds.
  Iterable<String> get ids => _worlds.keys;

  /// Remembers [world] (kept) if it is not known yet, and returns its id. Call it
  /// with the `targetWorld` of any event.
  String touch(World world) {
    final id = world.getId();
    _worlds.putIfAbsent(id, world.keep);
    return id;
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
  }
}
