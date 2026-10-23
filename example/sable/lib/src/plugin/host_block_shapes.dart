// The host half of the collision bakery: `BlockState.getCollisionShape` and
// `state.liquid()` over the server's block registry.
//
// Java reads both off the `BlockState` object itself
// (`RapierVoxelColliderBakery.buildPhysicsDataForBlock`). Dart block states are
// plain data, so the state string is resolved to the host's registry entry
// (`BlockStates.stateOfId`, which also covers this plugin's own blocks) and the
// entry's collision boxes and liquid flag are the answer.
//
// Host: this file uses `pumpkin_api`, so it is only linked by the plugin entry
// point (`bin/main.dart`), never by the pure `src/physics/jolt.dart` barrel.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show stateIdOf;
import 'package:create/src/common/host_bridge.dart' show BlockStates;
import 'package:pumpkin_api/pumpkin_api.dart';
import '../../sable.dart' show BlockStateKey;

import '../physics/jolt/voxel.dart';
import '../physics/section_packer.dart';

/// [BlockShapeSource] over the host's block registry.
final class HostBlockShapeSource implements BlockShapeSource {
  /// The resolved state per state string, cached for the life of the plugin (a
  /// state id always names the same state).
  final Map<String, _ResolvedState?> _states = {};

  /// The baked box lists, by state string.
  final Map<String, List<VoxelBox>> _boxes = {};

  @override
  List<VoxelBox>? boxesOf(String state) {
    final resolved = _resolve(state);
    if (resolved == null) return null;
    final cached = _boxes[state];
    if (cached != null) return cached;
    final boxes = <VoxelBox>[
      for (final box in resolved.info.collisionShapes)
        VoxelBox(box.min.$1, box.min.$2, box.min.$3, box.max.$1, box.max.$2, box.max.$3),
    ];
    _boxes[state] = boxes;
    return boxes;
  }

  @override
  bool isLiquid(String state) {
    final resolved = _resolve(state);
    if (resolved == null) return false;
    // Java's `state.liquid()` is "has a fluid state", which is a fluid block *or*
    // a waterlogged one (`SimpleWaterloggedBlock`); the host's flag is the
    // block-level `is_liquid`, so the property is added here. Java also counts
    // kelp explicitly, and kelp is a liquid block in the host's table.
    return resolved.info.isLiquid || resolved.state.flag('waterlogged');
  }

  _ResolvedState? _resolve(String state) {
    if (_states.containsKey(state)) return _states[state];
    final key = BlockStateKey.parse(state);
    final bstate = BState(key.blockId, key.properties);
    final id = stateIdOf(bstate);
    final info = id == null ? null : BlockStates.stateOfId(id);
    return _states[state] = info == null ? null : _ResolvedState(info, bstate);
  }
}

/// One state string resolved against the host registry.
final class _ResolvedState {
  final BlockState info;
  final BState state;

  const _ResolvedState(this.info, this.state);
}
