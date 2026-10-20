// Notifications for other mods about the assemblies Simulated performs.
//
// The physics assembler and the swivel bearing are the two blocks that turn a
// structure into a sub-level. Mods that keep their own data about a structure
// (Aeronautics' balloons, for example) need to know when that happened, and the
// dependency only runs one way — they import `simulated`, never the reverse — so
// they install a listener here instead.
//
// Pure: no host imports.
import 'sim_assembly_helper.dart';

/// A structure was assembled into a sub-level.
///
/// [worldId] is the world the blocks came from, [anchor] the block the structure
/// was assembled around, and [result] the new sub-level with the offset from
/// [anchor] to the plot centre.
typedef SimAssemblyListener = void Function(
  String worldId,
  (int, int, int) anchor,
  SimAssemblyResult result,
);

/// A sub-level was placed back into the world.
typedef SimDisassemblyListener = void Function(
  String worldId,
  (int, int, int) anchor,
  Object subLevel,
);

/// The listeners other mods install.
abstract final class SimAssemblyEvents {
  static final List<SimAssemblyListener> _assembled = [];
  static final List<SimDisassemblyListener> _disassembled = [];

  /// Registers [listener]; returns the function that removes it again.
  static void Function() onAssembled(SimAssemblyListener listener) {
    _assembled.add(listener);
    return () => _assembled.remove(listener);
  }

  /// Registers [listener]; returns the function that removes it again.
  static void Function() onDisassembled(SimDisassemblyListener listener) {
    _disassembled.add(listener);
    return () => _disassembled.remove(listener);
  }

  /// Tells every listener that [result] was assembled in [worldId].
  static void notifyAssembled(String worldId, (int, int, int) anchor, SimAssemblyResult result) {
    for (final listener in _assembled.toList()) {
      listener(worldId, anchor, result);
    }
  }

  /// Tells every listener that a sub-level was placed back at [anchor].
  static void notifyDisassembled(String worldId, (int, int, int) anchor, Object subLevel) {
    for (final listener in _disassembled.toList()) {
      listener(worldId, anchor, subLevel);
    }
  }

  /// Removes every listener (tests, plugin unload).
  static void clear() {
    _assembled.clear();
    _disassembled.clear();
  }
}
