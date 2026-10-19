// `ContraptionWorld` (pure): a read-only level over the blocks of a contraption. Used for the
// collision shapes of carried blocks; blocks outside the contraption are air.
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/level.dart';

/// `ContraptionWorld`.
final class ContraptionWorld extends BlockGetter {
  final Contraption contraption;
  final ContraptionLevel parent;
  final int minY;
  final int height;

  ContraptionWorld(this.parent, this.contraption)
    : minY = _nextMultipleOf16((contraption.bounds?.minY ?? 0) - 1),
      height =
          _nextMultipleOf16((contraption.bounds?.maxY ?? 0) + 1) -
          _nextMultipleOf16((contraption.bounds?.minY ?? 0) - 1);

  /// `nextMultipleOf16`.
  static int _nextMultipleOf16(double a) {
    final i = a.toInt();
    final sign = a < 0 ? -1 : 1;
    return ((((i.abs() - 1) | 15) + 1) * sign);
  }

  /// `getBlockState(pos)`.
  @override
  BState stateAt(Pos p) => contraption.blocks[p]?.state ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isFaceSturdy(Pos p, Direction face) =>
      !parent.stateCollisionEmpty(stateAt(p));

  @override
  List<BlockBox> collisionBoxes(Pos p) =>
      parent.stateCollisionBoxes(stateAt(p));

  @override
  bool supportShapeEmpty(Pos p) => parent.stateCollisionEmpty(stateAt(p));

  @override
  bool canBeReplaced(Pos p) => parent.stateReplaceable(stateAt(p));

  @override
  bool hasTag(Pos p, String tag) => parent.stateHasTag(stateAt(p), tag);

  @override
  bool isWater(Pos p) => false;

  /// `getMinY()`.
  int getMinY() => minY;

  /// `getHeight()`.
  int getHeight() => height;
}
