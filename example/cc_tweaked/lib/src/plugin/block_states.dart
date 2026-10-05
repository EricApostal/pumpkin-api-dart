// Reads and writes the block state ids of CC's blocks: which block and which
// property values a state id means, and the id of a block with other values
// (for example the same computer, now `state=on`). Binding-free: it works on
// what `installCcBlocks` verified.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../protocol/blocks.dart';
import 'block_install.dart';

/// A state id read as a CC block with its property values.
final class CcBlockState {
  /// `computercraft:<name>`.
  final String key;

  /// The property values by name.
  final Map<String, String> values;

  const CcBlockState(this.key, this.values);

  @override
  String toString() => '$key$values';
}

final class CcBlockStates {
  final List<RegisteredBlock> _blocks;
  final List<CcBlockPlan> _plans;

  CcBlockStates(CcBlockInstallation installation)
    : _blocks = installation.blocks,
      _plans = installation.plans;

  /// Every registered block key.
  Iterable<String> get keys => [for (final b in _blocks) b.key];

  /// The block and values of [stateId], `null` if it is not a CC state.
  CcBlockState? decode(int stateId) {
    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      final index = stateId - block.baseStateId;
      if (index >= 0 && index < block.stateCount) {
        return CcBlockState(block.key, _plans[i].definition.layout.valuesAt(index));
      }
    }
    return null;
  }

  /// Whether [stateId] belongs to the block [key].
  bool isBlock(int stateId, String key) => decode(stateId)?.key == key;

  /// The id of the state of [key] with [values] (properties that are not
  /// listed have their default value), `null` if the block is not registered
  /// or the host does not have such a state.
  int? encode(String key, Map<String, String> values) {
    for (var i = 0; i < _blocks.length; i++) {
      if (_blocks[i].key != key) continue;
      try {
        return _blocks[i].baseStateId + _plans[i].definition.layout.indexOf(values);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// [stateId] with the properties in [changes] set to other values (same
  /// block); `null` if [stateId] is not a CC state or the result does not
  /// exist.
  int? withValues(int stateId, Map<String, String> changes) {
    final state = decode(stateId);
    if (state == null) return null;
    return encode(state.key, {...state.values, ...changes});
  }
}
