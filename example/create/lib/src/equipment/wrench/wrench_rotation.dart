// Port of `IWrenchable.getRotatedBlockState`: how a wrench click on [face] rotates a
// block state, from its properties. Pure.
import '../model/dir.dart';

/// Which kind of `facing` property a block has. Java tells `HORIZONTAL_FACING` (4 values)
/// from `FACING` (6 values) by property identity; here by the block's value list.
enum FacingKind { none, horizontal, sixWay }

abstract final class WrenchRotation {
  /// `VoxelShaper.axisAsFace(axis)`: the positive direction of the axis.
  static Dir axisAsFace(Ax a) => Dir.of(true, a);

  /// Whether the `axis` property of a block only has `x` and `z` (`HORIZONTAL_AXIS`).
  static bool axisIsHorizontalOnly(Iterable<String>? values) => values != null && !values.contains('y');

  /// The facing kind of a block given the values of its `facing` property
  /// (`null` when it has none).
  static FacingKind facingKindOf(Iterable<String>? values) {
    if (values == null) return FacingKind.none;
    final v = values.toSet();
    return v.contains('up') || v.contains('down') ? FacingKind.sixWay : FacingKind.horizontal;
  }

  /// The properties of the rotated state, or [props] unchanged when nothing rotates.
  static Map<String, String> rotated(
    Map<String, String> props,
    Dir targetedFace, {
    required FacingKind facing,
    bool axisHorizontalOnly = false,
  }) {
    final targetAxis = targetedFace.axis;

    if (targetAxis == Ax.y) {
      final hAxis = props['axis'];
      if (hAxis != null && axisHorizontalOnly) {
        // HORIZONTAL_AXIS: x <-> z.
        final a = Ax.parse(hAxis)!;
        return {...props, 'axis': axisAsFace(a).clockWiseAbout(targetAxis).axis.name};
      }
      if (facing == FacingKind.horizontal && props['facing'] != null) {
        final f = Dir.parse(props['facing']!);
        if (f != null && f.isHorizontal) {
          return {...props, 'facing': f.clockWiseAbout(targetAxis).name};
        }
      }
    }

    final axis = props['axis'];
    if (axis != null && !axisHorizontalOnly) {
      final a = Ax.parse(axis)!;
      return {...props, 'axis': axisAsFace(a).clockWiseAbout(targetAxis).axis.name};
    }

    if (facing != FacingKind.sixWay || props['facing'] == null) return props;

    final stateFacing = Dir.parse(props['facing']!)!;
    if (stateFacing.axis == targetAxis) {
      final along = props['axis_along_first'];
      if (along != null) {
        return {...props, 'axis_along_first': along == 'true' ? 'false' : 'true'};
      }
      return props;
    }
    var next = Map<String, String>.of(props);
    var f = stateFacing;
    do {
      f = f.clockWiseAbout(targetAxis);
      next['facing'] = f.name;
      if (targetAxis == Ax.y && next.containsKey('axis_along_first')) {
        next['axis_along_first'] = next['axis_along_first'] == 'true' ? 'false' : 'true';
      }
    } while (f.axis == targetAxis);
    return next;
  }
}
