// Copycat blocks (pure part): which blocks a copycat accepts as material, how a material is
// turned by right-clicking it again, and the NBT form of a material block state.
import '../api/block_state.dart';
import '../common/direction.dart';

const String copycatBaseKey = 'create:copycat_base';
const String copycatStepKey = 'create:copycat_step';
const String copycatPanelKey = 'create:copycat_panel';
const String copycatBarsKey = 'create:copycat_bars';

/// `BlockStateProperties.FACING` order of 26.3 (the order `BlockState.cycle` follows).
const List<String> facingCycle = ['north', 'east', 'south', 'west', 'up', 'down'];

/// Whether [s] is a copycat wrapper state (a `CopycatBlock`).
bool isCopycatBlock(String key) => key == copycatStepKey || key == copycatPanelKey;

/// `CopycatSpecialCases.isBarsMaterial`: iron bars style blocks that are not panes.
bool isBarsMaterial(BState material) {
  final path = material.key.substring(material.key.indexOf(':') + 1);
  final looksLikeBars = material.has('north') && material.has('east') && material.has('south') && material.has('west');
  if (!looksLikeBars || material.has('up')) return false;
  if (path.endsWith('_pane') || path == 'glass_pane') return false;
  return path.endsWith('_bars') || path == 'iron_bars';
}

/// `CopycatSpecialCases.isTrapdoorMaterial`.
bool isTrapdoorMaterial(BState material) =>
    material.key.endsWith('_trapdoor') && material.has('half') && material.has('open') && material.has('facing');

/// What the host knows about a block an item would place, for [copycatAcceptedState].
final class MaterialCandidate {
  /// The default state of the block.
  final BState defaultState;

  /// `block instanceof EntityBlock`.
  final bool isEntityBlock;

  /// `block instanceof StairBlock`.
  final bool isStair;

  /// In the `create:copycat_allow` / `create:copycat_deny` block tags.
  final bool allowTag;
  final bool denyTag;

  /// The default state has a full cube selection shape and a non-empty collision shape (the
  /// shape test of `getAcceptedBlockState`, only done when a level is available).
  final bool shapeOk;

  const MaterialCandidate({
    required this.defaultState,
    this.isEntityBlock = false,
    this.isStair = false,
    this.allowTag = false,
    this.denyTag = false,
    this.shapeOk = true,
  });
}

/// `CopycatBlock.getAcceptedBlockState`: the material state a [candidate] block gives, or `null`
/// when the copycat does not accept it. [isAcceptedRegardless] is the copycat's override (panels
/// take bars and trapdoors); [face] orients the material to the clicked face (null: keep);
/// [valid] tells whether a state with the given properties exists (a property value outside the
/// block's domain is not valid), which replaces Java's typed property checks.
BState? copycatAcceptedState(
  MaterialCandidate candidate, {
  required bool Function(BState material) isAcceptedRegardless,
  required bool Function(BState state) valid,
  Direction? face,
  bool checkShape = true,
}) {
  var applied = candidate.defaultState;
  if (isCopycatBlock(applied.key)) return null;
  final hardCodedAllow = isAcceptedRegardless(applied);
  if (!candidate.allowTag && !hardCodedAllow) {
    if (candidate.denyTag) return null;
    if (candidate.isEntityBlock) return null;
    if (candidate.isStair) return null;
    if (checkShape && !candidate.shapeOk) return null;
  }
  if (face != null) {
    final axis = face.axis;
    // FACING (six values) and HORIZONTAL_FACING (four values, only for horizontal faces).
    if (applied.has('facing')) {
      final next = applied.setValue('facing', face.serializedName);
      if (valid(next)) applied = next;
    }
    // AXIS (x, y, z) and HORIZONTAL_AXIS (x, z).
    if (applied.has('axis')) {
      final next = applied.setValue('axis', axis.serializedName);
      if (valid(next)) applied = next;
    }
  }
  return applied;
}

/// `CopycatBlockEntity.cycleMaterial`: the next orientation of [material], or `null` when the
/// material cannot be turned. [valid] as in [copycatAcceptedState].
BState? copycatCycleMaterial(BState material, bool Function(BState state) valid) {
  if (material.has('half') && const {'top', 'bottom'}.contains(material['half']) && material.flag('open')) {
    return material.setValue('half', material['half'] == 'top' ? 'bottom' : 'top');
  }
  if (material.has('facing')) {
    final six = valid(material.setValue('facing', 'up'));
    final current = material['facing']!;
    if (six) {
      final i = facingCycle.indexOf(current);
      return material.setValue('facing', facingCycle[(i + 1) % facingCycle.length]);
    }
    final facing = Direction.byName(current);
    if (facing != null && facing.isHorizontal) return material.setValue('facing', facing.clockWise.serializedName);
  }
  if (material.has('axis')) {
    final three = valid(material.setValue('axis', 'y'));
    final current = material['axis']!;
    if (three) {
      const axes = ['x', 'y', 'z'];
      return material.setValue('axis', axes[(axes.indexOf(current) + 1) % 3]);
    }
    return material.setValue('axis', current == 'x' ? 'z' : 'x');
  }
  if (material.has('lit')) return material.cycleFlag('lit');
  if (material.has('powering')) return material.cycleFlag('powering');
  return null;
}

/// The key set of `NbtUtils.writeBlockState`: `Name` and `Properties`.
Map<String, Object> materialToMap(BState material) => {
  'Name': material.key,
  if (material.props.isNotEmpty) 'Properties': Map<String, String>.of(material.props),
};

/// The inverse of [materialToMap].
BState? materialFromMap(Map<String, Object?> map) {
  final name = map['Name'];
  if (name is! String) return null;
  final props = map['Properties'];
  return BState(name, props is Map ? {for (final e in props.entries) '${e.key}': '${e.value}'} : const {});
}
