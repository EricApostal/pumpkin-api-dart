// The property layouts of the blocks this plugin registered, by state id range (pure: no host
// bindings, so the state numbering is testable on the Dart VM).
//
// Why the plugin keeps its own copy: the host describes the state of a block with its vanilla
// `Property` enum (`crates/pumpkin-data/src/block_registry.rs`, `DynamicBlockProperties::to_props`
// keeps only the names and values that enum has). A Create property is neither a vanilla name nor
// a vanilla value - `turn` is not a vanilla property at all, and `shape` carries the rail values
// (`zo`, `cr_ndx`, ...) where vanilla has the stair values - so the host drops both and reports
// every `create:track` state as `{waterlogged=...}`. `BlockState.hasProperty(turn)` is then false
// for a track that has it, which is what made `TrackPlacement.tryConnect` answer
// `original_missing` (`TrackPlacement.java:170`) on every second click.
//
// The registration knows the real layout, so plugin blocks are described from it.
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// One registered block: the id of its first state and how its states are numbered.
final class StateRange {
  const StateRange(this.key, this.base, this.layout);

  final String key;

  /// The id of the first state (`CreateBlock.baseStateId`).
  final int base;

  /// The property layout the states follow (`CreateBlock.layout`).
  final BlockStateLayout layout;

  int get count => layout.stateCount;

  int get end => base + count;
}

/// The layouts of the plugin's own blocks, sorted by [StateRange.base].
abstract final class PluginStateLayouts {
  static final List<StateRange> _ranges = [];

  /// Describes the states `base ..< base + layout.stateCount` as [key] with [layout].
  static void register(String key, int base, BlockStateLayout layout) {
    _ranges
      ..removeWhere((r) => r.key == key)
      ..add(StateRange(key, base, layout))
      ..sort((a, b) => a.base.compareTo(b.base));
  }

  /// Forgets every layout (tests, plugin reloads).
  static void clear() => _ranges.clear();

  /// Every registered block, in state id order.
  static List<StateRange> get ranges => List.unmodifiable(_ranges);

  /// The block whose state range holds [stateId], `null` for a block of another plugin or
  /// vanilla.
  static StateRange? of(int stateId) {
    var low = 0;
    var high = _ranges.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final range = _ranges[mid];
      if (stateId < range.base) {
        high = mid - 1;
      } else if (stateId >= range.end) {
        low = mid + 1;
      } else {
        return range;
      }
    }
    return null;
  }

  /// The block called [key], `null` when this plugin did not register it.
  static StateRange? byKey(String key) {
    for (final range in _ranges) {
      if (range.key == key) return range;
    }
    return null;
  }

  /// The state id of [key] with [properties], `null` for an unknown property or value.
  static int? stateId(String key, Map<String, String> properties) {
    final range = byKey(key);
    if (range == null) return null;
    try {
      return range.base + range.layout.indexOf(properties);
    } on ArgumentError {
      return null;
    }
  }

  /// The property values of the state [stateId] of a block of this plugin.
  static Map<String, String>? valuesAt(int stateId) {
    final range = of(stateId);
    return range?.layout.valuesAt(stateId - range.base);
  }
}
