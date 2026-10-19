// Port of `content/equipment/symmetryWand/mirror/*`: the mirror shapes of the
// wand of symmetry. Pure (no host imports).
import '../model/block_state_ops.dart';
import '../model/dir.dart';

typedef V3 = (double, double, double);

/// `SymmetryMirror.EMPTY` ... names used in the saved / network form.
abstract final class MirrorTypes {
  static const empty = 'empty';
  static const plane = 'plane';
  static const crossPlane = 'cross_plane';
  static const triplePlane = 'triple_plane';
}

/// `SymmetryMirror` and its four subclasses. [position] is the mirror's centre
/// (a block corner, as the wand stores it), [orientationIndex] the index into the
/// subclass' `Align` enum.
abstract class SymmetryMirror {
  V3 position;
  int orientationIndex;
  bool enable;

  SymmetryMirror(this.position, {this.orientationIndex = 0, this.enable = true});

  /// `SymmetryMirror.create(orientationIndex, position, type, enable)`.
  factory SymmetryMirror.create(int orientationIndex, V3 position, String type, bool enable) {
    final SymmetryMirror element = switch (type) {
      MirrorTypes.plane => PlaneMirror(position),
      MirrorTypes.crossPlane => CrossPlaneMirror(position),
      MirrorTypes.triplePlane => TriplePlaneMirror(position),
      _ => EmptyMirror(position),
    };
    element.setOrientation(orientationIndex);
    element.enable = enable;
    return element;
  }

  String get typeName;

  /// `setPosition(Vec3)`.
  void setPosition(V3 pos) => position = pos;

  /// The number of orientations of this mirror.
  int get orientationCount;

  /// `rotate(boolean forward)`.
  void rotate(bool forward) {
    orientationIndex += forward ? 1 : -1;
    _wrapOrientation();
  }

  void _wrapOrientation() {
    final n = orientationCount;
    if (n == 0) return;
    if (orientationIndex < 0) orientationIndex += n;
    if (orientationIndex >= n) orientationIndex -= n;
  }

  /// `setOrientation(int)`.
  void setOrientation(int index) {
    orientationIndex = index;
  }

  /// `process(Map)`: adds the mirrored copies of every entry.
  void process(Map<P3, BState> blocks) {
    final result = <P3, BState>{};
    for (final e in blocks.entries.toList()) {
      result.addAll(processOne(e.key, e.value));
    }
    blocks.addAll(result);
  }

  /// `process(BlockPos, BlockState)`: the mirrored copies of one block.
  Map<P3, BState> processOne(P3 pos, BState block);

  // -- helpers (all port 1:1) ---------------------------------------------------

  V3 _diff(P3 p) => (-position.$1 + p.$1, -position.$2 + p.$2, -position.$3 + p.$3);

  /// `getIDiff`: the `(int)` cast truncates toward zero.
  P3 _idiff(P3 p) {
    final d = _diff(p);
    return (d.$1.truncate(), d.$2.truncate(), d.$3.truncate());
  }

  P3 flipXPos(P3 p) {
    final d = _idiff(p);
    return (p.$1 - 2 * d.$1, p.$2, p.$3);
  }

  P3 flipYPos(P3 p) {
    final d = _idiff(p);
    return (p.$1, p.$2 - 2 * d.$2, p.$3);
  }

  P3 flipZPos(P3 p) {
    final d = _idiff(p);
    return (p.$1, p.$2, p.$3 - 2 * d.$3);
  }

  P3 flipD2Pos(P3 p) {
    final d = _idiff(p);
    return (p.$1 - d.$1 + d.$3, p.$2, p.$3 - d.$3 + d.$1);
  }

  P3 flipD1Pos(P3 p) {
    final d = _idiff(p);
    return (p.$1 - d.$1 - d.$3, p.$2, p.$3 - d.$3 - d.$1);
  }

  BState flipXState(BState s) => BlockStateOps.mirror(s, Mir.frontBack);
  BState flipYState(BState s) => BlockStateOps.flipY(s);
  BState flipZState(BState s) => BlockStateOps.mirror(s, Mir.leftRight);
  BState flipD1State(BState s) => BlockStateOps.mirror(BlockStateOps.rotate(s, Rot.counterclockwise90), Mir.frontBack);
  BState flipD2State(BState s) => BlockStateOps.mirror(BlockStateOps.rotate(s, Rot.counterclockwise90), Mir.leftRight);

  SymmetryMirror copy() => SymmetryMirror.create(orientationIndex, position, typeName, enable);

  @override
  bool operator ==(Object other) =>
      other is SymmetryMirror &&
      other.typeName == typeName &&
      other.orientationIndex == orientationIndex &&
      other.enable == enable &&
      other.position == position;

  @override
  int get hashCode => Object.hash(typeName, orientationIndex, enable, position);

  @override
  String toString() => 'SymmetryMirror($typeName, $position, o=$orientationIndex, enable=$enable)';
}

/// `EmptyMirror`.
class EmptyMirror extends SymmetryMirror {
  EmptyMirror(super.position);

  @override
  String get typeName => MirrorTypes.empty;

  @override
  int get orientationCount => 1;

  @override
  void rotate(bool forward) {
    orientationIndex += forward ? 1 : -1;
  }

  @override
  Map<P3, BState> processOne(P3 pos, BState block) => {};
}

/// `PlaneMirror`: [orientationIndex] 0 = `XY` (mirrors along Z), 1 = `YZ` (mirrors along X).
class PlaneMirror extends SymmetryMirror {
  static const xy = 0;
  static const yz = 1;

  PlaneMirror(super.position);

  @override
  String get typeName => MirrorTypes.plane;

  @override
  int get orientationCount => 2;

  @override
  Map<P3, BState> processOne(P3 pos, BState block) {
    final result = <P3, BState>{};
    switch (orientationIndex) {
      case xy:
        result[flipZPos(pos)] = flipZState(block);
      case yz:
        result[flipXPos(pos)] = flipXState(block);
    }
    return result;
  }
}

/// `CrossPlaneMirror`: orientation 0 = `Y` (orthogonal), 1 = `D` (diagonal).
class CrossPlaneMirror extends SymmetryMirror {
  static const y = 0;
  static const d = 1;

  CrossPlaneMirror(super.position);

  @override
  String get typeName => MirrorTypes.crossPlane;

  @override
  int get orientationCount => 2;

  @override
  Map<P3, BState> processOne(P3 pos, BState block) {
    final result = <P3, BState>{};
    switch (orientationIndex) {
      case d:
        result[flipD1Pos(pos)] = flipD1State(block);
        result[flipD2Pos(pos)] = flipD2State(block);
        result[flipD1Pos(flipD2Pos(pos))] = flipD1State(flipD2State(block));
      case y:
        result[flipXPos(pos)] = flipXState(block);
        result[flipZPos(pos)] = flipZState(block);
        result[flipXPos(flipZPos(pos))] = flipXState(flipZState(block));
    }
    return result;
  }
}

/// `TriplePlaneMirror`: no orientation.
class TriplePlaneMirror extends SymmetryMirror {
  TriplePlaneMirror(super.position);

  @override
  String get typeName => MirrorTypes.triplePlane;

  @override
  int get orientationCount => 0;

  @override
  void rotate(bool forward) {
    orientationIndex += forward ? 1 : -1;
  }

  @override
  void setOrientation(int index) {
    // The Java class ignores the index entirely (`orientationIndex` stays 0).
  }

  @override
  Map<P3, BState> processOne(P3 pos, BState block) {
    final result = <P3, BState>{};
    result[flipXPos(pos)] = flipXState(block);
    result[flipZPos(pos)] = flipZState(block);
    result[flipXPos(flipZPos(pos))] = flipXState(flipZState(block));
    result[flipD1Pos(pos)] = flipD1State(block);
    result[flipD1Pos(flipXPos(pos))] = flipD1State(flipXState(block));
    result[flipD1Pos(flipZPos(pos))] = flipD1State(flipZState(block));
    result[flipD1Pos(flipXPos(flipZPos(pos)))] = flipD1State(flipXState(flipZState(block)));
    return result;
  }
}

/// The wire / saved form of a mirror: `orientation_index`, `position`, `type`, `enable`.
extension SymmetryMirrorWire on SymmetryMirror {
  Map<String, Object?> toJson() => {
    'orientation_index': orientationIndex,
    'position': [position.$1, position.$2, position.$3],
    'type': typeName,
    'enable': enable,
  };

  static SymmetryMirror fromJson(Map<String, Object?> m) {
    final pos = (m['position'] as List).cast<num>();
    return SymmetryMirror.create(
      (m['orientation_index'] as num?)?.toInt() ?? 0,
      (pos[0].toDouble(), pos[1].toDouble(), pos[2].toDouble()),
      m['type'] as String? ?? MirrorTypes.empty,
      m['enable'] as bool? ?? true,
    );
  }
}

/// How the wand chooses the plane orientation when placed (`SymmetryWandItem.useOn`).
abstract final class SymmetryWandPlacement {
  /// Plane orientation from the player's horizontal facing.
  static int planeOrientationFor(Dir playerFacing) =>
      (playerFacing == Dir.north || playerFacing == Dir.south) ? PlaneMirror.xy : PlaneMirror.yz;

  /// Cross plane orientation from the head yaw (`getYHeadRot`).
  static int crossOrientationFor(double headYaw) {
    // Java `%` keeps the sign of the dividend; `abs(rotation % 90)`.
    final abs = (headYaw.remainder(90)).abs();
    final diagonal = abs > 22 && abs < 45 + 22;
    return diagonal ? CrossPlaneMirror.d : CrossPlaneMirror.y;
  }
}
